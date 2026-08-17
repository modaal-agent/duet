// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import Duet
import XCTest

/// Executes a `Scenario` in one of two modes:
///
/// - **record** (`REGEN_FIXTURES=1`): drives the pure reducer through every *variant*
///   of the scenario (a linear scenario is one variant; `Branch`es fork into one
///   variant per root→leaf path), runs every local `Then`, and compiles one dialect-2
///   fixture per variant into `parity/fixtures/`. Fixtures are build products — never
///   hand-edited; the scenario runners are the only writers.
/// - **verify**: drives the reducer through every variant AND byte-gates each step
///   against the committed fixture. A step's trailing local `Then`s run BEFORE its
///   byte gate: a failing Then states the author's *intent* and wins the header, with
///   the byte divergence riding along as detail. Scenario-vs-fixture drift (edited
///   scenario, stale fixture) is reported as `structure` with a regen hint instead of
///   a fake divergence.
public enum ScenarioRunner {
  public enum ScenarioError: Error, CustomStringConvertible {
    case malformed(String)

    public var description: String {
      switch self {
      case let .malformed(detail):
        return "Malformed scenario: \(detail)"
      }
    }
  }

  static let platform = "swift"

  public static func verifyOrRecord<State, Action, Payload>(
    _ scenario: Scenario<State, Action, Payload>,
    reducer: (inout State, Action) -> [Effect<Payload>]
  ) throws
  where State: Equatable & Codable, Action: Codable, Payload: Equatable & Codable {
    if FixtureRecorder.regenerationRequested {
      try record(scenario, reducer: reducer)
    }
    try verify(scenario, reducer: reducer)
  }

  // MARK: - Record

  @discardableResult
  public static func record<State, Action, Payload>(
    _ scenario: Scenario<State, Action, Payload>,
    reducer: (inout State, Action) -> [Effect<Payload>]
  ) throws -> [URL]
  where State: Equatable & Codable, Action: Codable, Payload: Equatable & Codable {
    let variants = try Variants(scenario: scenario)
    let source = repoRelativeSource(of: scenario)
    let fixturesDir = try FixtureRunner.fixturesDirectory(
      startingFrom: String(describing: scenario.sourceFile))
    var urls: [URL] = []
    for variant in variants.all {
      var steps: [[String: Any]] = []
      try variants.walk(
        variant,
        reducer: reducer,
        onStep: { step, state, effects in
          steps.append([
            "label": step.label,
            "line": Int(step.line),
            "action": try jsonTree(of: step.action),
            "expectedState": try jsonTree(of: state),
            "expectedEffects": try jsonTree(of: effects),
          ])
        },
        onFailedAssertion: { failure, _, _, _ in
          // A false Then during record is an authoring error — nothing is written.
          XCTFail(
            FixtureRunner.format(
              failure, fixture: variant.fixture, scenarioSource: source,
              platform: platform),
            file: scenario.sourceFile, line: UInt(failure.line ?? 0))
          throw ScenarioError.malformed(
            "Then '\(failure.label ?? "?")' failed during record — fixture not written")
        })

      var scenarioMeta: [String: Any] = [
        "source": source ?? String(describing: scenario.sourceFile)
      ]
      if !variant.slugs.isEmpty {
        scenarioMeta["branch"] = variant.slugs.joined(separator: ".")
      }
      let document: [String: Any] = [
        "dialect": 2,
        "feature": scenario.feature,
        "description": scenario.description,
        "scenario": scenarioMeta,
        "initialState": try jsonTree(of: try variants.initialState()),
        "steps": steps,
      ]
      let url = fixturesDir
        .appendingPathComponent("\(variant.fixture).fixture.json")
      // §6 pretty form — the one writer (ReplayCanonical), shared with the CLI.
      try Data(CanonicalJSON.prettyCanonicalString(fromJSONObject: document).utf8)
        .write(to: url)
      print("ScenarioRunner: recorded \(variant.fixture).fixture.json (\(steps.count) steps)")
      urls.append(url)
    }
    return urls
  }

  // MARK: - Verify

  public static func verify<State, Action, Payload>(
    _ scenario: Scenario<State, Action, Payload>,
    reducer: (inout State, Action) -> [Effect<Payload>]
  ) throws
  where State: Equatable & Codable, Action: Codable, Payload: Equatable & Codable {
    let variants = try Variants(scenario: scenario)
    for variant in variants.all {
      try verifyVariant(variant, in: variants, of: scenario, reducer: reducer)
    }
  }

