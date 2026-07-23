// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.Effect
import dev.modaal.duet.kernel.EffectId
import dev.modaal.duet.kernel.Reduced
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield

/**
 * Exhaustive test store — contract §5 (failure rules E1–E5). Runs the real reducer and
 * really executes effects (on [scope]'s test dispatcher, so `delay` is virtual time), but
 * records everything so nothing can happen unasserted.
 * Swift mirror: DuetTesting/TestStore.swift.
 *
 * The `assert` closures mirror Swift's `inout` closure via `copy`:
 * `store.send(Increment) { it.copy(count = 1) }` receives the pre-action state and must
 * return *exactly* the post-reduce state (whole-value equality, E1).
 */
class TestStore<S, A, P>(
  initialState: S,
  private val reducer: (S, A) -> Reduced<S, P>,
  private val handler: (P) -> Flow<A>,
  private val scope: CoroutineScope,
) {
  var state: S = initialState
    private set

  private val receivedBuffer = ArrayDeque<A>()
  private val unassertedEffects = mutableListOf<Effect<P>>()
  private val identifiedJobs = mutableMapOf<EffectId, Job>()
  private val anonymousJobs = mutableListOf<Job>()
  private var activeEffectCount = 0

  /** E1: `assert` must produce exactly the post-reduce state. */
  fun send(action: A, assert: ((S) -> S)? = null) {
    val expected = assert?.invoke(state) ?: state
    val reduced = reducer(state, action)
    state = reduced.state
    assertEquals(expected, state, "send($action) state mismatch (E1)")
    unassertedEffects.addAll(reduced.effects)
    reduced.effects.forEach { execute(it) }
  }

  /** E3/E4: awaits the next handler-emitted action and asserts it (action + state change). */
  suspend fun receive(expectedAction: A, assert: ((S) -> S)? = null) {
    var attempts = 0
    while (receivedBuffer.isEmpty() && attempts < 200) {
      yield()
      attempts++
    }
    if (receivedBuffer.isEmpty()) {
      fail("receive($expectedAction): no action arrived (E4)")
    }
    val actual = receivedBuffer.removeFirst()
    assertEquals(expectedAction, actual, "receive: unexpected action")
    val expected = assert?.invoke(state) ?: state
    val reduced = reducer(state, actual)
    state = reduced.state
    assertEquals(expected, state, "receive($actual) state mismatch (E1)")
    unassertedEffects.addAll(reduced.effects)
    reduced.effects.forEach { execute(it) }
  }

  /** E2: pops and asserts every effect emitted since the last call. */
  fun expectEffects(expected: List<Effect<P>>) {
    assertEquals(expected, unassertedEffects.toList(), "effects mismatch (E2)")
    unassertedEffects.clear()
  }

  /** E2/E3/E5 closing check. Call at the end of every test. */
  suspend fun finish() {
    var attempts = 0
    while (activeEffectCount > 0 && attempts < 200) {
      yield()
      attempts++
    }
    assertTrue(
      unassertedEffects.isEmpty(),
      "unasserted effects at finish (E2): $unassertedEffects")
    assertTrue(
      receivedBuffer.isEmpty(),
      "unreceived actions at finish (E3): $receivedBuffer")
    assertEquals(
      0, activeEffectCount,
      "effect(s) still in flight at finish (E5) — cancel long-lived effects explicitly " +
        "(mirror of host teardown)")
  }

  /** Cancels everything — the teardown mirror, for tests that end mid-flight on purpose. */
  fun teardown() {
    identifiedJobs.values.forEach { it.cancel() }
    identifiedJobs.clear()
    anonymousJobs.forEach { it.cancel() }
    anonymousJobs.clear()
  }

  private fun execute(effect: Effect<P>) {
    when (effect) {
      is Effect.Cancel -> identifiedJobs.remove(effect.id)?.cancel()
      is Effect.Run -> {
        val id = effect.id
        id?.let { identifiedJobs.remove(it)?.cancel() }
        activeEffectCount++
        val job = scope.launch { handler(effect.payload).collect { receivedBuffer.addLast(it) } }
        // invokeOnCompletion, not try/finally: a job cancelled before it first runs never
        // executes its body (unlike a Swift Task), but completion handlers always fire.
        job.invokeOnCompletion { activeEffectCount-- }
        if (id != null) {
          identifiedJobs[id] = job
        } else {
          anonymousJobs.add(job)
        }
      }
    }
  }
}
