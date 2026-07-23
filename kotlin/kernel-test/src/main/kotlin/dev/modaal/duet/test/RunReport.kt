// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * One recorded failure inside a fixture/scenario run. `kind` is `state` / `effects`
 * (byte-gate divergences), `assertion` (a local then closure), or `structure`
 * (missing/stale fixture, step-count drift). `node` names the acting node in chain
 * fixtures (null for single-feature fixtures). `rendered` is the runner's own
 * human-formatted block — tools print it verbatim instead of re-implementing the
 * format (one formatter per platform, none in the CLI). Swift mirror:
 * DuetTesting/ParityRunReport.swift.
 */
data class ParityRunFailure(
  val step: Int? = null,
  val label: String? = null,
  val line: Int? = null,
  val kind: String,
  val node: String? = null,
  val path: String? = null,
  val expected: String? = null,
  val actual: String? = null,
  val action: String? = null,
  val message: String? = null,
  val rendered: String? = null,
)

/**
 * Machine-readable run reports for the `verify` CLI: each fixture run writes
 * `parity/.runs/kotlin/<fixture>.json` (pass or fail), so `verify explain` can map a
 * red lane to scenario source, step label, and first-divergence path without re-parsing
 * Gradle logs. One file per fixture — concurrency-safe without locks.
 */
object RunReport {
  private val prettyJson = Json { prettyPrint = true }

  /** Best-effort: report writing must never fail the test run itself. */
  fun write(
    fixture: String,
    feature: String?,
    platform: String = "kotlin",
    status: String,
    steps: Int?,
    scenarioSource: String?,
    failures: List<ParityRunFailure>,
  ) {
    runCatching {
      val directory = File(FixtureRunner.fixturesDirectory().parentFile, ".runs/$platform")
      directory.mkdirs()
      val document = buildJsonObject {
        put("fixture", fixture)
        put("platform", platform)
        put("status", status)
        feature?.let { put("feature", it) }
        steps?.let { put("steps", it) }
        scenarioSource?.let { put("scenarioSource", it) }
        put(
          "failures",
          JsonArray(
            failures.map { failure ->
              buildJsonObject {
                put("kind", failure.kind)
                failure.node?.let { put("node", it) }
                failure.step?.let { put("step", it) }
                failure.label?.let { put("label", it) }
                failure.line?.let { put("line", it) }
                failure.path?.let { put("path", it) }
                failure.expected?.let { put("expected", it) }
                failure.actual?.let { put("actual", it) }
                failure.action?.let { put("action", it) }
                failure.message?.let { put("message", it) }
                failure.rendered?.let { put("rendered", it) }
              }
            }))
      }
      File(directory, "$fixture.json")
        .writeText(prettyJson.encodeToString(JsonObject.serializer(), document))
    }
      .onFailure { System.err.println("RunReport: could not write report for '$fixture': $it") }
  }
}
