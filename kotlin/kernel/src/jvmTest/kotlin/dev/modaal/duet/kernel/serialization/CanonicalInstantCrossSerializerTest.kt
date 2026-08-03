// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import java.time.Instant as JavaInstant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.time.Instant
import kotlinx.serialization.json.Json

/**
 * The 0.1.2 byte pin: the COMMON canonical Instant ([CanonicalInstantSerializer],
 * `kotlin.time.Instant`) emits character-for-character what the JVM
 * [InstantMillisSerializer] (`java.time.Instant`) emits — including the
 * truncation (never rounding) of sub-millisecond digits — and both re-parse
 * each other's output. This is what makes a JVM-authored fixture corpus valid
 * for a commonMain feature that swapped its date type (the reference
 * adopter's capture).
 */
class CanonicalInstantCrossSerializerTest {

  private val samples =
    listOf(
      "0", // the epoch itself
      "1782640800000", // a capture-fixture-era date (2026)
      "1700000000123", // non-zero millis
      "1699999999999", // millis boundary
    )

  @Test
  fun commonFormMatchesTheJvmFormByteForByte() {
    for (sample in samples) {
      val millis = sample.toLong()
      val common = Json.encodeToString(CanonicalInstantSerializer, Instant.fromEpochMilliseconds(millis))
      val jvm = Json.encodeToString(InstantMillisSerializer, JavaInstant.ofEpochMilli(millis))
      assertEquals(jvm, common, "epoch millis $millis")
    }
  }

  @Test
  fun subMillisecondDigitsTruncateLikeTheFormatter() {
    // 123456789 ns = .123 in both forms — DateTimeFormatter truncates, and so
    // does toEpochMilliseconds()'s floor.
    val common =
      Json.encodeToString(
        CanonicalInstantSerializer, Instant.fromEpochSeconds(1_700_000_000, 123_956_789))
    val jvm =
      Json.encodeToString(
        InstantMillisSerializer, JavaInstant.ofEpochSecond(1_700_000_000, 123_956_789))
    assertEquals(jvm, common)
    assertEquals("\"2023-11-14T22:13:20.123Z\"", common)
  }

  @Test
  fun decodeAcceptsTheCanonicalForm() {
    val decoded = Json.decodeFromString(CanonicalInstantSerializer, "\"2026-07-28T10:00:00.000Z\"")
    assertEquals(
      JavaInstant.parse("2026-07-28T10:00:00.000Z").toEpochMilli(),
      decoded.toEpochMilliseconds())
  }
}
