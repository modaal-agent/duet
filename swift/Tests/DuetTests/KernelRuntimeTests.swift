// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Duet
import DuetTesting
import XCTest

/// Runtime tests against the real `Store` (not TestStore): teardown cancels in-flight
/// effects — the host-teardown guarantee (contract §3 rule 5).
@MainActor
final class KernelRuntimeTests: XCTestCase {
  func testStoreRunsTickerAndTeardownCancels() async {
    let clock = TestClock()
    let store = Store(
      initialState: CounterState(),
      reducer: counterReducer,
      handler: counterEffectHandler(clock: clock))

    store.send(.toggleAutoIncrement)
    XCTAssertTrue(store.state.isAutoIncrementing)

    await clock.advance(byNanoseconds: 1_000_000_000)
    XCTAssertEqual(store.state.count, 1)

    await clock.advance(byNanoseconds: 1_000_000_000)
    XCTAssertEqual(store.state.count, 2)

    store.teardown()
    await clock.advance(byNanoseconds: 5_000_000_000)
    XCTAssertEqual(store.state.count, 2, "teardown() must cancel the in-flight ticker")
  }

  func testRunWithSameIDCancelsPreviousEffect() async {
    // Rule 6 lives in the Store RUNTIME, so fixture replay (which compares the
    // reducer's effect lists) cannot see it — only a real-Store test can.
    let clock = TestClock()
    let store = Store<Int, String, String>(
      initialState: 0,
      reducer: { (state: inout Int, action: String) -> [Effect<String>] in
        if action == "start" { return [.run("tick", id: "ticker")] }
        state += 1
        return []
      },
      handler: { _ in
        AsyncStream { continuation in
          let task = Task {
            while !Task.isCancelled {
              try? await clock.sleep(nanoseconds: 1_000_000_000)
              if Task.isCancelled { break }
              continuation.yield("tick")
            }
            continuation.finish()
          }
          continuation.onTermination = { _ in task.cancel() }
        }
      })

    store.send("start")
    await clock.advance(byNanoseconds: 1_000_000_000)
    XCTAssertEqual(store.state, 1)

    store.send("start")  // same-id restart
    await clock.advance(byNanoseconds: 1_000_000_000)
    XCTAssertEqual(
      store.state, 2, "same-id restart must cancel the previous ticker (§3 rule 6)")
    store.teardown()
  }

  func testReducerStateIsObservableSynchronously() {
    let store = Store(
      initialState: CounterState(),
      reducer: counterReducer,
      handler: counterEffectHandler(clock: TestClock()))

    store.send(.increment)
    XCTAssertEqual(store.state.count, 1, "send reduces synchronously (contract §3 rule 2)")
    store.teardown()
  }
}
