// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import Duet
import XCTest

/// The chain dialect, scenario-authored (FT round 2). A chain scenario pins a
/// composition SEAM across nodes: per-step `node` + `action` + `expectedEffects`
/// (never `expectedState` — state evolution belongs to the leaf fixtures), and a
/// `Hop` carrying the delegate→parent-action mapping the shells implement in
/// production. Recording marks the delegate-emitting step `linkToNext: true`, so the
/// fixture-side replay (Kotlin ChainRunner) can assert the forwarding invariant
/// byte-level without any typed mapping.
///
/// Node handles are declared NEXT TO the scenario (each chain owns its seeds):
///
///     let picker = ChainNode("sharepicker", initial: SharePickerState(…), reducer: sharePickerReducer)
///     let timeline = ChainNode("timeline", initial: TimelineState(…), reducer: timelineReducer)
///     let shareApply = ChainScenario(chain: "share-apply", description: "…") {
///       When(picker, "apply emits the applied delegate", .applyTapped)
///       Hop("the feed-share seam", from: picker, to: timeline) { (d: SharePickerDelegate) in
///         .sharePicker(d)
///       }
///       ThenEffects(timeline, "the sheet closes into applyShareSelection") { … }
///     }
///
/// The `Hop` closure's input type must be written explicitly (`(d: SharePickerDelegate)`)
/// — it is what the recorded delegate payload is decoded as. No Context/Branch in
/// chains (they are short seam pins, not narratives).
public struct ChainNode<State, Action, Payload>
where State: Codable, Action: Codable, Payload: Equatable & Codable {
  let key: String
  let initial: State
  let reducer: (inout State, Action) -> [Effect<Payload>]

  public init(
    _ key: String, initial: State,
    reducer: @escaping (inout State, Action) -> [Effect<Payload>]
  ) {
    self.key = key
    self.initial = initial
    self.reducer = reducer
  }
}

/// Chain handles and scenarios are authored as immutable file-scope constants, like
/// `Scenario` — same `@unchecked Sendable` grounds: value-typed triples per the
/// serialization contract, pure reducers, single-domain runner walks.
extension ChainNode: @unchecked Sendable {}

/// One authored chain statement (type-erased — a chain spans several (S, A, P) triples).
public struct ChainStep {
  enum Kind {
    case when(
      nodeKey: String, label: String, line: UInt,
      makeBox: () -> ChainBoxing,
      actionTree: () throws -> Any,
      apply: (ChainBoxing) throws -> Any)
    case hop(
      fromKey: String, toKey: String, label: String, line: UInt,
      makeToBox: () -> ChainBoxing,
      derive: (Any) throws -> (actionTree: Any, apply: (ChainBoxing) throws -> Any))
    case then(
      nodeKey: String, label: String, line: UInt, isEffects: Bool,
      assert: (ChainBoxing) throws -> Bool)
  }

  let kind: Kind
}

/// A dispatched action on one node — one fixture step.
public func When<State, Action, Payload>(
  _ node: ChainNode<State, Action, Payload>, _ label: String, _ action: Action,
  line: UInt = #line
) -> ChainStep
where State: Codable, Action: Codable, Payload: Equatable & Codable {
  ChainStep(
    kind: .when(
      nodeKey: node.key, label: label, line: line,
      makeBox: { ChainBox(node: node) },
      actionTree: { try ChainScenarioRunner.jsonTree(of: action) },
      apply: { boxing in
        let box = try ChainBox<State, Action, Payload>.cast(boxing)
        return try box.reduce(action)
      }))
}

/// The seam statement: the PREVIOUS step's final `notifyListener` payload, decoded as
/// `Delegate`, mapped through the same delegate→action forwarding the parent's shell
/// performs — one fixture step on the `to` node, with the previous step marked
/// `linkToNext`. The mapping is re-derived at verify time from the actual replayed
/// payload, so an edited seam (or a drifted delegate) fails as `structure` drift.
public func Hop<FromState, FromAction, FromPayload, ToState, ToAction, ToPayload, Delegate>(
  _ label: String,
  from: ChainNode<FromState, FromAction, FromPayload>,
  to: ChainNode<ToState, ToAction, ToPayload>,
  line: UInt = #line,
  _ map: @escaping (Delegate) -> ToAction
) -> ChainStep where Delegate: Codable {
  ChainStep(
    kind: .hop(
      fromKey: from.key, toKey: to.key, label: label, line: line,
      makeToBox: { ChainBox(node: to) },
      derive: { payloadTree in
        let data = try JSONSerialization.data(
          withJSONObject: payloadTree, options: [.fragmentsAllowed])
        let delegate = try FixtureRunner.canonicalDecoder().decode(Delegate.self, from: data)
        let action = map(delegate)
        return (
          try ChainScenarioRunner.jsonTree(of: action),
          { boxing in
            let box = try ChainBox<ToState, ToAction, ToPayload>.cast(boxing)
            return try box.reduce(action)
          }
        )
      }))
}

