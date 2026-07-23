// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.serialization.CanonicalJson
import dev.modaal.duet.kernel.serialization.effectToJson
import dev.modaal.duet.kernel.Effect
import dev.modaal.duet.kernel.Reduced
import java.io.File
import kotlin.test.fail
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * Executes a [Scenario] in one of two modes (FT2). Swift mirror:
 * DuetTesting/ScenarioRunner.swift.
 *
 * - **record** (`REGEN_FIXTURES=1` or `-Dduet.regenFixtures=1`): drives the pure
 *   reducer through every *variant* of the scenario (a linear scenario is one variant;
 *   `branch`es fork into one variant per root→leaf path), runs every local `then`, and
 *   compiles one dialect-2 fixture per variant into `parity/fixtures/`. Fixtures are
 *   build products — never hand-edited (R10); the scenario runners are the only
 *   writers, and both platforms' §6 pretty writers emit byte-identical files.
 * - **verify**: drives the reducer through every variant AND byte-gates each step
 *   against the committed fixture. A step's trailing local `then`s run BEFORE its
 *   byte gate: a failing then states the author's *intent* and wins the header, with
 *   the byte divergence riding along as detail. Scenario-vs-fixture drift (edited
 *   scenario, stale fixture) is reported as `structure` with a regen hint instead of
 *   a fake divergence.
 */
object ScenarioRunner {
  /**
   * True when the caller should regenerate committed fixtures
   * (`REGEN_FIXTURES=1 ./gradlew test`, `-Dduet.regenFixtures=1`, or
   * `verify record`). Mirrors FixtureRecorder.regenerationRequested on iOS.
   */
  val regenerationRequested: Boolean
    get() =
      System.getProperty("duet.regenFixtures") == "1" ||
        System.getenv("REGEN_FIXTURES") == "1"

  fun <S, A, P> verifyOrRecord(
    scenario: Scenario<S, A, P>,
    stateSerializer: KSerializer<S>,
    actionSerializer: KSerializer<A>,
    payloadSerializer: KSerializer<P>,
    reducer: (S, A) -> Reduced<S, P>,
  ) {
    if (regenerationRequested) {
      record(scenario, stateSerializer, actionSerializer, payloadSerializer, reducer)
    }
    verify(scenario, stateSerializer, actionSerializer, payloadSerializer, reducer)
  }

  fun <S, A, P> record(
    scenario: Scenario<S, A, P>,
    stateSerializer: KSerializer<S>,
    actionSerializer: KSerializer<A>,
    payloadSerializer: KSerializer<P>,
    reducer: (S, A) -> Reduced<S, P>,
  ) {
    val json = FixtureRunner.json
    val source =
      scenario.source
        ?: error("record mode needs an explicit source path (no #filePath on the JVM)")
    val variants = Variants(scenario)
    for (variant in variants.all) {
      val steps = mutableListOf<JsonObject>()
      variants.walk(
        variant,
        reducer = reducer,
        onStep = { step, state, effects ->
          steps.add(
            buildJsonObject {
              put("label", step.label)
              put("line", step.line)
              put("action", json.encodeToJsonElement(actionSerializer, step.action))
              put("expectedState", json.encodeToJsonElement(stateSerializer, state))
              put(
                "expectedEffects",
                JsonArray(effects.map { effectToJson(it, payloadSerializer, json) }))
            })
        },
        onFailedAssertion = { failure, _, _, _ ->
          // A false then during record is an authoring error — nothing is written
          // (fail throws before this variant reaches its writeText).
          fail(FixtureRunner.format(failure, variant.fixture, source))
        })

      val document = buildJsonObject {
        put("dialect", 2)
        put("feature", scenario.feature)
        put("description", scenario.description)
        put(
          "scenario",
          buildJsonObject {
            put("source", source)
            if (variant.slugs.isNotEmpty()) put("branch", variant.slugs.joinToString("."))
          })
        put("initialState", json.encodeToJsonElement(stateSerializer, variants.initialState()))
        put("steps", JsonArray(steps))
      }
      val file = File(FixtureRunner.fixturesDirectory(), "${variant.fixture}.fixture.json")
      // §6 pretty form — byte-identical to the Swift record mode's writer.
      file.writeText(CanonicalJson.prettyCanonicalString(document))
      println("ScenarioRunner: recorded ${variant.fixture}.fixture.json (${steps.size} steps)")
    }
  }

  fun <S, A, P> verify(
    scenario: Scenario<S, A, P>,
    stateSerializer: KSerializer<S>,
    actionSerializer: KSerializer<A>,
    payloadSerializer: KSerializer<P>,
    reducer: (S, A) -> Reduced<S, P>,
  ) {
    val variants = Variants(scenario)
    // kotlin.test.fail throws, so the first failing variant ends the test — Swift's
    // XCTFail continues through the remaining variants (a documented asymmetry).
    for (variant in variants.all) {
      verifyVariant(
        variant, variants, scenario, stateSerializer, actionSerializer, payloadSerializer,
        reducer)
    }
  }

