// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.serialization.CanonicalJson
import dev.modaal.duet.kernel.serialization.effectToJson
import dev.modaal.duet.kernel.Reduced
import java.io.File
import kotlin.test.fail
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Replays a shared golden fixture (`parity/fixtures/<name>.fixture.json`) against the
 * **pure reducer only** — no runtime, no handlers, no dispatchers. Runner semantics:
 * contracts/serialization.md §5. Swift mirror: DuetTesting/FixtureRunner.swift.
 *
 * Dialect 2 (FT1): fixtures may carry `scenario.source`, per-step `label`/`line`, and
 * `dialect: 2`. All of it is *metadata* — the byte gate still compares only
 * `action`/`expectedState`/`expectedEffects`. On divergence the runner reports the
 * first divergent JSON path (FixtureDiff), the step label, and the scenario source
 * line, and writes a machine-readable report (RunReport) for `verify explain`.
 */
object FixtureRunner {
  // The pinned canonical config (serialization.md §3): encodeDefaults because kotlinx
  // otherwise omits default-valued fields (the counter golden caught that divergence on
  // first run); explicitNulls=false to match Swift's omit-nil rule; the contextual
  // Instant serializer gives java.time.Instant the canonical millisecond form.
  val json = dev.modaal.duet.kernel.serialization.CanonicalSerializers.json

  /**
   * Resolves `parity/fixtures` by walking up from the test JVM's working directory (the
   * Gradle module dir) — both platforms read the same files, so drift is structurally
   * impossible.
   */
  fun fixturesDirectory(): File {
    var dir: File? = File(System.getProperty("user.dir")).absoluteFile
    while (dir != null) {
      val candidate = File(dir, "parity/fixtures")
      if (candidate.isDirectory) return candidate
      dir = dir.parentFile
    }
    error("Could not locate parity/fixtures walking up from ${System.getProperty("user.dir")}")
  }

  /**
   * Byte-gate for one step: canonical-compares recorded vs actual state and effects; on
   * mismatch returns a failure carrying the first divergent JSON path.
   */
  fun stepDivergence(
    stepIndex: Int,
    label: String?,
    line: Int?,
    rawExpectedState: JsonElement,
    rawExpectedEffects: JsonElement,
    actualState: JsonElement,
    actualEffects: JsonElement,
    actionCanonical: String,
  ): ParityRunFailure? {
    if (CanonicalJson.canonicalString(rawExpectedState) !=
      CanonicalJson.canonicalString(actualState)
    ) {
      val divergence = FixtureDiff.firstDivergence(rawExpectedState, actualState)
      return ParityRunFailure(
        step = stepIndex, label = label, line = line, kind = "state",
        path = divergence?.path, expected = divergence?.expected, actual = divergence?.actual,
        action = actionCanonical)
    }
    if (CanonicalJson.canonicalString(rawExpectedEffects) !=
      CanonicalJson.canonicalString(actualEffects)
    ) {
      val divergence = FixtureDiff.firstDivergence(rawExpectedEffects, actualEffects)
      return ParityRunFailure(
        step = stepIndex, label = label, line = line, kind = "effects",
        path = divergence?.path, expected = divergence?.expected, actual = divergence?.actual,
        action = actionCanonical)
    }
    return null
  }