/// Local state assertion on one node (authoring-platform only — chains never record
/// state; this is the code-pointer assert the effects-only fixture can't carry).
public func Then<State, Action, Payload>(
  _ node: ChainNode<State, Action, Payload>, _ label: String, line: UInt = #line,
  _ assert: @escaping (State) -> Bool
) -> ChainStep
where State: Codable, Action: Codable, Payload: Equatable & Codable {
  ChainStep(
    kind: .then(
      nodeKey: node.key, label: label, line: line, isEffects: false,
      assert: { boxing in
        let box = try ChainBox<State, Action, Payload>.cast(boxing)
        return assert(box.state)
      }))
}

/// Local assertion on the effects the node emitted at its most recent step.
public func ThenEffects<State, Action, Payload>(
  _ node: ChainNode<State, Action, Payload>, _ label: String, line: UInt = #line,
  _ assert: @escaping ([Effect<Payload>]) -> Bool
) -> ChainStep
where State: Codable, Action: Codable, Payload: Equatable & Codable {
  ChainStep(
    kind: .then(
      nodeKey: node.key, label: label, line: line, isEffects: true,
      assert: { boxing in
        let box = try ChainBox<State, Action, Payload>.cast(boxing)
        return assert(box.lastEffects)
      }))
}

@resultBuilder
public enum ChainScenarioBuilder {
  public static func buildBlock(_ parts: [ChainStep]...) -> [ChainStep] {
    parts.flatMap { $0 }
  }

  public static func buildExpression(_ step: ChainStep) -> [ChainStep] {
    [step]
  }
}

public struct ChainScenario {
  public let chain: String
  public let fixture: String
  public let description: String
  public let sourceFile: StaticString
  public let steps: [ChainStep]

  public init(
    chain: String, fixture: String? = nil, description: String,
    sourceFile: StaticString = #filePath,
    @ChainScenarioBuilder content: () -> [ChainStep]
  ) {
    self.chain = chain
    self.fixture = fixture ?? "chain-\(chain)"
    self.description = description
    self.sourceFile = sourceFile
    self.steps = content()
  }
}

/// See `ChainNode`'s Sendable note.
extension ChainScenario: @unchecked Sendable {}

// MARK: - Boxes (type-erased per-node stores)

protocol ChainBoxing: AnyObject {
  var key: String { get }
  func initialStateTree() throws -> Any
}

final class ChainBox<State, Action, Payload>: ChainBoxing
where State: Codable, Action: Codable, Payload: Equatable & Codable {
  let key: String
  var state: State
  var lastEffects: [Effect<Payload>] = []
  private let initial: State
  private let reducer: (inout State, Action) -> [Effect<Payload>]

  init(node: ChainNode<State, Action, Payload>) {
    self.key = node.key
    self.state = node.initial
    self.initial = node.initial
    self.reducer = node.reducer
  }

  func initialStateTree() throws -> Any {
    try ChainScenarioRunner.jsonTree(of: initial)
  }

  func reduce(_ action: Action) throws -> Any {
    let effects = reducer(&state, action)
    lastEffects = effects
    return try ChainScenarioRunner.jsonTree(of: effects)
  }

  static func cast(_ boxing: ChainBoxing) throws -> ChainBox<State, Action, Payload> {
    guard let box = boxing as? ChainBox<State, Action, Payload> else {
      throw ScenarioRunner.ScenarioError.malformed(
        "node '\(boxing.key)' is used with mismatched State/Action/Payload types "
          + "(two ChainNodes sharing a key must share types)")
    }
    return box
  }
}

// MARK: - Runner

/// Record/verify for chain scenarios — the chain-dialect sibling of `ScenarioRunner`.
public enum ChainScenarioRunner {
  static let platform = "swift"

  public static func verifyOrRecord(_ scenario: ChainScenario) throws {
    if FixtureRecorder.regenerationRequested {
      try record(scenario)
    }
    try verify(scenario)
  }

