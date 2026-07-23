// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.shells.Working
import kotlin.test.fail
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield

/**
 * The worker seam's test bracket: instantiate the worker with fakes (mutation
 * gateways, virtual-time environments), [start] it on the test scope, drive
 * the fakes, assert emitted stream values / recorded imperative calls, then
 * [finish].
 *
 * Workers carry logical tests only — behavioral assertions through this
 * harness, never fixtures; parity is never gated at the worker. The leak
 * guarantee is the harness's, not a convention's: a worker whose `run()` has
 * not returned after cancellation fails the test at [finish].
 *
 * Thinness note (vs the Swift twin): under `runTest` the launch/cancel/settle
 * mechanics ride the virtual scheduler — no lock, no global-executor caveats;
 * settling is a bounded yield loop, wall-clock-free by construction.
 * Swift-flavor mirror: DuetTesting/WorkerTester.swift.
 */
class WorkerTester<W : Working>(val worker: W) {
  private var job: Job? = null
  private var completed = false

  /** Starts `run()` in a dedicated coroutine — the `StoreHost.adopt` bracket, test-side. */
  fun start(scope: CoroutineScope) {
    check(job == null) { "start() called twice — one bracket per tester" }
    job =
      scope.launch { worker.run() }.also { launched ->
        launched.invokeOnCompletion { completed = true }
      }
  }

  /** Cancels the worker's coroutine without waiting. */
  fun cancel() {
    job?.cancel()
  }

  /** Whether `run()` has returned. Never started counts as finished (nothing is running). */
  val isFinished: Boolean
    get() = job == null || completed

  /** Cancels and yields until `run()` returns, bounded by [maxYields]. Returns whether it settled. */
  suspend fun cancelAndSettle(maxYields: Int = 10_000): Boolean {
    cancel()
    var budget = maxYields
    while (!isFinished && budget > 0) {
      yield()
      budget -= 1
    }
    return isFinished
  }

  /**
   * The exhaustivity analog for workers: cancels, settles, and FAILS if
   * `run()` is still running — the leak class that stop-by-convention could
   * not catch, made a harness guarantee.
   */
  suspend fun finish(maxYields: Int = 10_000) {
    if (!cancelAndSettle(maxYields)) {
      fail(
        "${worker::class.simpleName} is still running after cancellation — run() must " +
          "return promptly once its coroutine is cancelled (park on untilCancelled(), " +
          "or keep loops cancellation-cooperative)")
    }
  }
}