  /**
   * The shared human failure block — ONE formatter per platform (the runner's own),
   * none in the tools: the rendered text is embedded in the run report (`rendered`) and
   * `verify`/`verify explain` print it verbatim. Shape pinned cross-platform by the
   * formatter golden (parity/fixtures/formatter.golden.txt).
   */
  fun format(
    failure: ParityRunFailure,
    fixture: String,
    scenarioSource: String?,
    platform: String = "kotlin",
  ): String {
    val lines = mutableListOf<String>()
    val subject = if (failure.node == null) "fixture" else "chain"
    val node = failure.node?.let { " ($it)" } ?: ""
    val label = failure.label?.let { " '$it'" } ?: ""
    val step = failure.step?.let { " step $it" } ?: ""
    val verdict = if (failure.kind == "assertion") "Then failed" else "${failure.kind} diverged"
    lines.add("✗ $subject '$fixture'$step$node$label — $verdict")
    failure.path?.let {
      val joiner = if (it.startsWith("[")) "" else "."
      when (failure.kind) {
        "effects" -> lines.add("  at expectedEffects$joiner$it")
        "state" -> lines.add("  at expectedState$joiner$it")
        else -> lines.add("  at $it") // pre-rooted (assertion enrichment)
      }
    }
    if (failure.expected != null || failure.actual != null) {
      lines.add("  expected: ${failure.expected ?: "∅"}   actual: ${failure.actual ?: "∅"}")
    }
    failure.action?.let { lines.add("  action: $it") }
    scenarioSource?.let {
      val line = failure.line?.let { l -> ":$l" } ?: ""
      lines.add("  scenario: $it$line")
    }
    failure.message?.let { lines.add("  $it") }
    val divergent = failure.kind == "state" || failure.kind == "effects" ||
      (failure.kind == "assertion" && failure.path != null)
    if (failure.step != null && divergent) {
      lines.add("  next: verify materialize $fixture#${failure.step} --platform $platform")
    }
    return lines.joinToString("\n")
  }

  fun <S, A, P> run(
    fixture: String,
    stateSerializer: KSerializer<S>,
    actionSerializer: KSerializer<A>,
    payloadSerializer: KSerializer<P>,
    reducer: (S, A) -> Reduced<S, P>,
  ) {
    val file = File(fixturesDirectory(), "$fixture.fixture.json")
    require(file.isFile) { "Fixture not found: ${file.path}" }
    val root = json.parseToJsonElement(file.readText()).jsonObject
    val feature = root["feature"]?.jsonPrimitive?.contentOrNull
    val scenarioSource =
      root["scenario"]?.jsonObject?.get("source")?.jsonPrimitive?.contentOrNull
    val rawInitialState = requireNotNull(root["initialState"]) { "missing initialState" }
    val steps = requireNotNull(root["steps"]) { "missing steps" }.jsonArray

    var state = json.decodeFromJsonElement(stateSerializer, rawInitialState)

    steps.forEachIndexed { index, stepElement ->
      val step = stepElement.jsonObject
      val rawAction = requireNotNull(step["action"]) { "step $index missing action" }
      val rawExpectedState =
        requireNotNull(step["expectedState"]) { "step $index missing expectedState" }
      val rawExpectedEffects =
        requireNotNull(step["expectedEffects"]) { "step $index missing expectedEffects" }

      val action = json.decodeFromJsonElement(actionSerializer, rawAction)
      val reduced = reducer(state, action)
      state = reduced.state

      val failure =
        stepDivergence(
          stepIndex = index,
          label = step["label"]?.jsonPrimitive?.contentOrNull,
          line = step["line"]?.jsonPrimitive?.intOrNull,
          rawExpectedState = rawExpectedState,
          rawExpectedEffects = rawExpectedEffects,
          actualState = json.encodeToJsonElement(stateSerializer, state),
          actualEffects =
            JsonArray(reduced.effects.map { effectToJson(it, payloadSerializer, json) }),
          actionCanonical = CanonicalJson.canonicalString(rawAction))
      if (failure != null) {
        val stamped = failure.copy(rendered = format(failure, fixture, scenarioSource))
        RunReport.write(
          fixture = fixture, feature = feature, status = "failed",
          steps = steps.size, scenarioSource = scenarioSource, failures = listOf(stamped))
        // Stop at the first divergence: post-divergence steps replay against poisoned
        // state and only produce cascade noise.
        fail(stamped.rendered ?: stamped.kind)
      }
    }
    RunReport.write(
      fixture = fixture, feature = feature, status = "passed",
      steps = steps.size, scenarioSource = scenarioSource, failures = emptyList())
  }
}
