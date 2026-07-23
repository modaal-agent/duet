// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.replay

import dev.modaal.duet.kernel.Effect
import dev.modaal.duet.kernel.Reduced
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.serializer

/**
 * Receipts for the flavor-side replay adapter: the typed registry entry's
 * decode → reduce → canonical-encode step, the stateful session as a strict
 * convenience over it, and the tolerant spine boundary.
 */
class BoundaryReplayTest {

  @Serializable
  data class CounterState(val count: Int = 0, val ticking: Boolean = false)

  private val entry =
    ReplayFeature.entry(
      "counter",
      CounterState.serializer(),
      String.serializer(),
      String.serializer(),
    ) { state, action ->
      when (action) {
        "inc" -> Reduced(state.copy(count = state.count + 1))
        "start" ->
          Reduced(state.copy(ticking = true), listOf(Effect.Run("tick", id = "counter.tick")))
        "stop" -> Reduced(state.copy(ticking = false), listOf(Effect.Cancel("counter.tick")))
        else -> Reduced(state)
      }
    }

  private val registry = ReplayRegistry(listOf(entry))

  @Test
  fun statelessStepReturnsCanonicalStateAndEffects() {
    val result = entry.step("""{"count": 0, "ticking": false}""", "\"start\"")
    assertEquals("""{"count":0,"ticking":true}""", result.stateCanonical)
    assertEquals(
      """[{"id":"counter.tick","kind":"run","payload":"tick"}]""",
      result.effectsCanonical)
  }

  @Test
  fun sessionThreadsStateAcrossSteps() {
    val session = BoundaryReplay.makeSession(registry, "counter", """{"count":0,"ticking":false}""")
    session.step("\"inc\"")
    val second = session.step("\"inc\"")
    assertEquals("""{"count":2,"ticking":false}""", second.stateCanonical)
    assertEquals("[]", second.effectsCanonical)
  }

  @Test
  fun unknownFeatureFailsLoudly() {
    assertFailsWith<IllegalArgumentException> {
      BoundaryReplay.makeSession(registry, "ghost", "{}")
    }
  }

  @Test
  fun canonicalizeUsesTheCoreWriter() {
    assertEquals("""{"a":1,"b":2}""", BoundaryReplay.canonicalize("""{"b": 2, "a": 1}"""))
  }

  @Test
  fun spineBoundaryRoundTripsAndRestoresNothingOnForeignPayloads() {
    val spine = CounterState(count = 3, ticking = true)
    val encoded = SpineBoundary.encode(CounterState.serializer(), spine)
    assertEquals("""{"count":3,"ticking":true}""", encoded)
    assertEquals(spine, SpineBoundary.decode(CounterState.serializer(), encoded))
    assertNull(SpineBoundary.decode(CounterState.serializer(), "not json"))
    assertNull(SpineBoundary.decode(CounterState.serializer(), """{"count":"nope"}"""))
  }
}
