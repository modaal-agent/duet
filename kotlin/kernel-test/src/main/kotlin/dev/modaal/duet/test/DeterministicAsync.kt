// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import java.lang.ref.WeakReference
import kotlin.test.fail
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.yield

/**
 * The deterministic-async toolkit, Kotlin half (spec 15 §6.3) — mirror-ruled
 * against DuetTesting/DeterministicAsync.swift, with the thinness the platform
 * earns recorded per primitive:
 *
 * - **Virtual time** needs no toolkit type at all: `runTest`'s scheduler IS the
 *   virtual clock, and the kernel's `LiveClock` suspends on it. (Swift needs a
 *   distinct `TestClock`; Kotlin's twin is the seam alone.)
 * - **Turn control** ([settleUntil], [settle]) — the drain-then-check and
 *   re-send-until-projected shapes as API. On the JVM these are thin wrappers
 *   over `advanceUntilIdle`, kept as named primitives so test intent reads
 *   identically on both platforms and flake-class fixes stay one idiom.
 * - **[ChildDeallocLedger]** — the churn-ledger weak-tracking assertion. The one
 *   primitive that CANNOT ride virtual time (GC is not virtual); it polls
 *   wall-clock briefly around explicit `System.gc()` requests.
 * - **[SuiteWallClockBudget]** — the degraded-host signature as an opt-in
 *   diagnostic (never a bound-widening prompt — the flake registry's standing
 *   rule).
 */

/**
 * Drains ready work and asserts [condition]. Rounds re-drain after each check
 * so conditions that trigger new work (a projection sending a follow-up
 * action) still settle deterministically.
 *
 * Platform finding, encoded here so nobody re-derives it: `advanceUntilIdle`
 * is FOREGROUND-filtered — with only `backgroundScope` work queued (workers,
 * shell observations) it runs nothing. `runCurrent`/`yield` drain background
 * tasks at the current virtual time, so this loop uses those. Virtual TIME
 * stays an explicit test act (`advanceTimeBy`) — same division as the Swift
 * twin, where `settleUntil` yields and `TestClock.advance` moves time.
 */
@OptIn(ExperimentalCoroutinesApi::class)
suspend fun TestScope.settleUntil(rounds: Int = 20, condition: () -> Boolean) {
  repeat(rounds) {
    if (condition()) return
    testScheduler.runCurrent()
    if (condition()) return
    yield()
  }
  if (!condition()) {
    fail("settleUntil: condition not met after $rounds settle rounds")
  }
}

/**
 * The re-send-until-projected pattern (flake class B) as API: re-issues
 * [byResending] and drains until [until] holds. For subscription-shaped seams
 * where the first send can race the downstream collector's subscription.
 */
@OptIn(ExperimentalCoroutinesApi::class)
suspend fun TestScope.settle(byResending: () -> Unit, rounds: Int = 20, until: () -> Boolean) {
  repeat(rounds) {
    if (until()) return
    byResending()
    testScheduler.runCurrent()
    if (until()) return
    yield()
  }
  if (!until()) {
    fail("settle(byResending:): condition not met after $rounds resend rounds")
  }
}

/**
 * The churn receipt: track child/store/worker instances at creation, assert
 * they are collectible after teardown — the leak class as a first-class
 * assertion. Wall-clock-bounded by nature (GC is not virtual time).
 */
class ChildDeallocLedger {
  private val tracked = mutableListOf<Pair<String, WeakReference<Any>>>()

  fun track(label: String, instance: Any) {
    tracked.add(label to WeakReference(instance))
  }

  /** Asserts every tracked instance has been collected; names the survivors. */
  fun assertAllReleased(timeoutMillis: Long = 2_000) {
    val deadline = System.nanoTime() + timeoutMillis * 1_000_000
    while (System.nanoTime() < deadline) {
      System.gc()
      if (tracked.all { it.second.get() == null }) return
      Thread.sleep(20)
    }
    val survivors = tracked.filter { it.second.get() != null }.map { it.first }
    if (survivors.isNotEmpty()) {
      fail("ChildDeallocLedger: still reachable after teardown: $survivors")
    }
  }
}

/**
 * The degraded-host diagnostic: a wall-clock budget for a suite (or any
 * bracket). Exceeding it REPORTS by default — a stale/overloaded host reads as
 * a diagnostic, never as a reason to widen assertion bounds; opt in to failing
 * for CI lanes that treat budget breaks as red.
 */
class SuiteWallClockBudget(
  private val budgetMillis: Long,
  private val failOnExceed: Boolean = false,
) {
  private val startNanos = System.nanoTime()

  /** Call at suite end (an `@AfterAll` / test-tail hook). */
  fun check(label: String = "suite") {
    val elapsedMillis = (System.nanoTime() - startNanos) / 1_000_000
    if (elapsedMillis <= budgetMillis) return
    val message =
      "SuiteWallClockBudget: $label took ${elapsedMillis} ms (budget ${budgetMillis} ms) — " +
        "degraded-host signature; check environment before touching assertion bounds"
    if (failOnExceed) fail(message) else System.err.println(message)
  }
}
