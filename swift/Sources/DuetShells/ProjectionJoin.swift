// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Combine
import Foundation

// MT4 fork glue, shell duty 4 — the R13 helper. R13 (doc 08 §3.1, from the MT2
// finding): a projection over feature state PLUS an auxiliary async source must
// re-apply whenever ANY input arrives — the sources race, and a projection that only
// re-runs on state updates silently drops rows when state lands first. This type owns
// the subscription mechanics so the join rule can't be forgotten per call site.

/// Joins a store's state publisher with one auxiliary source (an index, a cache, a
/// repository stream) and re-runs `apply` on every input.
///
/// Semantics, pinned:
/// - The state side is synchronous (no scheduler hop): reconcilers must observe a
///   reduce before `send` returns. The emitted value is used, never a re-read of
///   `store.state` — `@Published` emits on `willSet`, before the property is written.
/// - The aux side hops to the main queue (`receive(on:)`): repository streams emit
///   on background queues.
/// - `apply` runs with the latest of both. The first state emission applies against
///   `initialAux` — project thin, self-heal when the aux source lands (R13).
@MainActor
public final class ProjectionJoin<State: Equatable, Aux>: HostedObservation {
  /// The latest auxiliary value, for hosts that resolve through it outside `apply`.
  public private(set) var aux: Aux
  private var latestState: State?
  private var cancellables = Set<AnyCancellable>()
  private let applyJoin: @MainActor (State, Aux) -> Void

  public init<StateP: Publisher, AuxP: Publisher>(
    state statePublisher: StateP,
    joining auxPublisher: AuxP,
    initialAux: Aux,
    apply: @escaping @MainActor (State, Aux) -> Void
  ) where StateP.Output == State, StateP.Failure == Never,
    AuxP.Output == Aux, AuxP.Failure == Never
  {
    self.aux = initialAux
    self.applyJoin = apply

    statePublisher
      .removeDuplicates()
      .sink { [weak self] state in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.latestState = state
          self.applyJoin(state, self.aux)
        }
      }
      .store(in: &cancellables)

    auxPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] aux in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.aux = aux
          if let state = self.latestState {
            self.applyJoin(state, aux)
          }
        }
      }
      .store(in: &cancellables)
  }

  public func cancel() {
    cancellables.removeAll()
  }
}

/// Observes a store's state synchronously on the main actor, delivering `(old, new)`
/// transition pairs — the seam where shells hang analytics and presentation gates
/// without deciding anything themselves (R8). The first emission delivers
/// `(current, current)`; duplicates are filtered.
@MainActor
public final class StateTransitions<State: Equatable>: HostedObservation {
  private var previous: State?
  private var cancellable: AnyCancellable?

  public init<P: Publisher>(
    state statePublisher: P,
    onChange: @escaping @MainActor (_ old: State, _ new: State) -> Void
  ) where P.Output == State, P.Failure == Never {
    cancellable = statePublisher
      .removeDuplicates()
      .sink { [weak self] state in
        MainActor.assumeIsolated {
          guard let self else { return }
          let old = self.previous ?? state
          self.previous = state
          onChange(old, state)
        }
      }
  }

  public func cancel() {
    cancellable = nil
  }
}
