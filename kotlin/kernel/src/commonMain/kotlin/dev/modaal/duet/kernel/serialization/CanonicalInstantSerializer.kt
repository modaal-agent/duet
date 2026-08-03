// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import kotlin.time.Instant
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * Canonical date form (contracts/serialization.md §2) for KMP-flavor common
 * code: ISO-8601 UTC with exactly 3 fractional digits and `Z`, built on
 * `kotlin.time.Instant` so it is COMMON — registered once in
 * [CanonicalSerializers.module] for all targets, which is what lets
 * Instant-carrying features cross the Apple boundary (the debt the
 * [registerPlatformContextualSerializers] KDoc recorded, discharged by the
 * first such feature: the reference adopter's capture, whose committed
 * fixtures are the byte validation).
 *
 * Byte-identity: the output is character-for-character the JVM
 * [InstantMillisSerializer] form (`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`,
 * sub-millisecond digits truncated — `DateTimeFormatter` truncates, never
 * rounds), proven by the kernel's cross-serializer test. Decoding uses
 * `Instant.parse`, which accepts the same ISO-8601 shapes
 * `java.time.Instant.parse` does.
 */
object CanonicalInstantSerializer : KSerializer<Instant> {
  override val descriptor: SerialDescriptor =
    PrimitiveSerialDescriptor(
      "dev.modaal.duet.kernel.serialization.InstantMillis.common", PrimitiveKind.STRING)

  override fun serialize(encoder: Encoder, value: Instant) {
    encoder.encodeString(format(value))
  }

  override fun deserialize(decoder: Decoder): Instant = Instant.parse(decoder.decodeString())

  private fun format(value: Instant): String {
    val millisTotal = value.toEpochMilliseconds() // floors toward -∞, like the formatter
    val days = millisTotal.floorDiv(86_400_000L)
    val millisOfDay = millisTotal.mod(86_400_000L)

    // Civil date from days-since-epoch (Howard Hinnant's algorithm).
    val z = days + 719_468L
    val era = (if (z >= 0) z else z - 146_096L) / 146_097L
    val dayOfEra = z - era * 146_097L
    val yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    val year0 = yearOfEra + era * 400L
    val dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    val mp = (5 * dayOfYear + 2) / 153
    val day = dayOfYear - (153 * mp + 2) / 5 + 1
    val month = if (mp < 10) mp + 3 else mp - 9
    val year = if (month <= 2) year0 + 1 else year0

    val hour = millisOfDay / 3_600_000L
    val minute = millisOfDay / 60_000L % 60
    val second = millisOfDay / 1_000L % 60
    val millis = millisOfDay % 1_000L

    fun pad(value: Long, width: Int): String = value.toString().padStart(width, '0')
    return "${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}" +
      "T${pad(hour, 2)}:${pad(minute, 2)}:${pad(second, 2)}.${pad(millis, 3)}Z"
  }
}
