// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import Duet
import XCTest

/// Replays a shared golden fixture (`parity/fixtures/<name>.fixture.json`) against the
/// **pure reducer only** — no runtime, no handlers, no clocks. Runner semantics:
/// contracts/serialization.md §5. Kotlin mirror: `kernel-testsupport` FixtureRunner.kt.
///
/// Dialect 2: fixtures may carry `scenario.source`, per-step `label`/`line`, and
/// `dialect: 2`. All of it is *metadata* — the byte gate still compares only
/// `action`/`expectedState`/`expectedEffects`. On divergence the runner reports the
/// first divergent JSON path (FixtureDiff), the step label, and the scenario source
/// line, and writes a machine-readable report (ParityRunReport) for `verify explain`.
public enum FixtureRunner {
  public enum FixtureError: Error, CustomStringConvertible {
    case repoRootNotFound(startedFrom: String)
    case fixtureNotFound(String)
    case malformed(String)

    public var description: String {
      switch self {
      case let .repoRootNotFound(start):
        return "Could not locate parity/fixtures walking up from \(start)"
      case let .fixtureNotFound(path):
        return "Fixture not found: \(path)"
      case let .malformed(detail):
        return "Malformed fixture: \(detail)"
      }
    }
  }

  /// Resolves `parity/fixtures` by walking up from this source file's compiled-in path —
  /// both platforms read the same files, so drift is structurally impossible.
  public static func fixturesDirectory(
    startingFrom path: String = #filePath
  ) throws -> URL {
    var directory = URL(fileURLWithPath: path).deletingLastPathComponent()
    while directory.path != "/" {
      let candidate = directory.appendingPathComponent("parity/fixtures", isDirectory: true)
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
      directory.deleteLastPathComponent()
    }
    throw FixtureError.repoRootNotFound(startedFrom: path)
  }

  /// Repo-relative form of an absolute source path (for fixture metadata + reports);
  /// nil when the repo root can't be located from it.
  static func repoRelativePath(of absolute: String) -> String? {
    guard let fixturesDir = try? fixturesDirectory(startingFrom: absolute) else {
      return nil
    }
    let root = fixturesDir.deletingLastPathComponent().deletingLastPathComponent().path
    guard absolute.hasPrefix(root + "/") else { return nil }
    return String(absolute.dropFirst(root.count + 1))
  }

  /// A parsed fixture document: raw JSON trees plus the dialect-2 metadata (nil on v1).
  public struct Document {
    public let url: URL
    public let feature: String?
    public let dialect: Int
    public let scenarioSource: String?
    public let rawInitialState: Any
    public let rawSteps: [[String: Any]]