  private static func verifyVariant<State, Action, Payload>(
    _ variant: Variants<State, Action, Payload>.Variant,
    in variants: Variants<State, Action, Payload>,
    of scenario: Scenario<State, Action, Payload>,
    reducer: (inout State, Action) -> [Effect<Payload>]
  ) throws
  where State: Equatable & Codable, Action: Codable, Payload: Equatable & Codable {
    let source = repoRelativeSource(of: scenario)
    let fixture = variant.fixture
    let fixturesDir = try FixtureRunner.fixturesDirectory(
      startingFrom: String(describing: scenario.sourceFile))

    var reported = false
    func report(_ rawFailure: ParityRunFailure, steps: Int?, at line: UInt) {
      reported = true
      var failure = rawFailure
      failure.rendered = FixtureRunner.format(
        failure, fixture: fixture, scenarioSource: source, platform: platform)
      ParityRunReport.write(
        fixture: fixture, feature: scenario.feature, status: "failed",
        steps: steps, scenarioSource: source, failures: [failure],
        besideFixtures: fixturesDir)
      XCTFail(failure.rendered ?? failure.kind, file: scenario.sourceFile, line: line)
    }

    let document: FixtureRunner.Document
    do {
      document = try FixtureRunner.Document.load(fixture: fixture, in: fixturesDir)
    } catch {
      report(
        ParityRunFailure(
          kind: "structure",
          message: "fixture missing or unreadable (\(error)) — record it: "
            + "verify record --feature \(scenario.feature)"),
        steps: nil, at: 1)
      return
    }
    if document.dialect < 2 {
      report(
        ParityRunFailure(
          kind: "structure",
          message: "fixture is dialect \(document.dialect) (pre-scenario) — regenerate: "
            + "verify record --feature \(scenario.feature)"),
        steps: nil, at: 1)
      return
    }

    let expectedInitial = try CanonicalJSON.canonicalString(
      fromJSONObject: document.rawInitialState)
    let actualInitial = try CanonicalJSON.canonicalString(of: try variants.initialState())
    if expectedInitial != actualInitial {
      report(
        ParityRunFailure(
          kind: "structure",
          message: "scenario Given drifted from recorded initialState — regenerate: "
            + "verify record --feature \(scenario.feature)"),
        steps: nil, at: 1)
      return
    }
    let whenCount = variants.whenCount(variant)
    if whenCount != document.rawSteps.count {
      report(
        ParityRunFailure(
          kind: "structure",
          message: "scenario has \(whenCount) When step(s) but fixture has "
            + "\(document.rawSteps.count) — regenerate: verify record --feature \(scenario.feature)"),
        steps: nil, at: 1)
      return
    }

    try variants.walk(
      variant,
      reducer: reducer,
      onStep: { step, state, effects in
        let rawStep = document.rawSteps[step.index]
        guard let rawAction = rawStep["action"],
          let rawExpectedState = rawStep["expectedState"],
          let rawExpectedEffects = rawStep["expectedEffects"]
        else {
          report(
            ParityRunFailure(
              step: step.index, label: step.label, line: Int(step.line), kind: "structure",
              message: "fixture step \(step.index) is malformed — regenerate"),
            steps: document.rawSteps.count, at: step.line)
          throw StopWalk()
        }
        // Drift gate: the fixture step must have been compiled from THIS action.
        let scenarioAction = try CanonicalJSON.canonicalString(of: step.action)
        let fixtureAction = try CanonicalJSON.canonicalString(fromJSONObject: rawAction)
        if scenarioAction != fixtureAction {
          report(
            ParityRunFailure(
              step: step.index, label: step.label, line: Int(step.line), kind: "structure",
              action: scenarioAction,
              message: "scenario action drifted from fixture (recorded: \(fixtureAction)) "
                + "— regenerate: verify record --feature \(scenario.feature)"),
            steps: document.rawSteps.count, at: step.line)
          throw StopWalk()
        }
        if let failure = try FixtureRunner.stepDivergence(
          stepIndex: step.index, label: step.label, line: Int(step.line),
          rawExpectedState: rawExpectedState, rawExpectedEffects: rawExpectedEffects,
          state: state, effects: effects, actionCanonical: scenarioAction)
        {
          report(failure, steps: document.rawSteps.count, at: step.line)
          throw StopWalk()
        }
      },
      onFailedAssertion: { failure, pending, state, effects in
        // The Then's intent-framed failure wins the header; if the step's byte gate
        // (still pending — Thens run first) also diverges, the path and fragments
        // ride along as detail.
        var enriched = failure
        if let pending, pending.index < document.rawSteps.count,
          let rawExpectedState = document.rawSteps[pending.index]["expectedState"],
          let rawExpectedEffects = document.rawSteps[pending.index]["expectedEffects"],
          let divergence = try? FixtureRunner.stepDivergence(
            stepIndex: pending.index, label: pending.label, line: Int(pending.line),
            rawExpectedState: rawExpectedState, rawExpectedEffects: rawExpectedEffects,
            state: state, effects: effects,
            actionCanonical: (try? CanonicalJSON.canonicalString(of: pending.action)) ?? ""),
          let divergencePath = divergence.path
        {
          let root = divergence.kind == "effects" ? "expectedEffects" : "expectedState"
          let joiner = divergencePath.hasPrefix("[") ? "" : "."
          enriched.path = "\(root)\(joiner)\(divergencePath)"
          enriched.expected = divergence.expected
          enriched.actual = divergence.actual
          enriched.message =
            (enriched.message ?? "")
            + " — the step's \(divergence.kind) also diverged from the fixture"
        }
        report(enriched, steps: document.rawSteps.count, at: UInt(failure.line ?? 0))
        throw StopWalk()
      })

    if !reported {
      ParityRunReport.write(
        fixture: fixture, feature: scenario.feature, status: "passed",
        steps: document.rawSteps.count, scenarioSource: source, failures: [],
        besideFixtures: fixturesDir)
    }
  }

