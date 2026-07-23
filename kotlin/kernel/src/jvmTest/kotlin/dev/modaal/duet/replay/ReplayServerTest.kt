// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.replay

import dev.modaal.duet.kernel.Reduced
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.jsonPrimitive

/**
 * Protocol receipts (contracts/replay-protocol-v1.md), subprocess-free:
 * `respond` is the pure half of the stdio loop.
 */
class ReplayServerTest {

  @Serializable
  data class PingState(val pings: Int = 0)

  private val registry =
    ReplayRegistry(
      listOf(
        ReplayFeature.entry(
          "ping",
          PingState.serializer(),
          String.serializer(),
          String.serializer(),
        ) { state, action ->
          when (action) {
            "ping" -> Reduced(state.copy(pings = state.pings + 1))
            else -> Reduced(state)
          }
        }))

  @Test
  fun handshakeAdvertisesTheRegistry() {
    val handshake = ReplayServer.handshake(registry)
    assertEquals("duet-replay", handshake["protocol"]?.jsonPrimitive?.content)
    assertEquals("1", handshake["version"]?.jsonPrimitive?.content)
    assertEquals("kotlin", handshake["platform"]?.jsonPrimitive?.content)
    assertEquals("""["ping"]""", handshake["features"].toString())
  }

  @Test
  fun reduceRoundTripsCanonicalStrings() {
    val response =
      ReplayServer.respond(
        """{"op":"reduce","feature":"ping","state":{"pings":1},"action":"ping"}""",
        registry)
    checkNotNull(response)
    assertEquals("""{"pings":2}""", response["state"]?.jsonPrimitive?.content)
    assertEquals("[]", response["effects"]?.jsonPrimitive?.content)
  }

  @Test
  fun errorsAreLoudAndSessionSafe() {
    assertEquals(
      "unknown feature 'ghost'",
      ReplayServer.respond(
          """{"op":"reduce","feature":"ghost","state":{},"action":"x"}""", registry)
        ?.get("error")?.jsonPrimitive?.content)
    assertEquals(
      "malformed request line",
      ReplayServer.respond("not json", registry)?.get("error")?.jsonPrimitive?.content)
    assertEquals(
      "unknown op 'sing'",
      ReplayServer.respond("""{"op":"sing"}""", registry)?.get("error")?.jsonPrimitive?.content)
  }

  @Test
  fun exitEndsTheSession() {
    assertNull(ReplayServer.respond("""{"op":"exit"}""", registry))
  }
}
