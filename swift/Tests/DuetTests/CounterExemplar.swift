// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Duet
import Foundation

// The kernel receipts' exemplar feature (the counter, in its harness-proving role):
// state changes, a guarded system action, and a virtual-time ticker effect with
// cancel-in-flight identity. Test-target-local on purpose — the framework ships no
// features, and each suite's exemplar is tailored to what it receipts (this copy
// skips canonical Codable; the DuetTestingTests copy carries it for fixtures).

struct CounterState: Equatable, Sendable {
  var count: Int = 0
  var isAutoIncrementing: Bool = false
}

enum CounterAction: Equatable, Sendable {
  case increment
  case decrement
  case toggleAutoIncrement
  /// System action, fed back by the ticker effect.
  case tick
}

enum CounterEffectPayload: Equatable, Sendable {
  case startTicker
}

enum CounterEffectIDs {
  static let ticker: EffectID = "counter.ticker"
}

func counterReducer(
  state: inout CounterState, action: CounterAction
) -> [Effect<CounterEffectPayload>] {
  switch action {
  case .increment:
    state.count += 1
    return []
  case .decrement:
    state.count -= 1
    return []
  case .toggleAutoIncrement:
    state.isAutoIncrementing.toggle()
    return state.isAutoIncrementing
      ? [.run(.startTicker, id: CounterEffectIDs.ticker)]
      : [.cancel(id: CounterEffectIDs.ticker)]
  case .tick:
    // Guarded: a stray tick after cancellation must not count.
    if state.isAutoIncrementing {
      state.count += 1
    }
    return []
  }
}

func counterEffectHandler(
  clock: any KernelClock
) -> (CounterEffectPayload) -> AsyncStream<CounterAction> {
  { payload in
    switch payload {
    case .startTicker:
      return AsyncStream { continuation in
        let task = Task {
          while !Task.isCancelled {
            do {
              try await clock.sleep(nanoseconds: 1_000_000_000)
            } catch {
              break
            }
            continuation.yield(.tick)
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }
  }
}