  private fun <S, A, P> verifyVariant(
    variant: Variant<S, A, P>,
    variants: Variants<S, A, P>,
    scenario: Scenario<S, A, P>,
    stateSerializer: KSerializer<S>,
    actionSerializer: KSerializer<A>,
    payloadSerializer: KSerializer<P>,
    reducer: (S, A) -> Reduced<S, P>,
  ) {
    val json = FixtureRunner.json
    val fixture = variant.fixture

    fun reportAndFail(rawFailure: ParityRunFailure, steps: Int?): Nothing {
      val failure =
        rawFailure.copy(
          rendered = FixtureRunner.format(rawFailure, fixture, scenario.source))
      RunReport.write(
        fixture = fixture, feature = scenario.feature, status = "failed",
        steps = steps, scenarioSource = scenario.source, failures = listOf(failure))
      fail(failure.rendered ?: failure.kind)
    }

    val file = File(FixtureRunner.fixturesDirectory(), "$fixture.fixture.json")
    val root =
      runCatching {
        require(file.isFile) { "Fixture not found: ${file.path}" }
        json.parseToJsonElement(file.readText()).jsonObject
      }
        .getOrElse { error ->
          reportAndFail(
            ParityRunFailure(
              kind = "structure",
              message = "fixture missing or unreadable ($error) — record it: " +
                "verify record --feature ${scenario.feature}"),
            steps = null)
        }
    val dialect = root["dialect"]?.jsonPrimitive?.intOrNull ?: 1
    if (dialect < 2) {
      reportAndFail(
        ParityRunFailure(
          kind = "structure",
          message = "fixture is dialect $dialect (pre-scenario) — regenerate: " +
            "verify record --feature ${scenario.feature}"),
        steps = null)
    }
    val rawInitialState = requireNotNull(root["initialState"]) { "missing initialState" }
    val steps = requireNotNull(root["steps"]) { "missing steps" }.jsonArray

    val actualInitial =
      CanonicalJson.canonicalString(
        json.encodeToJsonElement(stateSerializer, variants.initialState()))
    if (actualInitial != CanonicalJson.canonicalString(rawInitialState)) {
      reportAndFail(
        ParityRunFailure(
          kind = "structure",
          message = "scenario given() drifted from recorded initialState — regenerate: " +
            "verify record --feature ${scenario.feature}"),
        steps = null)
    }
    val whenCount = variants.whenCount(variant)
    if (whenCount != steps.size) {
      reportAndFail(
        ParityRunFailure(
          kind = "structure",
          message = "scenario has $whenCount whenAction step(s) but fixture has " +
            "${steps.size} — regenerate: verify record --feature ${scenario.feature}"),
        steps = null)
    }

    variants.walk(
      variant,
      reducer = reducer,
      onStep = { step, state, effects ->
        val rawStep = steps[step.index].jsonObject
        val rawAction = rawStep["action"]
        val rawExpectedState = rawStep["expectedState"]
        val rawExpectedEffects = rawStep["expectedEffects"]
        if (rawAction == null || rawExpectedState == null || rawExpectedEffects == null) {
          reportAndFail(
            ParityRunFailure(
              step = step.index, label = step.label, line = step.line, kind = "structure",
              message = "fixture step ${step.index} is malformed — regenerate"),
            steps = steps.size)
        }
        // Drift gate: the fixture step must have been compiled from THIS action.
        val scenarioAction =
          CanonicalJson.canonicalString(json.encodeToJsonElement(actionSerializer, step.action))
        val fixtureAction = CanonicalJson.canonicalString(rawAction)
        if (scenarioAction != fixtureAction) {
          reportAndFail(
            ParityRunFailure(
              step = step.index, label = step.label, line = step.line, kind = "structure",
              action = scenarioAction,
              message = "scenario action drifted from fixture (recorded: $fixtureAction) — " +
                "regenerate: verify record --feature ${scenario.feature}"),
            steps = steps.size)
        }
        val failure =
          FixtureRunner.stepDivergence(
            stepIndex = step.index, label = step.label, line = step.line,
            rawExpectedState = rawExpectedState, rawExpectedEffects = rawExpectedEffects,
            actualState = json.encodeToJsonElement(stateSerializer, state),
            actualEffects = JsonArray(effects.map { effectToJson(it, payloadSerializer, json) }),
            actionCanonical = scenarioAction)
        if (failure != null) reportAndFail(failure, steps = steps.size)
      },
      onFailedAssertion = { failure, pending, state, effects ->
        // The then's intent-framed failure wins the header; if the step's byte gate
        // (still pending — thens run first) also diverges, the path and fragments
        // ride along as detail.
        var enriched = failure
        if (pending != null && pending.index < steps.size) {
          val rawStep = steps[pending.index].jsonObject
          val rawExpectedState = rawStep["expectedState"]
          val rawExpectedEffects = rawStep["expectedEffects"]
          val divergence =
            if (rawExpectedState != null && rawExpectedEffects != null) {
              runCatching {
                FixtureRunner.stepDivergence(
                  stepIndex = pending.index, label = pending.label, line = pending.line,
                  rawExpectedState = rawExpectedState,
                  rawExpectedEffects = rawExpectedEffects,
                  actualState = json.encodeToJsonElement(stateSerializer, state),
                  actualEffects =
                    JsonArray(effects.map { effectToJson(it, payloadSerializer, json) }),
                  actionCanonical = runCatching {
                    CanonicalJson.canonicalString(
                      json.encodeToJsonElement(actionSerializer, pending.action))
                  }.getOrDefault(""))
              }.getOrNull()
            } else {
              null
            }
          val divergencePath = divergence?.path
          if (divergence != null && divergencePath != null) {
            val root = if (divergence.kind == "effects") "expectedEffects" else "expectedState"
            val joiner = if (divergencePath.startsWith("[")) "" else "."
            enriched = enriched.copy(
              path = "$root$joiner$divergencePath",
              expected = divergence.expected,
              actual = divergence.actual,
              message = (enriched.message ?: "") +
                " — the step's ${divergence.kind} also diverged from the fixture")
          }
        }
        reportAndFail(enriched, steps = steps.size)
      })

    RunReport.write(
      fixture = fixture, feature = scenario.feature, status = "passed",
      steps = steps.size, scenarioSource = scenario.source, failures = emptyList())
  }

