// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.serialization.CanonicalJson
import dev.modaal.duet.kernel.serialization.effectToJson
import dev.modaal.duet.kernel.Reduced
import java.io.File
import kotlin.test.fail
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Replays a chain fixture (the cross-node SEAM dialect — S4-Q2, dialect 2 since FT
 * round 2): each step names a node, an action, and the expected effects; `linkToNext:
 * true` asserts the step's final `notifyListener` payload is byte-identical to the
 * value embedded in the next step's action — the shell-forwarding invariant, as data.
 * Chains record no state (leaf fixtures own state evolution).
 *
 * Authoring lives in the chain scenario DSL (`ChainScenario` on either flavor — hops
 * carry the typed delegate→parent-action mapping); this runner is the fixture-path
 * replay half: dialect-2 metadata (labels, lines, scenario source) lands in failures,
 * divergences carry the first divergent JSON path (FixtureDiff), every run writes a
 * machine report (RunReport), and the replay stops at the first divergence. Kotlin
 * authoring twin: ChainScenario.kt; Swift: DuetTesting/ChainScenario.swift.
 */
object ChainRunner {
  /** A typed node adapter: closes over the node's state and exposes decode→reduce→canonical-effects. */
  class Node internal constructor(
    internal val initialize: (kotlinx.serialization.json.JsonElement) -> Unit,
    internal val reduce: (kotlinx.serialization.json.JsonElement) -> String,
  )

  /** Adapts a typed (state, reducer) pair to the JSON-level chain runner. */
  fun <S, A, P> node(
    initialState: S,
    stateSerializer: KSerializer<S>,
    actionSerializer: KSerializer<A>,
    payloadSerializer: KSerializer<P>,
    reducer: (S, A) -> Reduced<S, P>,
    json: Json = FixtureRunner.json,
  ): Node {
    var state = initialState
    return Node(
      initialize = { element -> state = json.decodeFromJsonElement(stateSerializer, element) },
      reduce = { element ->
        val action = json.decodeFromJsonElement(actionSerializer, element)
        val reduced = reducer(state, action)
        state = reduced.state
        CanonicalJson.canonicalString(
          JsonArray(reduced.effects.map { effectToJson(it, payloadSerializer, json) }))
      })
  }

  fun run(fixture: String, nodes: Map<String, Node>) {
    val file = File(FixtureRunner.fixturesDirectory(), "$fixture.fixture.json")
    require(file.isFile) { "Chain fixture not found: ${file.path}" }
    val root = FixtureRunner.json.parseToJsonElement(file.readText()).jsonObject
    val steps = requireNotNull(root["steps"]) { "chain fixture root/steps" }.jsonArray
    val scenarioSource =
      root["scenario"]?.jsonObject?.get("source")?.jsonPrimitive?.contentOrNull

    fun reportAndFail(failure: ParityRunFailure): Nothing {
      val stamped =
        failure.copy(rendered = FixtureRunner.format(failure, fixture, scenarioSource))
      RunReport.write(
        fixture = fixture, feature = null, status = "failed",
        steps = steps.size, scenarioSource = scenarioSource, failures = listOf(stamped))
      fail(stamped.rendered!!)
    }

    (root["initialStates"] as? JsonObject)?.forEach { (nodeName, rawState) ->
      val node =
        requireNotNull(nodes[nodeName]) { "initialStates: unknown node '$nodeName'" }
      node.initialize(rawState)
    }

    var pendingLink: String? = null
    steps.forEachIndexed { index, stepElement ->
      val step = stepElement.jsonObject
      val nodeName = requireNotNull(step["node"]) { "chain step $index" }.jsonPrimitive.content
      val label = step["label"]?.jsonPrimitive?.contentOrNull
      val line = step["line"]?.jsonPrimitive?.intOrNull
      val rawAction = requireNotNull(step["action"]) { "chain step $index" }
      val rawExpectedEffects = requireNotNull(step["expectedEffects"]) { "chain step $index" }
      val node =
        nodes[nodeName]
          ?: reportAndFail(
            ParityRunFailure(
              step = index, label = label, line = line, kind = "structure", node = nodeName,
              message = "the test registered no node '$nodeName'"))

      // The seam invariant: the previous node's delegate payload IS this action's
      // embedded value. Effects byte-gates fire first (stop-at-first), so reaching a
      // broken link means the fixture itself is inconsistent (hand-edit — R10).
      pendingLink?.let { expectedValue ->
        val embedded =
          (rawAction as? JsonObject)?.get("value")
            ?: reportAndFail(
              ParityRunFailure(
                step = index, label = label, line = line, kind = "structure", node = nodeName,
                message = "linkToNext requires an embedded action value — regenerate: verify record"))
        if (CanonicalJson.canonicalString(embedded) != expectedValue) {
          reportAndFail(
            ParityRunFailure(
              step = index, label = label, line = line, kind = "structure", node = nodeName,
              message =
                "action value ≠ previous delegate payload (hand-edited fixture? R10) " +
                  "— regenerate: verify record"))
        }
        pendingLink = null
      }

      val actualEffects = node.reduce(rawAction)
      val expectedEffects = CanonicalJson.canonicalString(rawExpectedEffects)
      if (actualEffects != expectedEffects) {
        val divergence =
          FixtureDiff.firstDivergence(
            rawExpectedEffects, FixtureRunner.json.parseToJsonElement(actualEffects))
        // Stop at the first divergence: post-divergence steps replay against poisoned
        // state and only produce cascade noise.
        reportAndFail(
          ParityRunFailure(
            step = index, label = label, line = line, kind = "effects", node = nodeName,
            path = divergence?.path, expected = divergence?.expected,
            actual = divergence?.actual,
            action = CanonicalJson.canonicalString(rawAction)))
      }

      if ((step["linkToNext"] as? JsonPrimitive)?.booleanOrNull == true) {
        pendingLink =
          lastNotifyListenerPayload(actualEffects)
            ?: reportAndFail(
              ParityRunFailure(
                step = index, label = label, line = line, kind = "structure", node = nodeName,
                message = "linkToNext but no notifyListener effect — regenerate: verify record"))
      }
    }
    require(pendingLink == null) { "trailing linkToNext with no following step" }

    RunReport.write(
      fixture = fixture, feature = null, status = "passed",
      steps = steps.size, scenarioSource = scenarioSource, failures = emptyList())
  }

  private fun lastNotifyListenerPayload(effectsCanonical: String): String? {
    val effects =
      FixtureRunner.json.parseToJsonElement(effectsCanonical) as? JsonArray ?: return null
    for (effect in effects.reversed()) {
      val payload = (effect as? JsonObject)?.get("payload") as? JsonObject ?: continue
      if ((payload["case"] as? JsonPrimitive)?.content != "notifyListener") continue
      val value = payload["value"] ?: continue
      return CanonicalJson.canonicalString(value)
    }
    return null
  }
}
