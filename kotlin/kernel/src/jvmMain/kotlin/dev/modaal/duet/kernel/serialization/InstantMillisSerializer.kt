// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * Canonical date form (contracts/serialization.md §2): ISO-8601 UTC with exactly 3
 * fractional digits and `Z`. Swift-flavor mirror: the `DateFormatter` in
 * DuetTesting's CanonicalJSON / the fixture decoder strategy. Registered
 * contextually; feature models annotate `@Contextual val createdAt: Instant`.
 */
object InstantMillisSerializer : KSerializer<Instant> {
  private val formatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

  override val descriptor: SerialDescriptor =
    PrimitiveSerialDescriptor("dev.modaal.duet.kernel.serialization.InstantMillis", PrimitiveKind.STRING)

  override fun serialize(encoder: Encoder, value: Instant) {
    encoder.encodeString(formatter.format(value))
  }

  override fun deserialize(decoder: Decoder): Instant = Instant.parse(decoder.decodeString())
}
