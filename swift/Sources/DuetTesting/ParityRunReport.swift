// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// One recorded failure inside a fixture/scenario run. `kind` is `state` / `effects`
/// (byte-gate divergences), `assertion` (a local Then closure), or `structure`
/// (missing/stale fixture, step-count drift). `node` names the acting node in chain
/// fixtures (nil for single-feature fixtures). `rendered` is the runner's own
/// human-formatted block — tools print it verbatim instead of re-implementing the
/// format (one formatter per platform, none in the CLI).
public struct ParityRunFailure {
  public var step: Int?
  public var label: String?
  public var line: Int?
  public var kind: String
  public var node: String?
  public var path: String?
  public var expected: String?
  public var actual: String?
  public var action: String?
  public var message: String?
  public var rendered: String?

  public init(
    step: Int? = nil, label: String? = nil, line: Int? = nil, kind: String,
    node: String? = nil, path: String? = nil, expected: String? = nil,
    actual: String? = nil, action: String? = nil, message: String? = nil
  ) {
    self.step = step
    self.label = label
    self.line = line
    self.kind = kind
    self.node = node
    self.path = path
    self.expected = expected
    self.actual = actual
    self.action = action
    self.message = message
  }
}

/// Machine-readable run reports for the `verify` CLI: each fixture run writes
/// `parity/.runs/<platform>/<fixture>.json` (pass or fail), so `verify explain` can map
/// a red lane to scenario source, step label, and first-divergence path without
/// re-parsing test logs. One file per fixture — concurrency-safe without locks.
/// Kotlin mirror: kernel-testsupport RunReport.kt.
public enum ParityRunReport {
  /// Best-effort: report writing must never fail the test run itself.
  /// `besideFixtures` is the consumer repo's resolved fixtures directory — reports
  /// land in its sibling `.runs/<platform>/`.
  public static func write(
    fixture: String,
    feature: String?,
    platform: String = "swift",
    status: String,
    steps: Int?,
    scenarioSource: String?,
    failures: [ParityRunFailure],
    besideFixtures fixturesDirectory: URL
  ) {
    do {
      let directory = fixturesDirectory
        .deletingLastPathComponent()
        .appendingPathComponent(".runs/\(platform)", isDirectory: true)
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true)
      var document: [String: Any] = [
        "fixture": fixture,
        "platform": platform,
        "status": status,
        "failures": failures.map(json(of:)),
      ]
      document["feature"] = feature
      document["steps"] = steps
      document["scenarioSource"] = scenarioSource
      let data = try JSONSerialization.data(
        withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
      try data.write(to: directory.appendingPathComponent("\(fixture).json"))
    } catch {
      FileHandle.standardError.write(
        Data("ParityRunReport: could not write report for '\(fixture)': \(error)\n".utf8))
    }
  }

  private static func json(of failure: ParityRunFailure) -> [String: Any] {
    var object: [String: Any] = ["kind": failure.kind]
    object["step"] = failure.step
    object["label"] = failure.label
    object["line"] = failure.line
    object["node"] = failure.node
    object["path"] = failure.path
    object["expected"] = failure.expected
    object["actual"] = failure.actual
    object["action"] = failure.action
    object["message"] = failure.message
    object["rendered"] = failure.rendered
    return object
  }
}
