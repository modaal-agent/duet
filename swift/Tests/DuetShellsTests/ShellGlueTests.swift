// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Combine
import Duet
import DuetShells
import Foundation
import XCTest

/// Shell glue receipts. ProjectionJoin's tests pin the join rule (re-apply on EITHER input —
/// the two-source race is the whole point of the type); StoreHost's pin the
/// reverse-order, idempotent teardown that replaces hand-enumerated `teardown()`
/// bodies; `kernelStream()`'s pin that effect cancellation reaches the upstream
/// Combine subscription (cancellation across the bridge).
@MainActor
final class ShellGlueTests: XCTestCase {

  // MARK: - ProjectionJoin

  func testProjectionJoinAppliesStateAgainstInitialAuxThenSelfHealsWhenAuxLands() async {
    let state = CurrentValueSubject<Int, Never>(0)
    let aux = PassthroughSubject<String, Never>()
    var applied: [String] = []

    let join = ProjectionJoin(state: state, joining: aux, initialAux: "empty") {
      applied.append("\($0)|\($1)")
    }

    // State replays synchronously against the initial aux (project thin)…
    XCTAssertEqual(applied, ["0|empty"])
    state.send(1)
    XCTAssertEqual(applied, ["0|empty", "1|empty"])

    // …and the projection self-heals when the aux source lands.
    aux.send("index")
    await settle()
    XCTAssertEqual(applied, ["0|empty", "1|empty", "1|index"])
    XCTAssertEqual(join.aux, "index")
  }

  func testProjectionJoinDedupsStateAndStopsAfterCancel() async {
    let state = CurrentValueSubject<Int, Never>(7)
    let aux = PassthroughSubject<String, Never>()
    var applied: [String] = []

    let join = ProjectionJoin(state: state, joining: aux, initialAux: "-") {
      applied.append("\($0)|\($1)")
    }

    state.send(7)
    XCTAssertEqual(applied, ["7|-"], "duplicate state must not re-apply")

    join.cancel()
    state.send(8)
    aux.send("late")
    await settle()
    XCTAssertEqual(applied, ["7|-"], "a cancelled join must go quiet")
  }

  func testStateTransitionsDeliversOldNewPairsWithSeededFirstFire() {
    let state = CurrentValueSubject<Int, Never>(0)
    var pairs: [String] = []

    let transitions = StateTransitions(state: state) { old, new in
      pairs.append("\(old)->\(new)")
    }

    XCTAssertEqual(pairs, ["0->0"], "first fire seeds old == new (nothing to compare)")
    state.send(1)
    state.send(1)
    state.send(2)
    XCTAssertEqual(pairs, ["0->0", "0->1", "1->2"])

    transitions.cancel()
    state.send(3)
    XCTAssertEqual(pairs, ["0->0", "0->1", "1->2"])
  }

  // MARK: - StoreHost

  func testStoreHostTearsDownInReverseRegistrationOrderExactlyOnce() {
    let host = StoreHost()
    var order: [String] = []

    host.adopt(teardown: { order.append("store") })
    host.adopt(teardown: { order.append("slot") })
    host.adopt(teardown: { order.append("observation") })

    host.teardownAll()
    XCTAssertEqual(order, ["observation", "slot", "store"])

    host.teardownAll()
    XCTAssertEqual(order, ["observation", "slot", "store"], "teardownAll is idempotent")
  }

  func testStoreHostTearsDownAdoptedReconcilersAndCancelsHostedStoreEffects() async {
    let host = StoreHost()

    // A hosted store with one long-lived effect: teardownAll must cancel it (the
    // stream's onTermination is the receipt).
    let effectTerminated = TerminationFlag()
    let store = host.host(
      Store<Int, Int, String>(
        initialState: 0,
        reducer: { state, action in
          state = action
          return [.run("observe", id: "glue.observe")]
        },
        handler: { _ in
          AsyncStream { continuation in
            continuation.onTermination = { _ in effectTerminated.set() }
          }
        }))
    store.send(1)

    // An adopted slot with a live child: teardownAll must drain it.
    var tornChildren: [String] = []
    let slot = host.adopt(
      ChildSlot<Int, String>(
        build: { "child-\($0)" },
        teardown: { tornChildren.append($0) }))
    slot.reconcile(key: 1)
    XCTAssertEqual(slot.activeHandle, "child-1")

    host.teardownAll()
    await settle()
    XCTAssertEqual(tornChildren, ["child-1"])
    XCTAssertTrue(
      effectTerminated.isSet, "hosted store's in-flight effect must be cancelled")
  }

  // MARK: - kernelStream (the audited Combine→AsyncStream bridge)

  func testKernelStreamYieldsValuesAndCancelsUpstreamWhenConsumerIsCancelled() async {
    let subject = PassthroughSubject<Int, Never>()
    let upstreamCancelled = TerminationFlag()

    let stream = subject
      .handleEvents(receiveCancel: { upstreamCancelled.set() })
      .kernelStream()

    // Subscription starts at creation; values buffer until iterated.
    subject.send(1)
    subject.send(2)

    // Consume the way `Store.execute` does: a task iterating the stream, cancelled
    // at teardown. Task cancellation is what terminates the stream and unwinds the
    // upstream subscription — cancellation across the bridge.
    let consumer = Task { @MainActor in
      var received: [Int] = []
      for await value in stream {
        received.append(value)
      }
      return received
    }
    await settle()
    consumer.cancel()
    let received = await consumer.value

    XCTAssertEqual(received, [1, 2])
    XCTAssertTrue(
      upstreamCancelled.isSet,
      "cancelling the consuming effect must cancel the upstream subscription")
  }

  func testFinishedStreamCompletesImmediately() async {
    var received: [Int] = []
    for await value in AsyncStream<Int>.finished {
      received.append(value)
    }
    XCTAssertEqual(received, [])
  }
}

/// A latch settable from `@Sendable` termination/cancel callbacks (a captured `var`
/// can't cross into them under strict concurrency).
private final class TerminationFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  var isSet: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set() {
    lock.lock()
    defer { lock.unlock() }
    value = true
  }
}

/// Test-side pump: effect handlers hop through tasks; a few yields let every queued
/// hop settle deterministically.
@MainActor
func settle(_ turns: Int = 20) async {
  for _ in 0..<turns {
    await Task.yield()
  }
}
