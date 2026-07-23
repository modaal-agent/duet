// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import java.util.UUID
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * Canonical UUID form (contracts/serialization.md §2) for JVM-authored feature code
 * carrying `java.util.UUID`: `toString()` is already lowercase; decoding accepts
 * either case (mirrors Swift's `UUID(uuidString:)`). KMP-flavor common code uses
 * `kotlin.uuid.Uuid` + [CanonicalUuidSerializer] instead — same bytes.
 */
object UuidSerializer : KSerializer<UUID> {
  override val descriptor: SerialDescriptor =
    PrimitiveSerialDescriptor("dev.modaal.duet.kernel.serialization.JavaUuid", PrimitiveKind.STRING)

  override fun serialize(encoder: Encoder, value: UUID) {
    encoder.encodeString(value.toString())
  }

  override fun deserialize(decoder: Decoder): UUID = UUID.fromString(decoder.decodeString())
}
