// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Combine
import DuetShells
import DuetTesting
import Foundation
import XCTest

/// WorkerTester receipts: the bracket (start → drive fakes → assert →
/// finish), and the exhaustivity analog — a worker whose `run()` survives
/// cancellation is reported as a failure, never a hang.
@MainActor
final class WorkerTesterTests: XCTestCase {

  func testBracketDrivesAWorkerThroughItsFakes() async {
    let source = PassthroughSubject<Int, Never>()
    let worker = DoublingWorker(source: source)
    let tester = WorkerTester(worker)

    tester.start()
    await settle()
    source.send(2)
    source.send(21)
    XCTAssertEqual(worker.doubled, [4, 42])

    await tester.finish()
  }

  func testCancelAndSettleReportsAHungWorkerInsteadOfHanging() async {
    let tester = WorkerTester(HungWorker())
    tester.start()
    await settle()

    let settled = await tester.cancelAndSettle(maxYields: 50)
    XCTAssertFalse(settled, "a run() that ignores cancellation must be reported, not awaited forever")
  }

  func testFinishWithoutStartIsTriviallySettled() async {
    let tester = WorkerTester(DoublingWorker(source: PassthroughSubject()))
    let settled = await tester.cancelAndSettle()
    XCTAssertTrue(settled)
  }

  func testSynchronousSurfaceServesPollingHarnesses() async {
    // The Quick-spec shape: sync start/cancel + eventually-true isFinished
    // (here settled with yields; Nimble consumers poll with toEventually).
    let tester = WorkerTester(DoublingWorker(source: PassthroughSubject()))
    tester.start()
    XCTAssertFalse(tester.isFinished)
    await settle()

    tester.cancel()
    var budget = 10_000
    while !tester.isFinished && budget > 0 {
      await Task.yield()
      budget -= 1
    }
    XCTAssertTrue(tester.isFinished)
  }
}

// MARK: - Fixtures

/// Subscription-shaped worker under test: consumes a fake source, records
/// its transform — the logical-test surface WorkerTester brackets.
@MainActor
private final class DoublingWorker: Working {
  private let source: PassthroughSubject<Int, Never>
  private(set) var doubled: [Int] = []

  init(source: PassthroughSubject<Int, Never>) {
    self.source = source
  }

  func run() async {
    var bag = Set<AnyCancellable>()
    source
      .sink { [weak self] value in self?.doubled.append(value * 2) }
      .store(in: &bag)
    await untilCancelled()
    bag.removeAll()
  }
}

/// The leak exemplar: parks on a continuation nothing ever resumes, so
/// cancellation never reaches it.
private final class HungWorker: Working {
  func run() async {
    await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
  }
}

private func settle(_ turns: Int = 20) async {
  for _ in 0..<turns {
    await Task.yield()
  }
}
