// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The runtime: owns state, runs the pure reducer on [send], executes the returned [Effect]
 * values via the feature's handler, and feeds handler-emitted actions back in.
 * Contract: contracts/store-kernel-contract.md §3. Swift-flavor mirror: Duet/Store.swift.
 *
 * [scope] is host-owned and must be main-dispatched (`Dispatchers.Main.immediate` in
 * production, a `TestDispatcher` in tests); cancelling it is the teardown that cancels every
 * in-flight effect (rule 5). [send] must only be called from that dispatcher (rule 1).
 */
class Store<S, A, P>(
  initialState: S,
  private val reducer: (S, A) -> Reduced<S, P>,
  private val handler: (P) -> Flow<A>,
  private val scope: CoroutineScope,
) {
  private val mutableState = MutableStateFlow(initialState)
  val state: StateFlow<S> = mutableState.asStateFlow()

  private val identifiedJobs = mutableMapOf<EffectId, Job>()
  private val anonymousJobs = mutableListOf<Job>()
  private var isReducing = false
  private val actionQueue = ArrayDeque<A>()

  /**
   * Reduces synchronously (the new state is observable before `send` returns), then starts
   * the emitted effects in declaration order. Actions sent while a reduce is running
   * (reentrancy via a synchronously-emitting handler) are queued, never reduced recursively
   * (rules 2–4).
   */
  fun send(action: A) {
    actionQueue.addLast(action)
    if (isReducing) return
    isReducing = true
    try {
      while (actionQueue.isNotEmpty()) {
        val next = actionQueue.removeFirst()
        val reduced = reducer(mutableState.value, next)
        mutableState.value = reduced.state
        reduced.effects.forEach { execute(it) }
      }
    } finally {
      isReducing = false
    }
  }

  /**
   * Cancels every in-flight effect without cancelling the host scope — for hosts whose
   * scope outlives the store. Hosts that own a dedicated scope can cancel that instead.
   */
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
        effect.id?.let { identifiedJobs.remove(it)?.cancel() }
        // The handler is invoked HERE, synchronously with effect start — the
        // flavor-invariant ordering the kernel-trace fixtures pin (the Swift
        // flavor builds the stream inside execute too). Handlers are cold-flow
        // constructors by contract; only consumption rides the coroutine.
        val stream = handler(effect.payload)
        val job = scope.launch { stream.collect { send(it) } }
        if (effect.id != null) {
          identifiedJobs[effect.id] = job
        } else {
          anonymousJobs.add(job)
        }
      }
    }
  }
}
