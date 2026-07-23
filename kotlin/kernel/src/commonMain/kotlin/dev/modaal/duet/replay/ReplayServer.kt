// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.replay

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * The replay-protocol server — a JSON-lines stdio loop over an app's adapter
 * registry. Protocol v1, the versioned flavor seam — normative contract:
 * contracts/replay-protocol-v1.md. Swift-flavor mirror: DuetReplay/ReplayServer.swift.
 *
 * An app's replay-runner `main` (JVM host lane) is three lines:
 *
 *     fun main() {
 *       ReplayServer.serve(appReplayRegistry)
 *     }
 */
object ReplayServer {
  const val PROTOCOL_NAME = "duet-replay"
  const val PROTOCOL_VERSION = 1
  const val PLATFORM = "kotlin"

  private val json = Json

  /** The handshake object emitted on start. */
  fun handshake(registry: ReplayRegistry): JsonObject = buildJsonObject {
    put("features", JsonArray(registry.features.keys.sorted().map { JsonPrimitive(it) }))
    put("platform", PLATFORM)
    put("protocol", PROTOCOL_NAME)
    put("version", PROTOCOL_VERSION)
  }

  /**
   * One request line → one response object; null means `exit` was requested.
   * Pure request handling, split from the stdio loop so it can be receipted
   * without a subprocess.
   */
  fun respond(line: String, registry: ReplayRegistry): JsonObject? {
    val request =
      try {
        json.parseToJsonElement(line).jsonObject
      } catch (_: Exception) {
        return errorObject("malformed request line")
      }
    return when (val op = (request["op"] as? JsonPrimitive)?.content) {
      "exit" -> null
      "reduce" -> {
        val feature = (request["feature"] as? JsonPrimitive)?.content
        val stateTree = request["state"]
        val actionTree = request["action"]
        if (feature == null || stateTree == null || actionTree == null) {
          return errorObject("reduce needs feature/state/action")
        }
        val replay =
          registry.features[feature] ?: return errorObject("unknown feature '$feature'")
        try {
          val result = replay.step(stateTree.toString(), actionTree.toString())
          buildJsonObject {
            put("effects", result.effectsCanonical)
            put("state", result.stateCanonical)
          }
        } catch (e: Exception) {
          errorObject(e.toString())
        }
      }
      else -> errorObject("unknown op '$op'")
    }
  }

  /**
   * The blocking stdio loop: handshake, then one response per request line
   * until `exit` or EOF. Nothing else may reach stdout (contract §1) —
   * diagnostics belong on stderr.
   */
  fun serve(registry: ReplayRegistry) {
    println(json.encodeToString(JsonObject.serializer(), handshake(registry)))
    while (true) {
      val line = readlnOrNull() ?: return
      if (line.isEmpty()) continue
      val response = respond(line, registry) ?: return
      println(json.encodeToString(JsonObject.serializer(), response))
    }
  }

  private fun errorObject(message: String): JsonObject = buildJsonObject {
    put("error", message)
  }
}