  // MARK: - Variants (branch expansion + the walk)

  /// Thrown by callbacks to end a variant's walk early after a reported failure;
  /// swallowed by `walk` so the caller sees exactly one XCTFail per variant.
  private struct StopWalk: Error {}

  struct FlatWhen<Action> {
    let index: Int
    let label: String
    let line: UInt
    let action: Action
  }

  /// The scenario's branch tree expanded into linear variants: one per root→leaf path
  /// (exactly one, unsuffixed, when the scenario has no `Branch`). Each variant's node
  /// list is fully linear — branch content is re-wrapped as a `Context` so labels and
  /// the walk need no branch awareness downstream.
  struct Variants<State, Action, Payload: Equatable> {
    struct Variant {
      let slugs: [String]
      let fixture: String
      let nodes: [ScenarioNode<State, Action, Payload>]
    }

    let scenario: Scenario<State, Action, Payload>
    let all: [Variant]

    init(scenario: Scenario<State, Action, Payload>) throws {
      guard case .given = scenario.nodes.first else {
        throw ScenarioError.malformed(
          "scenario '\(scenario.fixture)' must start with Given(initialState)")
      }
      self.scenario = scenario
      self.all = try Self.expand(scenario.nodes).map { slugs, nodes in
        Variant(
          slugs: slugs,
          fixture: slugs.isEmpty
            ? scenario.fixture
            : "\(scenario.fixture).\(slugs.joined(separator: "."))",
          nodes: nodes)
      }
      let names = all.map(\.fixture)
      guard Set(names).count == names.count else {
        throw ScenarioError.malformed(
          "branch labels collide after slugification: \(names.sorted())")
      }
    }

    func initialState() throws -> State {
      guard case let .given(state, _) = scenario.nodes.first else {
        throw ScenarioError.malformed("missing Given")
      }
      return state
    }

    func whenCount(_ variant: Variant) -> Int {
      func count(_ nodes: [ScenarioNode<State, Action, Payload>]) -> Int {
        nodes.reduce(0) { total, node in
          switch node {
          case .when: return total + 1
          case let .context(_, _, children): return total + count(children)
          default: return total
          }
        }
      }
      return count(variant.nodes)
    }

    /// Splits a node list at its first `Branch`: everything before is the shared
    /// prefix; everything after must also be a `Branch` (branches are alternate
    /// ENDINGS — the no-conditionals rule holds because the structure is static: every branch
    /// always runs, no runtime value chooses). A `Context` whose children fork must
    /// be the last node at its level, and its variants bubble up.
    private static func expand(
      _ nodes: [ScenarioNode<State, Action, Payload>]
    ) throws -> [(slugs: [String], nodes: [ScenarioNode<State, Action, Payload>])] {
      for (index, node) in nodes.enumerated() {
        switch node {
        case let .branch(_, line, _):
          let tail = Array(nodes[index...])
          var branches: [(label: String, line: UInt, children: [ScenarioNode<State, Action, Payload>])] = []
          for sibling in tail {
            guard case let .branch(label, line, children) = sibling else {
              throw ScenarioError.malformed(
                "only Branch nodes may follow a Branch at the same level "
                  + "(branches are alternate endings; line \(line))")
            }
            branches.append((label, line, children))
          }
          let slugs = try branches.map { try slugify($0.label) }
          guard Set(slugs).count == slugs.count else {
            throw ScenarioError.malformed("sibling Branch labels collide: \(slugs.sorted())")
          }
          let prefix = Array(nodes[..<index])
          var variants: [(slugs: [String], nodes: [ScenarioNode<State, Action, Payload>])] = []
          for (branch, slug) in zip(branches, slugs) {
            for sub in try expand(branch.children) {
              variants.append((
                slugs: [slug] + sub.slugs,
                nodes: prefix + [.context(label: branch.label, line: branch.line, nodes: sub.nodes)]
              ))
            }
          }
          return variants
        case let .context(label, line, children):
          let subs = try expand(children)
          if subs.count == 1, subs[0].slugs.isEmpty { continue }  // plain linear context
          guard index == nodes.count - 1 else {
            throw ScenarioError.malformed(
              "a Context containing Branches must be the last node at its level "
                + "('\(label)')")
          }
          let prefix = Array(nodes[..<index])
          return subs.map { sub in
            (
              slugs: sub.slugs,
              nodes: prefix + [.context(label: label, line: line, nodes: sub.nodes)]
            )
          }
        default:
          continue
        }
      }
      return [([], nodes)]
    }

