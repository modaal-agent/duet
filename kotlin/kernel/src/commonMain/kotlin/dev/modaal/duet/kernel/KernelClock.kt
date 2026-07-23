// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel

import kotlin.time.Duration.Companion.nanoseconds
import kotlinx.coroutines.delay

/**
 * The clock seam for clocked effects (the C8 mirror twin, narrowed per FC2):
 * effect handlers take a [KernelClock] from the environment instead of calling
 * `delay` directly, which is what makes timeout/dwell effects fixture-visible
 * and deterministically testable. Swift-flavor mirror: Duet/Clock.swift
 * (`KernelClock` / `LiveClock`), same name, same geometry.
 *
 * Thinness record (the mirror rule's honest-sizing requirement): this twin has
 * NO separate test realization. Coroutine virtual time IS the test clock —
 * under `runTest`/`TestDispatcher`, [LiveClock]'s `delay` suspends on the
 * virtual scheduler, so tests advance it with the machinery they already use.
 * The Swift flavor needs a distinct `TestClock` type because Swift concurrency
 * has no ambient virtual time; Kotlin's realization is the seam alone.
 */
fun interface KernelClock {
  /**
   * Suspends for the given duration. Throws `CancellationException` if the
   * surrounding coroutine is cancelled while sleeping.
   */
  suspend fun sleep(nanoseconds: Long)
}

/** Wall-clock implementation for production wiring (virtual under `runTest`). */
object LiveClock : KernelClock {
  override suspend fun sleep(nanoseconds: Long) {
    delay(nanoseconds.nanoseconds)
  }
}
