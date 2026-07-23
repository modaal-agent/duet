// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.replay

import dev.modaal.duet.kernel.Reduced
import dev.modaal.duet.kernel.serialization.CanonicalJson
import dev.modaal.duet.kernel.serialization.CanonicalSerializers
import dev.modaal.duet.kernel.serialization.effectToJson
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.JsonArray

/**
 * The KMP flavor's replay adapter — the ONLY per-flavor piece the replay protocol
 * (contracts/replay-protocol-v1.md) leaves in the flavor library. One typed entry
 * per feature (scaffold-emitted glue, one line each, next to the app's feature
 * declarations); each step is stateless: decode state + action, run the pure
 * reducer, return canonical strings. The CLI owns everything else (driving,
 * diffing, writing, reporting). Swift-flavor mirror: DuetReplay/ReplayFeature.swift.
 *
 * An app declares its registry in its own commonMain:
 *
 *     val appReplayRegistry = ReplayRegistry(listOf(
 *       ReplayFeature.entry("counter", CounterState.serializer(),
 *         CounterActionSerializer, CounterEffectPayloadSerializer, ::counterReducer),
 *       …
 *     ))
 */
class ReplayFeature internal constructor(
  val name: String,
  internal val step: (stateJson: String, actionJson: String) -> StepResult,
) {
  companion object {
    /**
     * The typed entry: pins a feature name to its (State, Action, Payload) serializer
     * triple and pure reducer. The S/A/P generics are captured here and never cross a
     * boundary; decoding uses the pinned canonical configuration; results are the
     * canonical compact strings the byte gate compares.
     */
    fun <S, A, P> entry(
      name: String,
      stateSerializer: KSerializer<S>,
      actionSerializer: KSerializer<A>,
      payloadSerializer: KSerializer<P>,
      reducer: (S, A) -> Reduced<S, P>,
    ): ReplayFeature {
      val json = CanonicalSerializers.json
      return ReplayFeature(name) { stateJson, actionJson ->
        val state = json.decodeFromJsonElement(stateSerializer, json.parseToJsonElement(stateJson))
        val action =
          json.decodeFromJsonElement(actionSerializer, json.parseToJsonElement(actionJson))
        val reduced = reducer(state, action)
        StepResult(
          stateCanonical =
            CanonicalJson.canonicalString(json.encodeToJsonElement(stateSerializer, reduced.state)),
          effectsCanonical =
            CanonicalJson.canonicalString(
              JsonArray(reduced.effects.map { effectToJson(it, payloadSerializer, json) })),
        )
      }
    }
  }
}

/**
 * The result of one replay step — both fields ALREADY canonical (written by
 * [CanonicalJson]). A plain data class so SKIE bridges it to a value-semantic
 * Swift struct at the XCFramework boundary.
 */
data class StepResult(val stateCanonical: String, val effectsCanonical: String)

/**
 * The app's feature table, keyed by feature name. Duplicate names are a
 * programmer error (two features cannot share a fixture namespace).
 */
class ReplayRegistry(entries: List<ReplayFeature>) {
  val features: Map<String, ReplayFeature> = entries.associateBy { it.name }

  init {
    require(features.size == entries.size) { "ReplayRegistry: duplicate feature names" }
  }
}
