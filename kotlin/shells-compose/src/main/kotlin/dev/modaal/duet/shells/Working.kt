// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import kotlinx.coroutines.awaitCancellation

// The worker seam: lifecycle-bound stateful processing, re-substrated on
// structured concurrency (doc 20). A worker is an environment-side object that
// may own mutable state and long-lived subscriptions, bracketed by a host's
// mount lifetime, feeding features ONLY through the existing seams —
// environment Flows consumed by effect handlers, or actions through a
// shell-bound Relay. Workers never touch stores or feature state ("no silent
// ingress"); workers process, reducers decide (R16).
//
// Config-change stance (Q2): Android workers live in the RETAINED/logical
// component scope (the tree that survives rotation — InstanceKeeper-backed
// under Decompose), so "one bracket per mount" means LOGICAL mount on both
// platforms. View-bound scopes stay for view-side observation only.

/**
 * One worker: `run()` is its whole life. A host starts it at adoption
 * ([StoreHost.adopt]) and cancellation of the launched coroutine IS stop —
 * there is no separate `stop()` to forget. One bracket per (logical) mount: a
 * remount adopts a fresh instance; "pause when backgrounded" is consumed as an
 * input stream, never a lifecycle callback.
 *
 * Implementation guidance, not API: stateful workers confine their state to
 * the host's (main-confined) scope — isolation replaces hand-rolled locks. The
 * `run()` body and its structured children are a sanctioned concurrency home;
 * a worker launching unstructured jobs is the same review defect it would be
 * in feature code. Swift-flavor mirror: DuetShells/Working.swift.
 */
fun interface Working {
  /**
   * The worker's whole life, from adoption to host teardown. MUST return
   * promptly once cancelled — a worker still running after cancellation is a
   * leak (`WorkerTester.finish()` fails on it, and the host's
   * [StoreHost.liveWorkerCount] ledger stays nonzero).
   */
  suspend fun run()
}

/**
 * The bracket tail for subscription-shaped workers: set the subscriptions up in
 * `run()`, then `untilCancelled()`. Thinness note: on Kotlin this is
 * [awaitCancellation] — structured concurrency provides the park; the Swift
 * twin needs a hand-rolled continuation.
 */
suspend fun untilCancelled(): Nothing = awaitCancellation()
