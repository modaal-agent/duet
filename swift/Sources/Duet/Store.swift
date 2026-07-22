// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Combine
import Foundation

/// The runtime: owns `State`, runs the pure reducer on `send`, executes the returned
/// `Effect` values via the feature's handler, and feeds handler-emitted actions back in.
/// Contract: contracts/store-kernel-contract.md §3.
@MainActor
public final class Store<State: Equatable, Action, Payload: Equatable>: ObservableObject {
  @Published public private(set) var state: State

  private let reducer: (inout State, Action) -> [Effect<Payload>]
  private let handler: (Payload) -> AsyncStream<Action>
  private let tasks = EffectTaskBox()
  private var isReducing = false
  private var actionQueue: [Action] = []

  public init(
    initialState: State,
    reducer: @escaping (inout State, Action) -> [Effect<Payload>],
    handler: @escaping (Payload) -> AsyncStream<Action>
  ) {
    self.state = initialState
    self.reducer = reducer
    self.handler = handler
  }

  deinit {
    // Best-effort backstop; hosts must still call teardown() (contract §3 rule 5).
    tasks.cancelAll()
  }

  /// Reduces synchronously (new state is observable before `send` returns), then starts
  /// the emitted effects in declaration order. Actions sent while a reduce is running
  /// (reentrancy via a synchronously-emitting handler) are queued, never reduced recursively.
  public func send(_ action: Action) {
    actionQueue.append(action)
    guard !isReducing else { return }
    isReducing = true
    defer { isReducing = false }
    while !actionQueue.isEmpty {
      let next = actionQueue.removeFirst()
      let effects = reducer(&state, next)
      for effect in effects {
        execute(effect)
      }
    }
  }

  /// Cancels every in-flight effect — the `cancelOnDeactivate(interactor:)` successor.
  /// Hosts MUST call this when the owning screen/scope dies.
  public func teardown() {
    tasks.cancelAll()
  }

  private func execute(_ effect: Effect<Payload>) {
    switch effect {
    case let .cancel(id):
      tasks.cancel(id: id)
    case let .run(payload, id):
      if let id {
        tasks.cancel(id: id)
      }
      let stream = handler(payload)
      // The task inherits the store's main-actor isolation, so `send` needs no
      // hop — actions from the stream re-enter the reduce loop synchronously.
      let task = Task { [weak self] in
        for await action in stream {
          if Task.isCancelled { break }
          self?.send(action)
        }
      }
      tasks.store(task, id: id)
    }
  }
}

/// Nonisolated task registry so `deinit` can cancel without touching main-actor state.
private final class EffectTaskBox: @unchecked Sendable {
  private let lock = NSLock()
  private var identified: [EffectID: Task<Void, Never>] = [:]
  private var anonymous: [Task<Void, Never>] = []

  func store(_ task: Task<Void, Never>, id: EffectID?) {
    lock.lock()
    defer { lock.unlock() }
    if let id {
      identified[id] = task
    } else {
      anonymous.append(task)
    }
  }

  func cancel(id: EffectID) {
    lock.lock()
    let task = identified.removeValue(forKey: id)
    lock.unlock()
    task?.cancel()
  }

  func cancelAll() {
    lock.lock()
    let all = Array(identified.values) + anonymous
    identified.removeAll()
    anonymous.removeAll()
    lock.unlock()
    for task in all {
      task.cancel()
    }
  }
}
