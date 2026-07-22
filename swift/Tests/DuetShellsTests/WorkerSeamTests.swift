// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Combine
import Duet
import DuetShells
import Foundation
import XCTest

/// Worker-seam receipts. `adopt` pins the bracket contract: registration
/// starts `run()` (in registration order), `teardownAll()` cancels LIFO with
/// everything else adopted, and the `liveWorkerCount` ledger settles to zero
/// once every `run()` returns — the leak class stop-by-convention could not
/// catch, now observable. `untilCancelled()` pins the subscription-shaped
/// worker's park: locals release on the way out, cancelling Combine machinery
/// without a `stop()` hook.
@MainActor
final class WorkerSeamTests: XCTestCase {

  func testAdoptStartsWorkersInRegistrationOrder() async {
    let host = StoreHost()
    let log = EventLog()

    host.adopt(ParkedWorker(name: "A", log: log))
    host.adopt(ParkedWorker(name: "B", log: log))

    await settle()
    XCTAssertEqual(log.events, ["A ran", "B ran"], "registration order is start order")
    XCTAssertEqual(host.liveWorkerCount, 2)

    host.teardownAll()
    await settle()
    XCTAssertEqual(host.liveWorkerCount, 0)
  }

  func testTeardownCancelsWorkersLIFOWithEverythingElseAdopted() async {
    let host = StoreHost()
    let log = EventLog()

    host.adopt(ParkedWorker(name: "first", log: log))
    host.adopt(teardown: { log.append("observation cancelled") })
    host.adopt(ParkedWorker(name: "last", log: log))
    await settle()
    log.clear()

    // onCancel handlers run synchronously inside task.cancel(), so the
    // cancellation order below is the teardown order, not scheduling luck.
    host.teardownAll()
    XCTAssertEqual(
      log.events, ["last cancelled", "observation cancelled", "first cancelled"],
      "teardown unwinds the adoption list in reverse, workers interleaved with the rest")

    await settle()
    XCTAssertEqual(host.liveWorkerCount, 0, "every run() returned after cancellation")
  }

  func testAdoptedWorkerIsRetainedForTheMountAndReleasedAfterTeardown() async {
    let host = StoreHost()
    var worker: ParkedWorker? = ParkedWorker(name: "held", log: EventLog())
    weak var weakWorker = worker

    host.adopt(worker!)
    worker = nil
    await settle()
    XCTAssertNotNil(weakWorker, "adoption retains the worker for the mount's life")

    host.teardownAll()
    await settle()
    XCTAssertNil(weakWorker, "teardown releases it once run() returns")
  }

  func testUntilCancelledReleasesSubscriptionMachineryStructurally() async {
    let host = StoreHost()
    let subject = PassthroughSubject<Int, Never>()
    let worker = SubscribingWorker(source: subject)

    host.adopt(worker)
    await settle()
    subject.send(1)
    subject.send(2)
    XCTAssertEqual(worker.received, [1, 2], "run() set the subscription up before parking")

    host.teardownAll()
    await settle()
    subject.send(3)
    XCTAssertEqual(worker.received, [1, 2], "the parked run() returned; its locals cancelled the pipeline")
    XCTAssertEqual(host.liveWorkerCount, 0)
  }
}

// MARK: - Fixtures

/// Order-sensitive event recorder shared between workers and assertions.
@MainActor
private final class EventLog {
  private(set) var events: [String] = []
  func append(_ event: String) { events.append(event) }
  func clear() { events.removeAll() }
}

/// Loop-shaped worker: records its start, parks, records its cancellation.
@MainActor
private final class ParkedWorker: Working {
  private let name: String
  private let log: EventLog

  init(name: String, log: EventLog) {
    self.name = name
    self.log = log
  }

  func run() async {
    log.append("\(name) ran")
    await withTaskCancellationHandler {
      await untilCancelled()
    } onCancel: {
      // teardownAll() cancels on the main actor and onCancel runs
      // synchronously inside task.cancel() — assumeIsolated keeps the
      // ordering receipt synchronous rather than scheduling-dependent.
      MainActor.assumeIsolated { self.log.append("\(self.name) cancelled") }
    }
  }
}

/// Subscription-shaped worker: Combine machinery lives in run()'s locals and
/// dies structurally when the park returns.
@MainActor
private final class SubscribingWorker: Working {
  private let source: PassthroughSubject<Int, Never>
  private(set) var received: [Int] = []

  init(source: PassthroughSubject<Int, Never>) {
    self.source = source
  }

  func run() async {
    var bag = Set<AnyCancellable>()
    source
      .sink { [weak self] value in self?.received.append(value) }
      .store(in: &bag)
    await untilCancelled()
    bag.removeAll()
  }
}