  // Variants (branch expansion + the walk) — mirror of Swift ScenarioRunner.Variants.

  private class FlatWhen<A>(
    val index: Int,
    val label: String,
    val line: Int,
    val action: A,
  )

  private class Variant<S, A, P>(
    val slugs: List<String>,
    val fixture: String,
    val nodes: List<ScenarioNode<S, A, P>>,
  )

  /**
   * The scenario's branch tree expanded into linear variants: one per root→leaf path
   * (exactly one, unsuffixed, when the scenario has no `branch`). Each variant's node
   * list is fully linear — branch content is re-wrapped as a `context` so labels and
   * the walk need no branch awareness downstream.
   */
  private class Variants<S, A, P>(private val scenario: Scenario<S, A, P>) {
    val all: List<Variant<S, A, P>>

    init {
      check(scenario.nodes.firstOrNull() is ScenarioNode.Given<*, *, *>) {
        "scenario '${scenario.fixture}' must start with given(initialState)"
      }
      all =
        expand(scenario.nodes).map { (slugs, nodes) ->
          Variant(
            slugs = slugs,
            fixture =
              if (slugs.isEmpty()) scenario.fixture
              else "${scenario.fixture}.${slugs.joinToString(".")}",
            nodes = nodes)
        }
      val names = all.map { it.fixture }
      check(names.toSet().size == names.size) {
        "branch labels collide after slugification: ${names.sorted()}"
      }
    }

    fun initialState(): S {
      @Suppress("UNCHECKED_CAST")
      val given =
        scenario.nodes.firstOrNull() as? ScenarioNode.Given<S, A, P> ?: error("missing given()")
      return given.state
    }

    fun whenCount(variant: Variant<S, A, P>): Int {
      fun count(nodes: List<ScenarioNode<S, A, P>>): Int =
        nodes.fold(0) { total, node ->
          total +
            when (node) {
              is ScenarioNode.When -> 1
              is ScenarioNode.Context -> count(node.nodes)
              else -> 0
            }
        }
      return count(variant.nodes)
    }

