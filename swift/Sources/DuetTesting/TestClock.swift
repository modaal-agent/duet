// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import Duet

/// Virtual-time clock for T1/T2 tests (contract §5). `sleep` suspends until the test
/// calls `advance(byNanoseconds:)` past the deadline. Kotlin mirror: `runTest` virtual time.
public final class TestClock: KernelClock, @unchecked Sendable {
  private struct Sleeper {
    let id: UUID
    let deadline: UInt64
    let continuation: CheckedContinuation<Void, Error>
  }

  private let lock = NSLock()
  private var now: UInt64 = 0
  private var sleepers: [Sleeper] = []

  public init() {}

  public func sleep(nanoseconds: UInt64) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        lock.lock()
        let deadline = now + nanoseconds
        // A cancellation racing this registration is handled by the onCancel path below
        // (it may run before registration; check Task.isCancelled first).
        if Task.isCancelled {
          lock.unlock()
          continuation.resume(throwing: CancellationError())
          return
        }
        sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
        lock.unlock()
      }
    } onCancel: {
      lock.lock()
      let cancelled = sleepers.filter { $0.id == id }
      sleepers.removeAll { $0.id == id }
      lock.unlock()
      for sleeper in cancelled {
        sleeper.continuation.resume(throwing: CancellationError())
      }
    }
  }

  /// Advances virtual time, resumes every sleeper whose deadline passed (in deadline
  /// order), then yields repeatedly so resumed effects get to emit and deliver actions.
  public func advance(byNanoseconds delta: UInt64) async {
    // Let effect tasks started just before this call reach their first sleep —
    // otherwise a sleep registered after the advance misses it and waits forever.
    await Task.megaYield()
    let due = takeDueSleepers(advancingBy: delta)
    for sleeper in due {
      sleeper.continuation.resume()
      // Yield between resumes so a periodic effect can re-register its next sleep
      // before further time passes (matters when advancing across several periods).
      await Task.megaYield()
    }
    await Task.megaYield()
  }

  /// The locked slice of `advance`, synchronous so the lock never spans a suspension.
  private func takeDueSleepers(advancingBy delta: UInt64) -> [Sleeper] {
    lock.lock()
    defer { lock.unlock() }
    now += delta
    let due = sleepers.filter { $0.deadline <= now }.sorted { $0.deadline < $1.deadline }
    sleepers.removeAll { $0.deadline <= now }
    return due
  }
}

extension Task where Success == Never, Failure == Never {
  /// Cooperative-scheduling pressure valve for tests: give in-flight effect tasks
  /// enough scheduler turns to run to their next suspension point.
  public static func megaYield(count: Int = 20) async {
    for _ in 0..<count {
      await Task<Void, Never>.detached(priority: .background) { await Task.yield() }.value
    }
  }
}
