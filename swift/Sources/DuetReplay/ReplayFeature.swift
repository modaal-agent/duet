// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Duet
import Foundation

/// The Swift flavor's replay adapter — the ONLY per-flavor piece the replay
/// protocol leaves in the flavor library. One typed entry per feature
/// (scaffold-emitted glue, one line each, next to the app's composition root);
/// each step call is stateless: decode state + action trees, run the pure
/// reducer, return canonical strings. The CLI owns everything else (driving,
/// diffing, writing, reporting).
///
/// An app declares its registry beside its features and hands it to
/// `ReplayServer.serve(registry:)` from a small executable target:
///
///     let registry = ReplayRegistry([
///       ReplayFeature.entry("counter", CounterState.self, CounterAction.self, counterReducer),
///       …
///     ])
public struct ReplayFeature: Sendable {
  public let name: String
  public let step:
    @Sendable (_ stateTree: Any, _ actionTree: Any) throws -> (state: String, effects: String)

  public init(
    name: String,
    step: @escaping @Sendable (_ stateTree: Any, _ actionTree: Any) throws -> (
      state: String, effects: String
    )
  ) {
    self.name = name
    self.step = step
  }

  /// The typed entry: pins a feature name to its (State, Action, Payload) triple and
  /// pure reducer. Decoding uses the canonical decoder; results are returned as the
  /// canonical compact strings the byte gate compares.
  public static func entry<State, Action, Payload>(
    _ name: String,
    _: State.Type,
    _: Action.Type,
    _ reducer: @escaping @Sendable (inout State, Action) -> [Effect<Payload>]
  ) -> ReplayFeature
  where State: Codable, Action: Codable, Payload: Codable & Equatable {
    ReplayFeature(name: name) { stateTree, actionTree in
      let decoder = ReplayCanonical.canonicalDecoder()
      var state = try decoder.decode(
        State.self,
        from: JSONSerialization.data(withJSONObject: stateTree, options: [.fragmentsAllowed]))
      let action = try decoder.decode(
        Action.self,
        from: JSONSerialization.data(withJSONObject: actionTree, options: [.fragmentsAllowed]))
      let effects = reducer(&state, action)
      return (
        state: try ReplayCanonical.canonicalString(of: state),
        effects: try ReplayCanonical.canonicalString(of: effects))
    }
  }
}

/// The app's feature table, keyed by feature name. Duplicate names are a
/// programmer error (two features cannot share a fixture namespace).
public struct ReplayRegistry: Sendable {
  public let features: [String: ReplayFeature]

  public init(_ entries: [ReplayFeature]) {
    self.features = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
  }
}
