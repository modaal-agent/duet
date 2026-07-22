// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import Duet

// MT4 fork glue, shell duty 1: hosting stores means guaranteeing their teardown.
// Before this helper every composition root hand-enumerated its stores, reconcilers,
// and observations in teardown() — the forgotten-entry bug class the churn specs
// exist to catch. StoreHost turns that enumeration into registration at creation
// time: whatever the shell creates, it registers in the same breath.

/// The composition root's teardown registry. `teardownAll()` unwinds in reverse
/// registration order, so registering things in creation order gives the right
/// shutdown for free: observations stop first, child reconcilers detach next, the
/// node's own stores cancel their effects last. Idempotent — a second
/// `teardownAll()` is a no-op.
@MainActor
public final class StoreHost {
  private var teardowns: [@MainActor () -> Void] = []

  public init() {}

  /// Hosts a store the shell owns: registers `store.teardown()` (kernel contract §3
  /// rule 5) and hands the store back for assignment.
  @discardableResult
  public func host<State, Action, Payload>(
    _ store: Store<State, Action, Payload>
  ) -> Store<State, Action, Payload> {
    teardowns.append { store.teardown() }
    return store
  }

  /// Registers a stack reconciler (shell duty 2) for teardown.
  @discardableResult
  public func adopt<Key, Handle>(
    _ children: ChildStores<Key, Handle>
  ) -> ChildStores<Key, Handle> {
    teardowns.append { children.teardownAll() }
    return children
  }

  /// Registers a modal-slot reconciler (shell duty 2) for teardown.
  @discardableResult
  public func adopt<Key, Handle>(_ slot: ChildSlot<Key, Handle>) -> ChildSlot<Key, Handle> {
    teardowns.append { slot.teardownAll() }
    return slot
  }

  /// Registers (and retains) an observation — a `ProjectionJoin` or
  /// `StateTransitions` the shell needs alive until teardown.
  @discardableResult
  public func adopt<O: HostedObservation>(_ observation: O) -> O {
    teardowns.append { observation.cancel() }
    return observation
  }

  /// Escape hatch for anything else that must stop at teardown.
  public func adopt(teardown: @escaping @MainActor () -> Void) {
    teardowns.append(teardown)
  }

  public func teardownAll() {
    let all = teardowns
    teardowns.removeAll()
    for teardown in all.reversed() {
      teardown()
    }
  }
}

/// Something a `StoreHost` can retain and cancel at teardown.
@MainActor
public protocol HostedObservation: AnyObject {
  func cancel()
}