  // MARK: Record

  @discardableResult
  public static func record(_ scenario: ChainScenario) throws -> URL {
    let source = FixtureRunner.repoRelativePath(of: String(describing: scenario.sourceFile))
    let fixturesDir = try FixtureRunner.fixturesDirectory(
      startingFrom: String(describing: scenario.sourceFile))
    var boxes = Boxes()
    var steps: [[String: Any]] = []
    var lastEffectsTree: Any = [Any]()

    for step in scenario.steps {
      switch step.kind {
      case let .when(nodeKey, label, line, makeBox, actionTree, apply):
        let box = boxes.box(for: nodeKey, make: makeBox)
        let action = try actionTree()
        lastEffectsTree = try apply(box)
        steps.append(recordedStep(
          node: nodeKey, label: label, line: line, action: action,
          effects: lastEffectsTree))
      case let .hop(_, toKey, label, line, makeToBox, derive):
        guard !steps.isEmpty else {
          throw ScenarioRunner.ScenarioError.malformed(
            "Hop cannot be the first chain step (nothing emitted a delegate yet)")
        }
        guard let payload = lastNotifyListenerPayload(inEffectsTree: lastEffectsTree) else {
          throw ScenarioRunner.ScenarioError.malformed(
            "Hop '\(label)': the previous step emitted no notifyListener delegate")
        }
        steps[steps.count - 1]["linkToNext"] = true
        let box = boxes.box(for: toKey, make: makeToBox)
        let derived = try derive(payload)
        lastEffectsTree = try derived.apply(box)
        steps.append(recordedStep(
          node: toKey, label: label, line: line, action: derived.actionTree,
          effects: lastEffectsTree))
      case let .then(nodeKey, label, line, _, assert):
        guard let box = boxes.existing(nodeKey) else {
          throw ScenarioRunner.ScenarioError.malformed(
            "Then on node '\(nodeKey)' before any of its steps")
        }
        if try !assert(box) {
          // A false Then during record is an authoring error — nothing is written.
          XCTFail(
            "chain '\(scenario.fixture)': Then '\(label)' failed during record — fixture not written",
            file: scenario.sourceFile, line: line)
          throw ScenarioRunner.ScenarioError.malformed(
            "Then '\(label)' failed during record")
        }
      }
    }

    var initialStates: [String: Any] = [:]
    for box in boxes.created {
      initialStates[box.key] = try box.initialStateTree()
    }
    let document: [String: Any] = [
      "dialect": 2,
      "chain": scenario.chain,
      "description": scenario.description,
      "scenario": ["source": source ?? String(describing: scenario.sourceFile)],
      "initialStates": initialStates,
      "steps": steps,
    ]
    let url = fixturesDir
      .appendingPathComponent("\(scenario.fixture).fixture.json")
    try Data(CanonicalJSON.prettyCanonicalString(fromJSONObject: document).utf8)
      .write(to: url)
    print("ChainScenarioRunner: recorded \(scenario.fixture).fixture.json (\(steps.count) steps)")
    return url
  }

  private static func recordedStep(
    node: String, label: String, line: UInt, action: Any, effects: Any
  ) -> [String: Any] {
    [
      "node": node,
      "label": label,
      "line": Int(line),
      "action": action,
      "expectedEffects": effects,
    ]
  }

  // MARK: Verify

