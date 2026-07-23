// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import kotlin.uuid.Uuid
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * Canonical UUID form (contracts/serialization.md §2): lowercase 8-4-4-4-12, built on
 * `kotlin.uuid.Uuid` so it is COMMON — registered once in [CanonicalSerializers.module]
 * for all targets, which is what lets UUID-carrying types cross the Apple boundary.
 *
 * Byte-identity: `Uuid.toString()` is lowercase 8-4-4-4-12, identical to
 * `java.util.UUID.toString()` and consistent with the [CanonicalJson] writer's
 * uuid-lowercasing rule. Decoding uses `Uuid.parse`, which — like
 * `java.util.UUID.fromString` / Swift's `UUID(uuidString:)` — accepts either case;
 * callers that must reject lax shapes keep their own strict pre-parse guard.
 */
object CanonicalUuidSerializer : KSerializer<Uuid> {
  override val descriptor: SerialDescriptor =
    PrimitiveSerialDescriptor("dev.modaal.duet.kernel.serialization.Uuid", PrimitiveKind.STRING)

  override fun serialize(encoder: Encoder, value: Uuid) {
    encoder.encodeString(value.toString())
  }

  override fun deserialize(decoder: Decoder): Uuid = Uuid.parse(decoder.decodeString())
}
