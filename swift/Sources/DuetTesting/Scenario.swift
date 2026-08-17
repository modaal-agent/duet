// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import Duet

/// The scenario DSL. A scenario is the *authored source* of a parity fixture:
/// spec-style, nested, with local `Then` assertions that carry code pointers. The
/// fixture JSON is compiled FROM it (`ScenarioRunner` record mode) and replayed on both
/// platforms; `Then`/`ThenEffects` closures run on the authoring platform only and are
/// never exported (scenarios contain no logic the fixture can't carry).
///
/// Deliberately NOT supported: `if`/`switch`/loops inside a scenario body. The builder
/// omits `buildOptional`/`buildEither`, so conditional scenarios are a *compile error* —
/// that is the rule enforced by the type system, not by review. Its target is
/// *data-dependent* control flow (what gets recorded must never depend on a runtime
/// value); `Branch` is static structure — every branch always runs, each as its own
/// recorded fixture — so alternates are expressible without weakening the rule.
public enum ScenarioNode<State, Action, Payload: Equatable> {
  case given(State, line: UInt)
  case when(label: String, action: Action, line: UInt)
  case then(label: String, line: UInt, assert: (State) -> Bool)
  case thenEffects(label: String, line: UInt, assert: ([Effect<Payload>]) -> Bool)
  case context(label: String, line: UInt, nodes: [ScenarioNode<State, Action, Payload>])
  case branch(label: String, line: UInt, nodes: [ScenarioNode<State, Action, Payload>])
}

@resultBuilder
public enum ScenarioBuilder<State, Action, Payload: Equatable> {
  public static func buildBlock(
    _ parts: [ScenarioNode<State, Action, Payload>]...
  ) -> [ScenarioNode<State, Action, Payload>] {
    parts.flatMap { $0 }
  }

  public static func buildExpression(
    _ node: ScenarioNode<State, Action, Payload>
  ) -> [ScenarioNode<State, Action, Payload>] {
    [node]
  }
}

/// The authored artifact. Generic parameters are usually written explicitly at the
/// declaration site (they pin the builder's element type for inference):
///
///     let sharePickerScenario = Scenario<SharePickerState, SharePickerAction, SharePickerEffectPayload>(
///       feature: "sharepicker",
///       description: "…") {
///       Given(SharePickerState(config: …))
///       When("activation subscribes to the friend graph", .onActive)
///       ThenEffects("exactly the identified observe effect") {
///         $0 == [.run(.observeFriends, id: "sharepicker.friends")]
///       }
///       Context("filtering") {
///         When("query narrows to 'a'", .queryChanged("a"))
///         Then("anna and cara remain") { $0.filteredFriendIds.count == 2 }
///       }
///     }
public struct Scenario<State, Action, Payload: Equatable> {
  public let feature: String
  public let fixture: String
  public let description: String
  /// Absolute path of the authoring file (captured via `#filePath`) — kept as
  /// `StaticString` so failures can point XCTest at the scenario source itself.
  public let sourceFile: StaticString
  public let nodes: [ScenarioNode<State, Action, Payload>]

  public init(
    feature: String,
    fixture: String? = nil,
    description: String,
    sourceFile: StaticString = #filePath,
    @ScenarioBuilder<State, Action, Payload> content: () -> [ScenarioNode<State, Action, Payload>]
  ) {
    self.feature = feature
    self.fixture = fixture ?? feature
    self.description = description
    self.sourceFile = sourceFile
    self.nodes = content()
  }
}

/// Scenarios are authored as immutable file-scope constants (the blessed pattern —
/// the artifact sits next to its test). `@unchecked` is grounded in the dialect's
/// own rules: fixture-visible State/Action/Payload are value types (serialization
/// contract), nodes are immutable after construction, and Then closures run only
/// inside the single-domain runner walk.
extension Scenario: @unchecked Sendable {}

// MARK: - DSL surface

/// The initial state. Exactly one `Given`, first in the scenario body.
public func Given<State, Action, Payload: Equatable>(
  _ state: State, line: UInt = #line
) -> ScenarioNode<State, Action, Payload> {
  .given(state, line: line)
}

/// One dispatched action — compiles to one fixture step. The label lands in the fixture
/// (`steps[i].label`) so a replay failure on EITHER platform names it.
public func When<State, Action, Payload: Equatable>(
  _ label: String, _ action: Action, line: UInt = #line
) -> ScenarioNode<State, Action, Payload> {
  .when(label: label, action: action, line: line)
}

/// Local state assertion against the state produced by the preceding `When`. Runs at
/// record and at authoring-platform verify; NOT exported to the fixture. A false return
/// fails at this line — the code pointer the fixture byte-gate can't give.
public func Then<State, Action, Payload: Equatable>(
  _ label: String, line: UInt = #line, _ assert: @escaping (State) -> Bool
) -> ScenarioNode<State, Action, Payload> {
  .then(label: label, line: line, assert: assert)
}

/// Local assertion on the effects emitted by the preceding `When`.
public func ThenEffects<State, Action, Payload: Equatable>(
  _ label: String, line: UInt = #line, _ assert: @escaping ([Effect<Payload>]) -> Bool
) -> ScenarioNode<State, Action, Payload> {
  .thenEffects(label: label, line: line, assert: assert)
}

/// Narrative grouping. Contexts are LINEAR: state flows through them (a context is a
/// chapter, not a Quick-style isolated branch — fixtures replay one action sequence).
/// Labels of enclosing contexts prefix each step label: "filtering › query narrows".
public func Context<State, Action, Payload: Equatable>(
  _ label: String, line: UInt = #line,
  @ScenarioBuilder<State, Action, Payload> _ content: () -> [ScenarioNode<State, Action, Payload>]
) -> ScenarioNode<State, Action, Payload> {
  .context(label: label, line: line, nodes: content())
}

/// A static alternate ending — the Quick-style fork the linear `Context` is not. Each
/// sibling `Branch` replays the shared prefix (pure reducers make that free), runs its
/// own steps in isolation from its siblings, and compiles to its OWN fixture:
/// `<fixture>.<slug>` (nested branches append: `<fixture>.<slug>.<slug>`). Branches
/// are terminal: once one appears at a level, only Branches may follow at that level.
///
/// Note: branches are *static* alternates — every branch always runs and records;
/// no runtime value chooses between them. `if` remains a compile error.
public func Branch<State, Action, Payload: Equatable>(
  _ label: String, line: UInt = #line,
  @ScenarioBuilder<State, Action, Payload> _ content: () -> [ScenarioNode<State, Action, Payload>]
) -> ScenarioNode<State, Action, Payload> {
  .branch(label: label, line: line, nodes: content())
}
