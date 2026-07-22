// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetShells
import Foundation
import XCTest

/// The worker seam's test bracket: instantiate the worker with fakes
/// (mutation gateways, virtual-time clocks), `start()` it, drive the fakes,
/// assert emitted stream values / recorded imperative calls, then `finish()`.
///
/// Workers carry logical tests only — behavioral assertions through this
/// harness, never fixtures; parity is never gated at the worker. The leak
/// guarantee is the harness's, not a convention's: a worker whose `run()` has
/// not returned after cancellation fails the test at `finish()`.
///
/// Deliberately nonisolated (state under a lock): callable from async XCTest
/// methods AND from synchronous spec DSLs (Quick `it` closures — the legacy
/// suites the worker sweep converts). Polling consumers pair `cancel()` with
/// an eventually-true `isFinished`; async consumers use `finish()`, which is
/// wall-clock-free by construction — settling is a bounded yield loop, not a
/// timeout. `start()` launches `run()` on the global executor; anything the
/// worker delivers to the main thread still needs the consumer's usual
/// main-loop pumping (Nimble's `toEventually`, or yields).
public final class WorkerTester<W: Working>: @unchecked Sendable {
  public let worker: W

  private let lock = NSLock()
  private var task: Task<Void, Never>?
  private var completed = false

  public init(_ worker: W) {
    self.worker = worker
  }

  /// Starts `run()` in a dedicated task — the `StoreHost.adopt` bracket,
  /// test-side.
  public func start() {
    lock.lock()
    precondition(task == nil, "start() called twice — one bracket per tester")
    task = Task { [worker] in
      await worker.run()
      self.markCompleted()
    }
    lock.unlock()
  }

  /// Cancels the worker's task without waiting. Poll `isFinished` to
  /// eventually-assert settling from synchronous harnesses.
  public func cancel() {
    lock.lock()
    let task = task
    lock.unlock()
    task?.cancel()
  }

  /// Whether `run()` has returned. Never started counts as finished (nothing
  /// is running).
  public var isFinished: Bool {
    lock.lock()
    defer { lock.unlock() }
    return task == nil || completed
  }

  /// Cancels the worker's task and yields until `run()` returns, bounded by
  /// `maxYields`. Returns whether the worker settled.
  @discardableResult
  public func cancelAndSettle(maxYields: Int = 10_000) async -> Bool {
    cancel()
    var budget = maxYields
    while !isFinished && budget > 0 {
      await Task.yield()
      budget -= 1
    }
    return isFinished
  }

  /// The exhaustivity analog for workers: cancels, settles, and FAILS if
  /// `run()` is still running — the leak class that stop-by-convention could
  /// not catch, made a harness guarantee.
  public func finish(
    maxYields: Int = 10_000, file: StaticString = #filePath, line: UInt = #line
  ) async {
    let settled = await cancelAndSettle(maxYields: maxYields)
    if !settled {
      XCTFail(
        """
        \(type(of: worker)) is still running after cancellation — run() must \
        return promptly once its task is cancelled (park on untilCancelled(), \
        or check Task.isCancelled in loops)
        """,
        file: file, line: line)
    }
  }

  private func markCompleted() {
    lock.lock()
    completed = true
    lock.unlock()
  }
}
