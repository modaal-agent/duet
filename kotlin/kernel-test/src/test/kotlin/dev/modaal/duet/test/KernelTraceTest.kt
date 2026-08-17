// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.Effect
import dev.modaal.duet.kernel.Reduced
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.builtins.serializer

/**
 * The cross-flavor kernel gate: the KMP kernel replays the six committed
 * Swift-recorded trace fixtures BYTE-IDENTICALLY under coroutine virtual time
 * (contracts/kernel-trace-v0.md). The scripted feature mirrors the Swift
 * KernelTraceTests' exactly; the Swift recorder is the writer of record —
 * this side only verifies (no REGEN mode).
 */
class KernelTraceTest {

  private fun TestScope.makeRecorder(): KernelTraceRecorder<Int, String, String> =
    KernelTraceRecorder(
      scope = this,
      initialState = 0,
      stateSerializer = Int.serializer(),
      actionSerializer = String.serializer(),
      payloadSerializer = String.serializer(),
      reducer = { state, action ->
        when (action) {
          "inc" -> Reduced(state + 1)
          "start-ping" -> Reduced(state, listOf(Effect.Run("ping")))
          "start-two" -> Reduced(state, listOf(Effect.Run("alpha"), Effect.Run("beta")))
          "start-clocked" -> Reduced(state, listOf(Effect.Run("tick", id = "clock")))
          "cancel-clock" -> Reduced(state, listOf(Effect.Cancel("clock")))
          "start-park" -> Reduced(state, listOf(Effect.Run("park")))
          "burst" -> Reduced(state, listOf(Effect.Run("burst")))
          "pong", "ticked", "b2", "chain-done" -> Reduced(state + 10)
          "b1" -> Reduced(state + 100)
          "start-chain" -> Reduced(state, listOf(Effect.Run("chained")))
          else -> Reduced(state)
        }
      },
      handler = { payload, clock ->
        when (payload) {
          "ping" -> flowOf("pong")
          "alpha" -> emptyFlow()
          // Finishes on the clock, one advance later — cross-effect ending
          // order within one settle window is CONTRACT-UNDEFINED (the trace
          // design's one-ending-per-window rule; kernel-trace-v0.md §3).
          "beta" -> flow { clock.sleep(50_000_000) }
          "tick" ->
            flow {
              clock.sleep(100_000_000)
              emit("ticked")
            }
          "park" -> flow { clock.sleep(10_000_000_000) }
          "burst" -> flowOf("b1", "b2")
          "chained" -> flowOf("chain-done")
          else -> emptyFlow<String>()
        } as Flow<String>
      })

  // MARK: the six rule traces

  @Test
  fun sendReduceSynchronous() = runTest {
    val recorder = makeRecorder()
    recorder.send("inc")
    recorder.send("inc")
    recorder.teardown()
    verify(recorder, "send-reduce-sync")
  }

  @Test
  fun effectStartOrderIsDeclarationOrder() = runTest {
    val recorder = makeRecorder()
    recorder.send("start-two")
    recorder.advance(byNanoseconds = 50_000_000)
    recorder.teardown()
    verify(recorder, "effect-start-order")
  }

  @Test
  fun effectRoundTripDeliversThroughTheQueue() = runTest {
    val recorder = makeRecorder()
    recorder.send("start-ping")
    recorder.teardown()
    verify(recorder, "effect-roundtrip")
  }

  @Test
  fun cancelInFlightByIdAndSameIdRestart() = runTest {
    val recorder = makeRecorder()
    recorder.send("start-clocked")
    recorder.advance(byNanoseconds = 50_000_000)
    recorder.send("cancel-clock")
    recorder.advance(byNanoseconds = 100_000_000) // nothing may fire
    recorder.send("start-clocked")
    recorder.send("start-clocked") // same-id restart cancels the first
    recorder.advance(byNanoseconds = 100_000_000) // exactly one tick
    recorder.teardown()
    verify(recorder, "cancel-in-flight")
  }

  @Test
  fun teardownCancelsEverything() = runTest {
    val recorder = makeRecorder()
    recorder.send("start-park")
    recorder.teardown()
    recorder.advance(byNanoseconds = 200_000_000) // silence after teardown
    verify(recorder, "teardown-cancels")
  }

  @Test
  fun reentrancyQueuesNeverNests() = runTest {
    val recorder = makeRecorder()
    recorder.send("burst")
    recorder.send("start-chain")
    recorder.teardown()
    verify(recorder, "reentrancy-queue")
  }

  // MARK: the byte gate

  private fun verify(recorder: KernelTraceRecorder<Int, String, String>, fixture: String) {
    val file = File(fixturesDirectory(), "$fixture.trace.jsonl")
    require(file.isFile) { "trace fixture not found: ${file.path}" }
    val committed = file.readText()
    val produced = recorder.canonicalTrace()
    assertEquals(
      committed,
      produced,
      "kernel trace '$fixture' diverged from the committed Swift-recorded fixture — " +
        "a kernel-flavor behavior difference (the cross-flavor kernel gate)")
  }

  /** The ONE fixture set, both flavors: swift/Tests/parity/fixtures/kernel-trace. */
  private fun fixturesDirectory(): File {
    var dir: File? = File(System.getProperty("user.dir")).absoluteFile
    while (dir != null) {
      val candidate = File(dir, "swift/Tests/parity/fixtures/kernel-trace")
      if (candidate.isDirectory) return candidate
      dir = dir.parentFile
    }
    error("could not locate swift/Tests/parity/fixtures/kernel-trace from ${System.getProperty("user.dir")}")
  }
}