  public static func verify(_ scenario: ChainScenario) throws {
    let source = FixtureRunner.repoRelativePath(of: String(describing: scenario.sourceFile))
    let fixture = scenario.fixture
    let fixturesDir = try FixtureRunner.fixturesDirectory(
      startingFrom: String(describing: scenario.sourceFile))

    var reported = false
    func report(_ rawFailure: ParityRunFailure, at line: UInt) {
      reported = true
      var failure = rawFailure
      failure.rendered = FixtureRunner.format(
        failure, fixture: fixture, scenarioSource: source, platform: platform)
      ParityRunReport.write(
        fixture: fixture, feature: nil, status: "failed",
        steps: nil, scenarioSource: source, failures: [failure],
        besideFixtures: fixturesDir)
      XCTFail(failure.rendered ?? failure.kind, file: scenario.sourceFile, line: line)
    }
    func structure(_ message: String, at line: UInt = 1) {
      report(ParityRunFailure(kind: "structure", message: message), at: line)
    }

    let url = fixturesDir
      .appendingPathComponent("\(fixture).fixture.json")
    guard let data = try? Data(contentsOf: url),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rawSteps = root["steps"] as? [[String: Any]]
    else {
      structure("chain fixture missing or unreadable — record it: verify record")
      return
    }
    let dialect = root["dialect"] as? Int ?? 1
    if dialect < 2 {
      structure("chain fixture is dialect \(dialect) (pre-scenario) — regenerate: verify record")
      return
    }
    let rawInitialStates = root["initialStates"] as? [String: Any] ?? [:]

    // Every node the scenario touches, created upfront so the Given-equivalents gate
    // before any step replays.
    var boxes = Boxes()
    for step in scenario.steps {
      switch step.kind {
      case let .when(nodeKey, _, _, makeBox, _, _):
        _ = boxes.box(for: nodeKey, make: makeBox)
      case let .hop(_, toKey, _, _, makeToBox, _):
        _ = boxes.box(for: toKey, make: makeToBox)
      case .then:
        break
      }
    }
    for box in boxes.created {
      guard let rawInitial = rawInitialStates[box.key] else {
        structure(
          "fixture has no initialStates['\(box.key)'] — regenerate: verify record")
        return
      }
      let expected = try CanonicalJSON.canonicalString(fromJSONObject: rawInitial)
      let actual = try CanonicalJSON.canonicalString(fromJSONObject: box.initialStateTree())
      if expected != actual {
        structure(
          "node '\(box.key)' seed drifted from recorded initialStates — regenerate: verify record")
        return
      }
    }
    for key in rawInitialStates.keys where boxes.existing(key) == nil {
      structure("fixture initialStates has unknown node '\(key)' — regenerate: verify record")
      return
    }

    let whenCount = scenario.steps.filter {
      if case .then = $0.kind { return false } else { return true }
    }.count
    if whenCount != rawSteps.count {
      structure(
        "chain scenario has \(whenCount) step(s) but fixture has \(rawSteps.count) "
          + "— regenerate: verify record")
      return
    }

    // The walk. Thens run before their step's byte gate (same deferred-gate contract
    // as ScenarioRunner); a Hop byte-gates the PREVIOUS step first, so a divergent
    // delegate fails as `effects` there, not as a confusing decode error here.
    struct Pending {
      let index: Int
      let nodeKey: String
      let label: String
      let line: UInt
      let effectsTree: Any
      let actionCanonical: String
    }
    var pending: Pending?
    var lastEffectsTree: Any = [Any]()
    var stepIndex = 0

    func flushPendingGate() throws {
      guard let step = pending else { return }
      pending = nil
      let rawExpected = rawSteps[step.index]["expectedEffects"] ?? [Any]()
      let expected = try CanonicalJSON.canonicalString(fromJSONObject: rawExpected)
      let actual = try CanonicalJSON.canonicalString(fromJSONObject: step.effectsTree)
      if expected != actual {
        let divergence = try FixtureDiff.firstDivergence(
          expected: rawExpected, actual: step.effectsTree)
        report(
          ParityRunFailure(
            step: step.index, label: step.label, line: Int(step.line), kind: "effects",
            node: step.nodeKey, path: divergence?.path, expected: divergence?.expected,
            actual: divergence?.actual, action: step.actionCanonical),
          at: step.line)
        throw StopWalk()
      }
    }

    func advance(
      nodeKey: String, label: String, line: UInt, actionTree: Any,
      apply: (ChainBoxing) throws -> Any, viaHop: Bool
    ) throws {
      let rawStep = rawSteps[stepIndex]
      let fixtureNode = rawStep["node"] as? String
      if fixtureNode != nodeKey {
        report(
          ParityRunFailure(
            step: stepIndex, label: label, line: Int(line), kind: "structure",
            node: nodeKey,
            message: "scenario step is on node '\(nodeKey)' but the fixture recorded "
              + "'\(fixtureNode ?? "?")' — regenerate: verify record"),
          at: line)
        throw StopWalk()
      }
      let scenarioAction = try CanonicalJSON.canonicalString(fromJSONObject: actionTree)
      let fixtureAction = try CanonicalJSON.canonicalString(
        fromJSONObject: rawStep["action"] ?? NSNull())
      if scenarioAction != fixtureAction {
        report(
          ParityRunFailure(
            step: stepIndex, label: label, line: Int(line), kind: "structure",
            node: nodeKey, action: scenarioAction,
            message: "scenario \(viaHop ? "hop-derived" : "") action drifted from fixture "
              + "(recorded: \(fixtureAction)) — regenerate: verify record"),
          at: line)
        throw StopWalk()
      }
      if viaHop, stepIndex > 0, (rawSteps[stepIndex - 1]["linkToNext"] as? Bool) != true {
        report(
          ParityRunFailure(
            step: stepIndex, label: label, line: Int(line), kind: "structure",
            node: nodeKey,
            message: "hop step, but fixture step \(stepIndex - 1) is not marked "
              + "linkToNext — regenerate: verify record"),
          at: line)
        throw StopWalk()
      }
      guard let box = boxes.existing(nodeKey) else { return }
      lastEffectsTree = try apply(box)
      pending = Pending(
        index: stepIndex, nodeKey: nodeKey, label: label, line: line,
        effectsTree: lastEffectsTree, actionCanonical: scenarioAction)
      stepIndex += 1
    }

    do {
      for step in scenario.steps {
        switch step.kind {
        case let .when(nodeKey, label, line, _, actionTree, apply):
          try flushPendingGate()
          try advance(
            nodeKey: nodeKey, label: label, line: line, actionTree: try actionTree(),
            apply: apply, viaHop: false)
        case let .hop(_, toKey, label, line, _, derive):
          try flushPendingGate()
          guard let payload = lastNotifyListenerPayload(inEffectsTree: lastEffectsTree)
          else {
            report(
              ParityRunFailure(
                step: stepIndex, label: label, line: Int(line), kind: "structure",
                node: toKey,
                message: "Hop, but the previous step emitted no notifyListener delegate"),
              at: line)
            throw StopWalk()
          }
          let derived = try derive(payload)
          try advance(
            nodeKey: toKey, label: label, line: line, actionTree: derived.actionTree,
            apply: derived.apply, viaHop: true)
        case let .then(nodeKey, label, line, isEffects, assert):
          guard let box = boxes.existing(nodeKey) else { continue }
          if try !assert(box) {
            var failure = ParityRunFailure(
              step: pending?.index, label: label, line: Int(line), kind: "assertion",
              node: nodeKey,
              message: isEffects
                ? "ThenEffects returned false against the node's last emitted effects"
                : "Then returned false against the node's current state")
            // Attach the pending step's effects divergence, if any (Thens run first).
            if let step = pending,
              let rawExpected = rawSteps[step.index]["expectedEffects"],
              let divergence = try? FixtureDiff.firstDivergence(
                expected: rawExpected, actual: step.effectsTree)
            {
              let path = divergence.path
              let joiner = path.hasPrefix("[") ? "" : "."
              failure.path = "expectedEffects\(joiner)\(path)"
              failure.expected = divergence.expected
              failure.actual = divergence.actual
              failure.message =
                (failure.message ?? "")
                + " — the step's effects also diverged from the fixture"
            }
            report(failure, at: line)
            throw StopWalk()
          }
        }
      }
      try flushPendingGate()
    } catch is StopWalk {
      // Reported by the callback; end quietly.
    }

    if !reported {
      ParityRunReport.write(
        fixture: fixture, feature: nil, status: "passed",
        steps: rawSteps.count, scenarioSource: source, failures: [],
        besideFixtures: fixturesDir)
    }
  }

