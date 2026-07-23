// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.KernelClock
import dev.modaal.duet.kernel.LiveClock
import dev.modaal.duet.kernel.Reduced
import dev.modaal.duet.kernel.Store
import dev.modaal.duet.kernel.serialization.CanonicalJson
import dev.modaal.duet.kernel.serialization.CanonicalSerializers
import kotlin.time.Duration.Companion.nanoseconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.yield
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// G3 — the kernel-trace apparatus, Kotlin side: the KMP flavor replays the SAME
// committed trace fixtures the Swift flavor records
// (swift/Tests/parity/fixtures/kernel-trace/), byte-identically, under
// coroutine virtual time. Contract: contracts/kernel-trace-v0.md. The Swift
// recorder is the corpus's writer of record; this side only verifies.

/** One observable kernel event, in trace order. Payload strings are canonical JSON. */
sealed interface KernelTraceEvent {
  data class Send(val action: String) : KernelTraceEvent
  data class Reduce(val action: String, val state: String) : KernelTraceEvent
  data class EffectStart(val payload: String, val id: String?) : KernelTraceEvent
  data class EffectAction(val action: String) : KernelTraceEvent
  data class EffectCancelled(val payload: String) : KernelTraceEvent
  data class EffectFinished(val payload: String) : KernelTraceEvent
  data class Advance(val nanoseconds: Long) : KernelTraceEvent
  data object Teardown : KernelTraceEvent
}

/** One canonical JSON line per event (jsonl — the fixture's byte form). */
val KernelTraceEvent.canonicalLine: String
  get() {
    val obj =
      when (this) {
        is KernelTraceEvent.Send -> buildJsonObject {
          put("event", "send")
          put("action", action)
        }
        is KernelTraceEvent.Reduce -> buildJsonObject {
          put("event", "reduce")
          put("action", action)
          put("state", state)
        }
        is KernelTraceEvent.EffectStart -> buildJsonObject {
          put("event", "effectStart")
          put("payload", payload)
          if (id == null) put("id", JsonNull) else put("id", id)
        }
        is KernelTraceEvent.EffectAction -> buildJsonObject {
          put("event", "effectAction")
          put("action", action)
        }
        is KernelTraceEvent.EffectCancelled -> buildJsonObject {
          put("event", "effectCancelled")
          put("payload", payload)
        }
        is KernelTraceEvent.EffectFinished -> buildJsonObject {
          put("event", "effectFinished")
          put("payload", payload)
        }
        is KernelTraceEvent.Advance -> buildJsonObject {
          put("event", "advance")
          put("nanoseconds", nanoseconds)
        }
        KernelTraceEvent.Teardown -> buildJsonObject { put("event", "teardown") }
      }
    return CanonicalJson.canonicalString(obj)
  }

/**
 * Records a kernel trace by wrapping a feature's reducer and handler around a
 * REAL [Store] on the test scope's virtual scheduler. Determinism is
 * structural on this platform (thinness notes vs the Swift twin):
 *
 * - **Lockstep is free**: a Flow's `emit` runs the store's collector — and
 *   therefore the send→reduce cycle — synchronously in the same coroutine, so
 *   delivery order in the trace IS reduce order with no wait loop.
 * - **The log needs no lock**: every append runs on the single-threaded test
 *   dispatcher (effect endings included — cancellation resumptions dispatch
 *   there too).
 * - Quiescence is the same signal as Swift: no new events across consecutive
 *   drain rounds (`runCurrent` + `yield` — the foreground-filter finding in
 *   DeterministicAsync.kt applies here too).
 *
 * Swift-flavor mirror: DuetTesting/KernelTrace.swift.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class KernelTraceRecorder<S, A, P>(
  private val scope: TestScope,
  initialState: S,
  stateSerializer: KSerializer<S>,
  private val actionSerializer: KSerializer<A>,
  payloadSerializer: KSerializer<P>,
  reducer: (S, A) -> Reduced<S, P>,
  handler: (P, KernelClock) -> Flow<A>,
) {
  /** Virtual under the test scheduler — `advance` moves it. */
  val clock: KernelClock = LiveClock

  private val json = CanonicalSerializers.json
  private val events = mutableListOf<KernelTraceEvent>()

  private fun <T> canonical(serializer: KSerializer<T>, value: T): String =
    CanonicalJson.canonicalString(json.encodeToJsonElement(serializer, value))

  val store: Store<S, A, P> =
    Store(
      initialState = initialState,
      reducer = { state, action ->
        val reduced = reducer(state, action)
        events.add(
          KernelTraceEvent.Reduce(
            action = canonical(actionSerializer, action),
            state = canonical(stateSerializer, reduced.state)))
        reduced
      },
      handler = { payload ->
        val payloadCanonical = canonical(payloadSerializer, payload)
        // Synchronous with effect start (the Store invokes handlers inside
        // execute — the trace-pinned flavor-invariant ordering).
        events.add(KernelTraceEvent.EffectStart(payload = payloadCanonical, id = null))
        handler(payload, clock)
          .let { upstream ->
            flow {
              upstream.collect { action ->
                events.add(
                  KernelTraceEvent.EffectAction(action = canonical(actionSerializer, action)))
                emit(action) // the store's collector reduces synchronously in here
              }
            }
          }
          .onCompletion { cause ->
            if (cause is CancellationException) {
              events.add(KernelTraceEvent.EffectCancelled(payload = payloadCanonical))
            } else {
              events.add(KernelTraceEvent.EffectFinished(payload = payloadCanonical))
            }
          }
      },
      scope = scope.backgroundScope,
    )

  /** Scripted send: logs the stimulus, sends, then settles to quiescence. */
  suspend fun send(action: A) {
    events.add(KernelTraceEvent.Send(action = canonical(actionSerializer, action)))
    store.send(action)
    settleQuiescent()
  }

  suspend fun advance(byNanoseconds: Long) {
    events.add(KernelTraceEvent.Advance(nanoseconds = byNanoseconds))
    scope.testScheduler.advanceTimeBy(byNanoseconds.nanoseconds)
    settleQuiescent()
  }

  suspend fun teardown() {
    events.add(KernelTraceEvent.Teardown)
    store.teardown()
    settleQuiescent()
  }

  /**
   * Drains until the trace is stable for [stableRounds] consecutive rounds
   * (bounded): pending clocked sleeps produce no events until advanced, so
   * stability — not idleness — is the quiescence signal.
   */
  private suspend fun settleQuiescent(stableRounds: Int = 3, maxRounds: Int = 200) {
    var streak = 0
    var rounds = 0
    var lastCount = events.size
    while (streak < stableRounds && rounds < maxRounds) {
      scope.testScheduler.runCurrent()
      yield()
      rounds += 1
      val count = events.size
      if (count == lastCount) {
        streak += 1
      } else {
        streak = 0
        lastCount = count
      }
    }
  }

  /** The fixture's byte form: one canonical JSON line per event + trailing newline. */
  fun canonicalTrace(): String =
    events.joinToString(separator = "\n", postfix = "\n") { it.canonicalLine }
}
