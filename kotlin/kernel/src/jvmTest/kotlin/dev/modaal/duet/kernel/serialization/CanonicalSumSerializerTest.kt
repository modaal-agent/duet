// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException

/**
 * Dialect receipts for the derived sum serializer (FC2 arm b): the
 * `{"case": …, "value": …}` envelope, the three payload shapes, the omit-nil
 * rule, and the loud failure modes. The registry convention under test is the
 * shipped one: `@SerialName` per case + one registry line per case.
 */
class CanonicalSumSerializerTest {

  @Serializable(with = EventSerializer::class)
  sealed interface Event

  @Serializable
  @SerialName("reset")
  data object Reset : Event

  @Serializable
  @SerialName("moved")
  data class Moved(val x: Int, val y: Int) : Event

  @Serializable
  @SerialName("renamed")
  data class Renamed(val name: String) : Event

  @Serializable
  @SerialName("noted")
  data class Noted(val note: String? = null) : Event

  // Deliberately NOT registered — the unregistered-subclass receipt.
  @Serializable
  @SerialName("rogue")
  data class Rogue(val v: Int) : Event

  object EventSerializer :
    CanonicalSumSerializer<Event>(
      "Event",
      listOf(
        case(Reset::class, Reset.serializer()),
        case(Moved::class, Moved.serializer()),
        case(Renamed::class, Renamed.serializer(), inline = true),
        case(Noted::class, Noted.serializer()),
      ))

  private val json = CanonicalSerializers.json

  private fun encode(event: Event): String =
    CanonicalJson.canonicalString(json.encodeToJsonElement(EventSerializer, event))

  private fun decode(raw: String): Event =
    json.decodeFromJsonElement(EventSerializer, json.parseToJsonElement(raw))

  @Test
  fun objectCaseOmitsValue() {
    assertEquals("""{"case":"reset"}""", encode(Reset))
    assertEquals(Reset, decode("""{"case":"reset"}"""))
  }

  @Test
  fun labeledCaseCarriesPropertyNames() {
    assertEquals("""{"case":"moved","value":{"x":1,"y":2}}""", encode(Moved(1, 2)))
    assertEquals(Moved(1, 2), decode("""{"case":"moved","value":{"x":1,"y":2}}"""))
  }

  @Test
  fun inlineCaseCarriesTheBarePayload() {
    assertEquals("""{"case":"renamed","value":"bob"}""", encode(Renamed("bob")))
    assertEquals(Renamed("bob"), decode("""{"case":"renamed","value":"bob"}"""))
  }

  @Test
  fun nilOnlyPayloadCollapsesToTheBareCase() {
    // explicitNulls = false: Noted(null) encodes to {}, which the envelope
    // emits as the bare case — the dialect's omit-nil rule, by construction.
    assertEquals("""{"case":"noted"}""", encode(Noted(null)))
    assertEquals(Noted(null), decode("""{"case":"noted"}"""))
    assertEquals("""{"case":"noted","value":{"note":"hi"}}""", encode(Noted("hi")))
  }

  @Test
  fun unknownCaseFailsLoudlyOnDecode() {
    assertFailsWith<SerializationException> { decode("""{"case":"vanished"}""") }
  }

  @Test
  fun unregisteredSubclassFailsLoudlyOnEncode() {
    assertFailsWith<SerializationException> { encode(Rogue(1)) }
  }
}
