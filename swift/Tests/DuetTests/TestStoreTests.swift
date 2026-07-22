// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Duet
import DuetTesting
import XCTest

/// T1 (exhaustive reducer via TestStore) + T2 (effect execution on virtual time):
/// the ticker effect starts, ticks on clock advance, cancels in-flight, and never
/// fires after cancellation. Contract §5 rules E1–E5 exercised end-to-end.
@MainActor
final class TestStoreTests: XCTestCase {
  private func makeStore(clock: TestClock) -> TestStore<
    CounterState, CounterAction, CounterEffectPayload
  > {
    TestStore(
      initialState: CounterState(),
      reducer: counterReducer,
      handler: counterEffectHandler(clock: clock))
  }

  func testManualCounting() async {
    let store = makeStore(clock: TestClock())
    store.send(.increment) { $0.count = 1 }
    store.send(.increment) { $0.count = 2 }
    store.send(.decrement) { $0.count = 1 }
    // Stray tick while auto-increment is off must be a no-op.
    store.send(.tick)
    await store.finish()
  }

  func testAutoIncrementLifecycleOnVirtualTime() async {
    let clock = TestClock()
    let store = makeStore(clock: clock)

    store.send(.toggleAutoIncrement) { $0.isAutoIncrementing = true }
    store.expectEffects([.run(.startTicker, id: CounterEffectIDs.ticker)])

    await clock.advance(byNanoseconds: 1_000_000_000)
    await store.receive(.tick) { $0.count = 1 }

    await clock.advance(byNanoseconds: 1_000_000_000)
    await store.receive(.tick) { $0.count = 2 }

    store.send(.toggleAutoIncrement) { $0.isAutoIncrementing = false }
    store.expectEffects([.cancel(id: CounterEffectIDs.ticker)])

    // After cancellation, time may pass but no tick is delivered (E3 would fail finish()).
    await clock.advance(byNanoseconds: 5_000_000_000)
    await store.finish()
  }

  func testCancelInFlightRestartsTicker() async {
    let clock = TestClock()
    let store = makeStore(clock: clock)

    store.send(.toggleAutoIncrement) { $0.isAutoIncrementing = true }
    store.expectEffects([.run(.startTicker, id: CounterEffectIDs.ticker)])

    // Toggling off+on emits cancel then a fresh run with the same id (cancel-in-flight
    // is ALSO exercised implicitly: the second run would cancel a lingering first).
    store.send(.toggleAutoIncrement) { $0.isAutoIncrementing = false }
    store.expectEffects([.cancel(id: CounterEffectIDs.ticker)])
    store.send(.toggleAutoIncrement) { $0.isAutoIncrementing = true }
    store.expectEffects([.run(.startTicker, id: CounterEffectIDs.ticker)])

    await clock.advance(byNanoseconds: 1_000_000_000)
    await store.receive(.tick) { $0.count = 1 }

    store.send(.toggleAutoIncrement) { $0.isAutoIncrementing = false }
    store.expectEffects([.cancel(id: CounterEffectIDs.ticker)])
    await store.finish()
  }
}
