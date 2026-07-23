// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import dev.modaal.duet.kernel.Effect
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Canonical serialization shape for kernel [Effect] values (contracts/serialization.md §4):
 *   {"kind": "run", "id": <string|null>, "payload": {...}}
 *   {"kind": "cancel", "id": <string>}
 * Core-owned (not test-only): the fixture machinery, the replay adapters, and the
 * boundary all emit effect bytes through this one function.
 * Swift-flavor mirror: `Effect: Codable` in Duet/Effect.swift.
 */
fun <P> effectToJson(effect: Effect<P>, payloadSerializer: KSerializer<P>, json: Json): JsonElement =
  when (effect) {
    is Effect.Run ->
      buildJsonObject {
        put("kind", "run")
        // Omit-nil rule (serialization.md §2): anonymous runs carry no id key.
        effect.id?.let { put("id", JsonPrimitive(it)) }
        put("payload", json.encodeToJsonElement(payloadSerializer, effect.payload))
      }
    is Effect.Cancel ->
      buildJsonObject {
        put("kind", "cancel")
        put("id", effect.id)
      }
  }