  // MARK: Plumbing

  private struct StopWalk: Error {}

  private struct Boxes {
    private(set) var created: [ChainBoxing] = []
    private var byKey: [String: ChainBoxing] = [:]

    mutating func box(for key: String, make: () -> ChainBoxing) -> ChainBoxing {
      if let existing = byKey[key] { return existing }
      let box = make()
      byKey[key] = box
      created.append(box)
      return box
    }

    func existing(_ key: String) -> ChainBoxing? {
      byKey[key]
    }
  }

  /// The delegate payload of the LAST `notifyListener` effect in a canonical effects
  /// tree (nil when there is none) — the value a `Hop` forwards.
  static func lastNotifyListenerPayload(inEffectsTree tree: Any) -> Any? {
    guard let effects = tree as? [[String: Any]] else { return nil }
    for effect in effects.reversed() {
      if let payload = effect["payload"] as? [String: Any],
        payload["case"] as? String == "notifyListener",
        let value = payload["value"]
      {
        return value
      }
    }
    return nil
  }

  static func jsonTree<T: Encodable>(of value: T) throws -> Any {
    let canonical = try CanonicalJSON.canonicalString(of: value)
    return try JSONSerialization.jsonObject(
      with: Data(canonical.utf8), options: [.fragmentsAllowed])
  }
}