    /**
     * Splits a node list at its first `branch`: everything before is the shared prefix;
     * everything after must also be a `branch` (branches are alternate ENDINGS — R11
     * stays intact because the structure is static: every branch always runs, no
     * runtime value chooses). A `context` whose children fork must be the last node at
     * its level, and its variants bubble up.
     */
    private fun expand(
      nodes: List<ScenarioNode<S, A, P>>,
    ): List<Pair<List<String>, List<ScenarioNode<S, A, P>>>> {
      nodes.forEachIndexed { index, node ->
        when (node) {
          is ScenarioNode.Branch -> {
            val branches =
              nodes.drop(index).map { sibling ->
                check(sibling is ScenarioNode.Branch) {
                  "only branch nodes may follow a branch at the same level " +
                    "(branches are alternate endings; line ${node.line})"
                }
                sibling
              }
            val slugs = branches.map { slugify(it.label) }
            check(slugs.toSet().size == slugs.size) {
              "sibling branch labels collide: ${slugs.sorted()}"
            }
            val prefix = nodes.take(index)
            val variants = mutableListOf<Pair<List<String>, List<ScenarioNode<S, A, P>>>>()
            for ((branch, slug) in branches.zip(slugs)) {
              for ((subSlugs, subNodes) in expand(branch.nodes)) {
                variants.add(
                  Pair(
                    listOf(slug) + subSlugs,
                    prefix + ScenarioNode.Context(branch.label, subNodes)))
              }
            }
            return variants
          }
          is ScenarioNode.Context -> {
            val subs = expand(node.nodes)
            // Plain linear context — nothing forks below it.
            if (subs.size == 1 && subs[0].first.isEmpty()) return@forEachIndexed
            check(index == nodes.size - 1) {
              "a context containing branches must be the last node at its level ('${node.label}')"
            }
            val prefix = nodes.take(index)
            return subs.map { (subSlugs, subNodes) ->
              Pair(subSlugs, prefix + ScenarioNode.Context(node.label, subNodes))
            }
          }
          else -> {}
        }
      }
      return listOf(Pair(emptyList(), nodes))
    }

    /**
     * Branch label → fixture-name slug: lowercased, ASCII-alphanumeric runs kept,
     * everything else collapses to a single `-`. Slugs must be non-empty and unique
     * among siblings.
     */
    private fun slugify(label: String): String {
      val out = StringBuilder()
      var pendingDash = false
      for (ch in label.lowercase()) {
        if (ch in 'a'..'z' || ch in '0'..'9') {
          if (pendingDash && out.isNotEmpty()) out.append('-')
          pendingDash = false
          out.append(ch)
        } else {
          pendingDash = true
        }
      }
      check(out.isNotEmpty()) { "branch label '$label' slugifies to nothing" }
      return out.toString()
    }

    /**
     * Depth-first walk of one variant: reduces on every `whenAction`, runs
     * then/thenEffects as they appear, and fires [onStep] (the byte gate / record sink)
     * for a step only after its trailing thens — i.e. just before the next
     * `whenAction`, and at walk end. [onFailedAssertion] receives the still-pending
     * step so the caller can attach byte-gate detail to an intent-framed then failure.
     * Callbacks end the walk by throwing (kotlin.test.fail) — no StopWalk mirror
     * needed on the JVM.
     */
    fun walk(
      variant: Variant<S, A, P>,
      reducer: (S, A) -> Reduced<S, P>,
      onStep: (FlatWhen<A>, S, List<Effect<P>>) -> Unit,
      onFailedAssertion: (ParityRunFailure, FlatWhen<A>?, S, List<Effect<P>>) -> Unit,
    ) {
      var state = initialState()
      var lastEffects: List<Effect<P>> = emptyList()
      var stepIndex = 0
      val contextPath = mutableListOf<String>()
      var pending: FlatWhen<A>? = null

      fun flushPendingGate() {
        val step = pending
        if (step != null) {
          pending = null
          onStep(step, state, lastEffects)
        }
      }

      fun visit(nodes: List<ScenarioNode<S, A, P>>, isRoot: Boolean) {
        nodes.forEachIndexed { offset, node ->
          when (node) {
            is ScenarioNode.Given -> {
              check(isRoot && offset == 0) { "given() must be the first node (and only there)" }
            }
            is ScenarioNode.When -> {
              flushPendingGate()
              val joined = (contextPath + node.label).joinToString(" › ")
              val reduced = reducer(state, node.action)
              state = reduced.state
              lastEffects = reduced.effects
              pending = FlatWhen(stepIndex, joined, node.line, node.action)
              stepIndex += 1
            }
            is ScenarioNode.Then -> {
              if (!node.assert(state)) {
                onFailedAssertion(
                  ParityRunFailure(
                    step = if (stepIndex > 0) stepIndex - 1 else null,
                    label = (contextPath + node.label).joinToString(" › "),
                    line = node.line, kind = "assertion",
                    message = "Then returned false against the current state"),
                  pending, state, lastEffects)
              }
            }
            is ScenarioNode.ThenEffects -> {
              if (!node.assert(lastEffects)) {
                onFailedAssertion(
                  ParityRunFailure(
                    step = if (stepIndex > 0) stepIndex - 1 else null,
                    label = (contextPath + node.label).joinToString(" › "),
                    line = node.line, kind = "assertion",
                    message = "ThenEffects returned false against the last emitted effects"),
                  pending, state, lastEffects)
              }
            }
            is ScenarioNode.Context -> {
              contextPath.add(node.label)
              visit(node.nodes, isRoot = false)
              contextPath.removeAt(contextPath.size - 1)
            }
            is ScenarioNode.Branch ->
              error("walk over an unexpanded branch — variant expansion must run first")
          }
        }
      }

      visit(variant.nodes, isRoot = true)
      flushPendingGate()
    }
  }
}