    /// `fixturesDirectory` must be resolved from a path in the CONSUMER's repo
    /// (a test file's `#filePath`, a scenario's `sourceFile`) — this library may
    /// live in a dependency checkout, so its own source location proves nothing.
    public static func load(fixture name: String, in fixturesDirectory: URL) throws -> Document {
      let url = fixturesDirectory.appendingPathComponent("\(name).fixture.json")
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw FixtureError.fixtureNotFound(url.path)
      }
      let data = try Data(contentsOf: url)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw FixtureError.malformed("root is not an object")
      }
      guard let rawInitialState = root["initialState"],
        let rawSteps = root["steps"] as? [[String: Any]]
      else {
        throw FixtureError.malformed("missing initialState/steps")
      }
      return Document(
        url: url,
        feature: root["feature"] as? String,
        dialect: root["dialect"] as? Int ?? 1,
        scenarioSource: (root["scenario"] as? [String: Any])?["source"] as? String,
        rawInitialState: rawInitialState,
        rawSteps: rawSteps)
    }
  }

  /// The canonical decoder both fixture paths share (dates in the pinned millis form).
  public static func canonicalDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(CanonicalJSON.iso8601Millis)
    return decoder
  }

  /// Byte-gate for one step: canonical-compares recorded vs actual state and effects;
  /// on mismatch returns a failure carrying the first divergent JSON path. Shared by
  /// this runner and ScenarioRunner so both report in the same shape.
  public static func stepDivergence<State, Payload>(
    stepIndex: Int,
    label: String?,
    line: Int?,
    rawExpectedState: Any,
    rawExpectedEffects: Any,
    state: State,
    effects: [Effect<Payload>],
    actionCanonical: String
  ) throws -> ParityRunFailure?
  where State: Codable, Payload: Codable & Equatable {
    let actualState = try CanonicalJSON.canonicalString(of: state)
    let expectedState = try CanonicalJSON.canonicalString(fromJSONObject: rawExpectedState)
    if actualState != expectedState {
      let divergence = try FixtureDiff.firstDivergence(
        expected: rawExpectedState, actual: reparse(actualState))
      return ParityRunFailure(
        step: stepIndex, label: label, line: line, kind: "state",
        path: divergence?.path, expected: divergence?.expected, actual: divergence?.actual,
        action: actionCanonical)
    }
    let actualEffects = try CanonicalJSON.canonicalString(of: effects)
    let expectedEffects = try CanonicalJSON.canonicalString(fromJSONObject: rawExpectedEffects)
    if actualEffects != expectedEffects {
      let divergence = try FixtureDiff.firstDivergence(
        expected: rawExpectedEffects, actual: reparse(actualEffects))
      return ParityRunFailure(
        step: stepIndex, label: label, line: line, kind: "effects",
        path: divergence?.path, expected: divergence?.expected, actual: divergence?.actual,
        action: actionCanonical)
    }
    return nil
  }

  /// The shared human failure block — ONE formatter per platform (the runner's own),
  /// none in the tools: the rendered text is embedded in the run report (`rendered`)
  /// and `verify`/`verify explain` print it verbatim. Shape pinned cross-platform by
  /// the formatter golden (parity/fixtures/formatter.golden.txt).
  public static func format(
    _ failure: ParityRunFailure, fixture: String, scenarioSource: String?,
    platform: String = "swift"
  ) -> String {
    var lines = [String]()
    let subject = failure.node == nil ? "fixture" : "chain"
    let node = failure.node.map { " (\($0))" } ?? ""
    let label = failure.label.map { " '\($0)'" } ?? ""
    let step = failure.step.map { " step \($0)" } ?? ""
    let verdict = failure.kind == "assertion" ? "Then failed" : "\(failure.kind) diverged"
    lines.append("✗ \(subject) '\(fixture)'\(step)\(node)\(label) — \(verdict)")
    if let path = failure.path {
      let joiner = path.hasPrefix("[") ? "" : "."
      switch failure.kind {
      case "effects": lines.append("  at expectedEffects\(joiner)\(path)")
      case "state": lines.append("  at expectedState\(joiner)\(path)")
      default: lines.append("  at \(path)")  // pre-rooted (assertion enrichment)
      }
    }
    if failure.expected != nil || failure.actual != nil {
      lines.append(
        "  expected: \(failure.expected ?? "∅")   actual: \(failure.actual ?? "∅")")
    }
    if let action = failure.action {
      lines.append("  action: \(action)")
    }
    if let source = scenarioSource {
      let line = failure.line.map { ":\($0)" } ?? ""
      lines.append("  scenario: \(source)\(line)")
    }
    if let message = failure.message {
      lines.append("  \(message)")
    }
    let divergent = failure.kind == "state" || failure.kind == "effects"
      || (failure.kind == "assertion" && failure.path != nil)
    if let step = failure.step, divergent {
      lines.append("  next: verify materialize \(fixture)#\(step) --platform \(platform)")
    }
    return lines.joined(separator: "\n")
  }

  public static func run<State, Action, Payload>(
    fixture name: String,
    initialStateType _: State.Type = State.self,
    reducer: (inout State, Action) -> [Effect<Payload>],
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws
  where
    State: Equatable & Codable, Action: Codable, Payload: Equatable & Codable
  {
    // Resolve from the calling test file — the consumer repo owns the fixtures.
    let fixturesDir = try fixturesDirectory(startingFrom: String(describing: file))
    let document = try Document.load(fixture: name, in: fixturesDir)
    let decoder = canonicalDecoder()
    var state = try decoder.decode(
      State.self, from: JSONSerialization.data(withJSONObject: document.rawInitialState))

    for (index, rawStep) in document.rawSteps.enumerated() {
      guard let rawAction = rawStep["action"],
        let rawExpectedState = rawStep["expectedState"],
        let rawExpectedEffects = rawStep["expectedEffects"]
      else {
        throw FixtureError.malformed("step \(index) missing action/expectedState/expectedEffects")
      }
      let action = try decoder.decode(
        Action.self, from: JSONSerialization.data(withJSONObject: rawAction))

      let effects = reducer(&state, action)

      if var failure = try stepDivergence(
        stepIndex: index,
        label: rawStep["label"] as? String,
        line: rawStep["line"] as? Int,
        rawExpectedState: rawExpectedState,
        rawExpectedEffects: rawExpectedEffects,
        state: state,
        effects: effects,
        actionCanonical: CanonicalJSON.canonicalString(fromJSONObject: rawAction))
      {
        failure.rendered = format(
          failure, fixture: name, scenarioSource: document.scenarioSource)
        ParityRunReport.write(
          fixture: name, feature: document.feature, status: "failed",
          steps: document.rawSteps.count, scenarioSource: document.scenarioSource,
          failures: [failure], besideFixtures: fixturesDir)
        // Stop at the first divergence: post-divergence steps replay against poisoned
        // state and only produce cascade noise.
        XCTFail(failure.rendered ?? failure.kind, file: file, line: line)
        return
      }
    }
    ParityRunReport.write(
      fixture: name, feature: document.feature, status: "passed",
      steps: document.rawSteps.count, scenarioSource: document.scenarioSource,
      failures: [], besideFixtures: fixturesDir)
  }

  private static func reparse(_ canonical: String) throws -> Any {
    try JSONSerialization.jsonObject(
      with: Data(canonical.utf8), options: [.fragmentsAllowed])
  }
}
