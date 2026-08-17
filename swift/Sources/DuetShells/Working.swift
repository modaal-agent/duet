// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

// The worker seam: lifecycle-bound stateful processing, re-substrated on
// structured concurrency. A worker is an environment-side object that may own
// mutable state and long-lived subscriptions, bracketed by a host's mount
// lifetime, feeding features ONLY through the existing seams — environment
// streams consumed by effect handlers, or actions through a shell-bound Relay.
// Workers never touch stores or feature state ("no silent ingress"), and a
// worker that grows decision logic is asking to move it into a reducer:
// workers process, reducers decide.
//
// Deliberately freestanding: no kernel type appears in this file, so a legacy
// app can adopt the worker bracket before it adopts the kernel.

/// One worker: `run()` is its whole life. A host starts it at adoption
/// (`StoreHost.adopt`) and cancellation of the surrounding task IS stop —
/// there is no separate `stop()` to forget. One bracket per mount: a remount
/// adopts a fresh instance; "pause when backgrounded" is consumed as an input
/// stream (scenePhase is data), never a lifecycle callback.
///
/// Implementation guidance, not API: stateful workers are `actor`s, or
/// `@MainActor` classes when main-bound — isolation replaces hand-rolled
/// serial queues and locks. The `run()` body and its structured children are
/// a sanctioned concurrency home; a worker spawning unstructured `Task {}`s
/// is the same review defect it would be in feature code.
public protocol Working: AnyObject, Sendable {
  /// The worker's whole life, from adoption to host teardown. MUST return
  /// promptly once the surrounding task is cancelled — a worker still running
  /// after cancellation is a leak (`WorkerTester.finish()` fails on it, and
  /// the host's `liveWorkerCount` ledger stays nonzero).
  func run() async
}

extension Working {
  /// The bracket tail for workers whose machinery is subscription-shaped
  /// (Combine pipelines, callback registries) rather than loop-shaped: set up
  /// the subscriptions in `run()`, then `await untilCancelled()`. Returns when
  /// the surrounding task is cancelled; locals then release, cancelling the
  /// subscriptions — teardown stays structured without a `stop()` hook.
  public func untilCancelled() async {
    let park = Park()
    await withTaskCancellationHandler {
      await park.wait()
    } onCancel: {
      park.cancel()
    }
  }
}

/// The parked continuation behind `untilCancelled()`, tolerant of the
/// cancel-before-wait race. Lock discipline: the lock is only ever taken in
/// synchronous scopes (the continuation body and `cancel()`), never across a
/// suspension.
private final class Park: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var cancelled = false

  func wait() async {
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
      lock.lock()
      if cancelled {
        lock.unlock()
        cont.resume()
      } else {
        continuation = cont
        lock.unlock()
      }
    }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let cont = continuation
    continuation = nil
    lock.unlock()
    cont?.resume()
  }
}
