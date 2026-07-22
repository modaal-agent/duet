// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import Duet
import XCTest

/// Exhaustive test store — contract §5 (failure rules E1–E5). Runs the real reducer and
/// really executes effects (against the test Environment the handler closed over), but
/// records everything so nothing can happen unasserted.
@MainActor
public final class TestStore<State: Equatable, Action: Equatable, Payload: Equatable> {
  public private(set) var state: State

  private let reducer: (inout State, Action) -> [Effect<Payload>]
  private let handler: (Payload) -> AsyncStream<Action>
  private var receivedBuffer: [Action] = []
  private var unassertedEffects: [Effect<Payload>] = []
  private var identifiedTasks: [EffectID: Task<Void, Never>] = [:]
  private var anonymousTasks: [Task<Void, Never>] = []
  private var activeEffectCount = 0

  public init(
    initialState: State,
    reducer: @escaping (inout State, Action) -> [Effect<Payload>],
    handler: @escaping (Payload) -> AsyncStream<Action>
  ) {
    self.state = initialState
    self.reducer = reducer
    self.handler = handler
  }

  /// E1: `assert` must transform a copy of the pre-action state into *exactly* the
  /// post-reduce state (whole-value equality).
  public func send(
    _ action: Action,
    assert: ((inout State) -> Void)? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    var expected = state
    let effects = reducer(&state, action)
    assert?(&expected)
    if expected != state {
      XCTFail(
        "send(\(action)) state mismatch (E1)\nexpected: \(expected)\nactual:   \(state)",
        file: file, line: line)
    }
    unassertedEffects.append(contentsOf: effects)
    for effect in effects {
      execute(effect)
    }
  }

  /// E3/E4: awaits the next handler-emitted action and asserts it (action + state change).
  public func receive(
    _ expectedAction: Action,
    assert: ((inout State) -> Void)? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    var attempts = 0
    while receivedBuffer.isEmpty && attempts < 200 {
      await Task.megaYield(count: 5)
      attempts += 1
    }
    guard !receivedBuffer.isEmpty else {
      XCTFail("receive(\(expectedAction)): no action arrived (E4)", file: file, line: line)
      return
    }
    let actual = receivedBuffer.removeFirst()
    if actual != expectedAction {
      XCTFail(
        "receive expected \(expectedAction), got \(actual)", file: file, line: line)
    }
    var expected = state
    let effects = reducer(&state, actual)
    assert?(&expected)
    if expected != state {
      XCTFail(
        "receive(\(actual)) state mismatch (E1)\nexpected: \(expected)\nactual:   \(state)",
        file: file, line: line)
    }
    unassertedEffects.append(contentsOf: effects)
    for effect in effects {
      execute(effect)
    }
  }

  /// E2: pops and asserts every effect emitted since the last call.
  public func expectEffects(
    _ expected: [Effect<Payload>],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    if unassertedEffects != expected {
      XCTFail(
        "effects mismatch (E2)\nexpected: \(expected)\nactual:   \(unassertedEffects)",
        file: file, line: line)
    }
    unassertedEffects.removeAll()
  }

  /// E2/E3/E5 closing check. Call at the end of every test.
  public func finish(file: StaticString = #filePath, line: UInt = #line) async {
    var attempts = 0
    while activeEffectCount > 0 && attempts < 200 {
      await Task.megaYield(count: 5)
      attempts += 1
    }
    if !unassertedEffects.isEmpty {
      XCTFail("unasserted effects at finish (E2): \(unassertedEffects)", file: file, line: line)
    }
    if !receivedBuffer.isEmpty {
      XCTFail("unreceived actions at finish (E3): \(receivedBuffer)", file: file, line: line)
    }
    if activeEffectCount > 0 {
      XCTFail(
        "\(activeEffectCount) effect(s) still in flight at finish (E5) — cancel long-lived "
          + "effects explicitly (mirror of host teardown)",
        file: file, line: line)
    }
  }

  /// Cancels everything — the teardown mirror, for tests that end mid-flight on purpose.
  public func teardown() {
    for task in identifiedTasks.values {
      task.cancel()
    }
    for task in anonymousTasks {
      task.cancel()
    }
    identifiedTasks.removeAll()
    anonymousTasks.removeAll()
  }

  private func execute(_ effect: Effect<Payload>) {
    switch effect {
    case let .cancel(id):
      identifiedTasks.removeValue(forKey: id)?.cancel()
    case let .run(payload, id):
      if let id {
        identifiedTasks.removeValue(forKey: id)?.cancel()
      }
      let stream = handler(payload)
      activeEffectCount += 1
      // The task inherits the test store's main-actor isolation — enqueue and
      // the effect-count bookkeeping run without a hop.
      let task = Task { [weak self] in
        for await action in stream {
          if Task.isCancelled { break }
          self?.enqueue(action)
        }
        self?.effectEnded()
      }
      if let id {
        identifiedTasks[id] = task
      } else {
        anonymousTasks.append(task)
      }
    }
  }

  private func enqueue(_ action: Action) {
    receivedBuffer.append(action)
  }

  private func effectEnded() {
    activeEffectCount -= 1
  }
}
