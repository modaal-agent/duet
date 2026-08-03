// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import kotlinx.serialization.json.Json
import kotlinx.serialization.modules.SerializersModule
import kotlinx.serialization.modules.contextual

/**
 * The pinned canonical configuration (contracts/serialization.md §3) — shared by the
 * fixture machinery (tests), the replay adapters (boundary), and the app's
 * process-death serialization (production). One configuration, every lane: this
 * object is why "host and boundary emit identical bytes" holds by construction.
 *
 * Contextual registrations:
 *  - `kotlin.uuid.Uuid` — common ([CanonicalUuidSerializer]), all targets. The
 *    canonical UUID type for KMP-flavor feature code.
 *  - `kotlin.time.Instant` — common ([CanonicalInstantSerializer]), all targets;
 *    byte-identical to the JVM form below. The canonical date type for
 *    KMP-flavor feature code (the multiplatform Instant the platform hook's
 *    KDoc owed, discharged at 0.1.2).
 *  - platform hook ([registerPlatformContextualSerializers]): the JVM `actual`
 *    registers `java.time.Instant` (millisecond ISO-8601 UTC) and `java.util.UUID`
 *    — the types JVM-authored feature code (the pre-KMP corpus shape) already
 *    carries. The Apple `actual` is empty.
 */
object CanonicalSerializers {
  val module = SerializersModule {
    contextual(CanonicalUuidSerializer)
    contextual(CanonicalInstantSerializer)
    registerPlatformContextualSerializers()
  }

  val json = Json {
    encodeDefaults = true
    explicitNulls = false
    serializersModule = module
  }
}