    /// Branch label → fixture-name slug: lowercased, non-alphanumeric runs collapse
    /// to `-`. Slugs must be non-empty and unique among siblings.
    private static func slugify(_ label: String) throws -> String {
      var out = ""
      var pendingDash = false
      for scalar in label.lowercased().unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
          if pendingDash, !out.isEmpty { out.append("-") }
          pendingDash = false
          out.unicodeScalars.append(scalar)
        } else {
          pendingDash = true
        }
      }
      guard !out.isEmpty else {
        throw ScenarioError.malformed("Branch label '\(label)' slugifies to nothing")
      }
      return out
    }

    /// Depth-first walk of one variant: reduces on every When, runs Then/ThenEffects
    /// as they appear, and fires `onStep` (the byte gate / record sink) for a When
    /// only after its trailing Thens — i.e. just before the next When, and at walk
    /// end. `onFailedAssertion` receives the still-pending step so the caller can
    /// attach byte-gate detail to an intent-framed Then failure. `StopWalk` from a
    /// callback ends the walk quietly; other errors propagate.
    func walk(
      _ variant: Variant,
      reducer: (inout State, Action) -> [Effect<Payload>],
      onStep: (FlatWhen<Action>, State, [Effect<Payload>]) throws -> Void,
      onFailedAssertion: (ParityRunFailure, FlatWhen<Action>?, State, [Effect<Payload>]) throws -> Void
    ) throws {
      var state = try initialState()
      var lastEffects: [Effect<Payload>] = []
      var stepIndex = 0
      var contextPath: [String] = []
      var pending: FlatWhen<Action>?

      func flushPendingGate() throws {
        if let step = pending {
          pending = nil
          try onStep(step, state, lastEffects)
        }
      }

      func visit(_ nodes: [ScenarioNode<State, Action, Payload>], isRoot: Bool) throws {
        for (offset, node) in nodes.enumerated() {
          switch node {
          case .given:
            guard isRoot && offset == 0 else {
              throw ScenarioError.malformed("Given must be the first node (and only there)")
            }
          case let .when(label, action, line):
            try flushPendingGate()
            let joined = (contextPath + [label]).joined(separator: " › ")
            let effects = reducer(&state, action)
            lastEffects = effects
            pending = FlatWhen(index: stepIndex, label: joined, line: line, action: action)
            stepIndex += 1
          case let .then(label, line, assert):
            if !assert(state) {
              try onFailedAssertion(
                ParityRunFailure(
                  step: stepIndex > 0 ? stepIndex - 1 : nil,
                  label: (contextPath + [label]).joined(separator: " › "),
                  line: Int(line), kind: "assertion",
                  message: "Then returned false against the current state"),
                pending, state, lastEffects)
            }
          case let .thenEffects(label, line, assert):
            if !assert(lastEffects) {
              try onFailedAssertion(
                ParityRunFailure(
                  step: stepIndex > 0 ? stepIndex - 1 : nil,
                  label: (contextPath + [label]).joined(separator: " › "),
                  line: Int(line), kind: "assertion",
                  message: "ThenEffects returned false against the last emitted effects"),
                pending, state, lastEffects)
            }
          case let .context(label, _, children):
            contextPath.append(label)
            try visit(children, isRoot: false)
            contextPath.removeLast()
          case .branch:
            throw ScenarioError.malformed(
              "walk over an unexpanded Branch — Variants.expand must run first")
          }
        }
      }

      do {
        try visit(variant.nodes, isRoot: true)
        try flushPendingGate()
      } catch is StopWalk {
        // Reported by the callback; end quietly.
      }
    }
  }

  // MARK: - Helpers

  private static func jsonTree<T: Encodable>(of value: T) throws -> Any {
    let canonical = try CanonicalJSON.canonicalString(of: value)
    return try JSONSerialization.jsonObject(
      with: Data(canonical.utf8), options: [.fragmentsAllowed])
  }

  /// Repo-relative path of the scenario source (for fixture metadata + reports); nil
  /// when the repo root can't be located from the source path.
  private static func repoRelativeSource<State, Action, Payload>(
    of scenario: Scenario<State, Action, Payload>
  ) -> String? {
    FixtureRunner.repoRelativePath(of: String(describing: scenario.sourceFile))
  }
}
