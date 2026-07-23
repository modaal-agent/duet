// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlinx.serialization.json.Json

/** Writer-rule receipts (contracts/serialization.md §1–§2, §6). */
class CanonicalJsonTest {

  private fun canonical(raw: String): String =
    CanonicalJson.canonicalString(Json.parseToJsonElement(raw))

  @Test
  fun sortsKeysByCodePoint() {
    assertEquals("""{"a":1,"b":2,"z":3}""", canonical("""{"z":3,"a":1,"b":2}"""))
  }

  @Test
  fun supplementaryCodePointsOrderAfterBmp() {
    // U+FF61 (halfwidth ideographic full stop) is one UTF-16 unit; U+1F600 is a
    // surrogate pair. Code-point order puts U+FF61 first — a UTF-16 unit-order
    // sort would invert them.
    assertEquals("{\"｡\":1,\"😀\":2}", canonical("{\"😀\":2,\"｡\":1}"))
  }

  @Test
  fun escapesOnlyTheContractSet() {
    assertEquals(
      "\"line\\nquote\\\"back\\\\tab\\tbell\\u0007\"",
      canonical("\"line\\nquote\\\"back\\\\tab\\tbell\\u0007\""))
  }

  @Test
  fun lowercasesUuidShapedStrings() {
    assertEquals(
      "\"6ba7b810-9dad-11d1-80b4-00c04fd430c8\"",
      canonical("\"6BA7B810-9DAD-11D1-80B4-00C04FD430C8\""))
  }

  @Test
  fun rejectsFloatingPointScalars() {
    assertFailsWith<IllegalArgumentException> { canonical("""{"x":1.5}""") }
  }

  @Test
  fun prettyFormMatchesThePinnedShape() {
    val pretty = CanonicalJson.prettyCanonicalString(Json.parseToJsonElement("""{"b":[1,2],"a":{}}"""))
    assertEquals("{\n  \"a\": {},\n  \"b\": [\n    1,\n    2\n  ]\n}\n", pretty)
  }
}
