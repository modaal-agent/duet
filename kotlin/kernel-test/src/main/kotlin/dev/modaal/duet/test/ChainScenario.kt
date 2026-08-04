// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.Effect
import dev.modaal.duet.kernel.Reduced
import dev.modaal.duet.kernel.serialization.CanonicalJson
import dev.modaal.duet.kernel.serialization.effectToJson
import java.io.File
import kotlin.test.fail
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * The chain dialect, scenario-authored — Kotlin flavor. Mirrors
 * DuetTesting/ChainScenario.swift: a chain scenario pins a composition SEAM across
 * nodes: per-step `node` + `action` + `expectedEffects` (never `expectedState` — state
 * evolution belongs to the leaf fixtures), and a `hop` carrying the delegate→
 * parent-action mapping the shells implement in production. Recording marks the
 * delegate-emitting step `linkToNext: true`, so the fixture-side replay (ChainRunner)
 * can assert the forwarding invariant byte-level without any typed mapping.
 *
 * Node handles are declared NEXT TO the scenario (each chain owns its seeds):
 *
 *     val picker = ChainNode("sharepicker", SharePickerState(…),
 *       SharePickerState.serializer(), SharePickerActionSerializer,
 *       SharePickerPayloadSerializer, ::sharePickerReduce)
 *     val timeline = ChainNode("timeline", TimelineState(…), …)
 *     val shareApply = chainScenario(chain = "share-apply", description = "…",
 *       source = "src-kmp/…/ChainScenarioTest.kt") {
 *       whenAction(picker, "apply emits the applied delegate", SharePickerAction.ApplyTapped)
 *       hop("the feed-share seam", from = picker, to = timeline,
 *         delegateSerializer = SharePickerDelegate.serializer()) { d ->
 *         TimelineAction.SharePicker(d)
 *       }
 *       thenEffects(timeline, "the sheet closes into applyShareSelection") { … }
 *     }
 *
 * The Swift `Hop` closure's explicit parameter type is how the recorded delegate
 * payload gets decoded; the Kotlin dialect passes the delegate's serializer explicitly
 * (`delegateSerializer`), matching the rest of the dialect's explicit-serializer style.
 * No context/branch in chains (they are short seam pins, not narratives). Call-site
 * lines come from the stack (no `#line` on the JVM — the documented platform
 * asymmetry, metadata only), and `source` is an explicit parameter (no `#filePath`).
 */
class ChainNode<S, A, P>(
  val key: String,
  internal val initial: S,
  internal val stateSerializer: KSerializer<S>,
  internal val actionSerializer: KSerializer<A>,
  internal val payloadSerializer: KSerializer<P>,
  internal val reducer: (S, A) -> Reduced<S, P>,
)

/** One authored chain statement (type-erased — a chain spans several (S, A, P) triples). */
internal sealed interface ChainStatement {
  val label: String
  val line: Int

  class WhenStep(
    val nodeKey: String,
    override val label: String,
    override val line: Int,
    val ensure: (ChainBoxes) -> Unit,
    val actionTree: () -> JsonElement,
    val apply: (ChainBoxes) -> JsonElement,
  ) : ChainStatement

  class HopStep(
    val fromKey: String,
    val toKey: String,
    override val label: String,
    override val line: Int,
    val ensure: (ChainBoxes) -> Unit,
    val derive: (JsonElement) -> DerivedHop,
  ) : ChainStatement

  class ThenStep(
    val nodeKey: String,
    override val label: String,
    override val line: Int,
    val isEffects: Boolean,
    /** null = the node has no box yet (record errors, verify skips — Swift mirror). */
    val assert: (ChainBoxes) -> Boolean?,
  ) : ChainStatement
}

/** A hop's derived half: the mapped action's tree plus its application on the `to` node. */
internal class DerivedHop(
  val actionTree: JsonElement,
  val apply: (ChainBoxes) -> JsonElement,
)

class ChainScenario internal constructor(
  val chain: String,
  val fixture: String,
  val description: String,
  /** Repo-relative path of this authoring file (explicit — no #filePath on the JVM). */
  val source: String?,
  internal val statements: List<ChainStatement>,
)

fun chainScenario(
  chain: String,
  fixture: String = "chain-$chain",
  description: String,
  source: String? = null,
  block: ChainScenarioBuilder.() -> Unit,
): ChainScenario {
  val builder = ChainScenarioBuilder()
  builder.block()
  return ChainScenario(chain, fixture, description, source, builder.statements)
}

class ChainScenarioBuilder internal constructor() {
  internal val statements = mutableListOf<ChainStatement>()
  private val json = FixtureRunner.json

  /** A dispatched action on one node — one fixture step. (`when` is a Kotlin keyword.) */
  fun <S, A, P> whenAction(node: ChainNode<S, A, P>, label: String, action: A) {
    statements.add(
      ChainStatement.WhenStep(
        nodeKey = node.key, label = label, line = callSiteLine(),
        ensure = { it.box(node) },
        actionTree = { json.encodeToJsonElement(node.actionSerializer, action) },
        apply = { boxes -> boxes.typed(node).reduce(action) }))
  }

  /**
   * The seam statement: the PREVIOUS step's final `notifyListener` payload, decoded via
   * [delegateSerializer], mapped through the same delegate→action forwarding the
   * parent's shell performs — one fixture step on the [to] node, with the previous step
   * marked `linkToNext`. The mapping is re-derived at verify time from the actual
   * replayed payload, so an edited seam (or a drifted delegate) fails as `structure`
   * drift.
   */
  fun <FS, FA, FP, TS, TA, TP, D> hop(
    label: String,
    from: ChainNode<FS, FA, FP>,
    to: ChainNode<TS, TA, TP>,
    delegateSerializer: KSerializer<D>,
    map: (D) -> TA,
  ) {
    statements.add(
      ChainStatement.HopStep(
        fromKey = from.key, toKey = to.key, label = label, line = callSiteLine(),
        ensure = { it.box(to) },
        derive = { payload ->
          val delegate = json.decodeFromJsonElement(delegateSerializer, payload)
          val action = map(delegate)
          DerivedHop(
            actionTree = json.encodeToJsonElement(to.actionSerializer, action),
            apply = { boxes -> boxes.typed(to).reduce(action) })
        }))
  }

  /**
   * Local state assertion on one node (authoring-platform only — chains never record
   * state; this is the code-pointer assert the effects-only fixture can't carry).
   */
  fun <S, A, P> then(node: ChainNode<S, A, P>, label: String, assert: (S) -> Boolean) {
    statements.add(
      ChainStatement.ThenStep(
        nodeKey = node.key, label = label, line = callSiteLine(), isEffects = false,
        assert = { boxes -> boxes.existingTyped(node)?.let { assert(it.state) } }))
  }

  /** Local assertion on the effects the node emitted at its most recent step. */
  fun <S, A, P> thenEffects(
    node: ChainNode<S, A, P>,
    label: String,
    assert: (List<Effect<P>>) -> Boolean,
  ) {
    statements.add(
      ChainStatement.ThenStep(
        nodeKey = node.key, label = label, line = callSiteLine(), isEffects = true,
        assert = { boxes -> boxes.existingTyped(node)?.let { assert(it.lastEffects) } }))
  }

  private fun callSiteLine(): Int {
    // First stack frame outside this file = the scenario author's line.
    return Throwable().stackTrace
      .firstOrNull { it.fileName != null && it.fileName != "ChainScenario.kt" }
      ?.lineNumber ?: 0
  }
}

// ── Boxes (type-erased per-node stores) ─────────────────────────────────────

internal interface ChainBoxing {
  val key: String

  fun initialStateTree(): JsonElement
}

internal class ChainBox<S, A, P>(private val node: ChainNode<S, A, P>) : ChainBoxing {
  override val key: String = node.key
  var state: S = node.initial
  var lastEffects: List<Effect<P>> = emptyList()
  private val json = FixtureRunner.json

  override fun initialStateTree(): JsonElement =
    json.encodeToJsonElement(node.stateSerializer, node.initial)

  fun reduce(action: A): JsonElement {
    val reduced = node.reducer(state, action)
    state = reduced.state
    lastEffects = reduced.effects
    return JsonArray(reduced.effects.map { effectToJson(it, node.payloadSerializer, json) })
  }
}

/**
 * The per-run box registry. Generics are erased on the JVM, so instead of Swift's
 * failing cast the registry pins each key to the ChainNode HANDLE that created its box:
 * one handle per node key, reused across statements — a second handle sharing the key
 * is the authoring error the Swift flavor reports as a type mismatch.
 */
internal class ChainBoxes {
  val created = mutableListOf<ChainBoxing>()
  private val byKey = mutableMapOf<String, Pair<ChainNode<*, *, *>, ChainBoxing>>()

  fun box(node: ChainNode<*, *, *>): ChainBoxing {
    val existing = byKey[node.key]
    if (existing != null) {
      check(existing.first === node) {
        "node '${node.key}' is used via two different ChainNode handles " +
          "(two ChainNodes sharing a key must be one declared handle)"
      }
      return existing.second
    }
    val box = makeBox(node)
    byKey[node.key] = Pair(node, box)
    created.add(box)
    return box
  }

  fun existing(node: ChainNode<*, *, *>): ChainBoxing? {
    val entry = byKey[node.key] ?: return null
    check(entry.first === node) {
      "node '${node.key}' is used via two different ChainNode handles " +
        "(two ChainNodes sharing a key must be one declared handle)"
    }
    return entry.second
  }

  fun existingKey(key: String): ChainBoxing? = byKey[key]?.second

  private fun <S, A, P> makeBox(node: ChainNode<S, A, P>): ChainBox<S, A, P> = ChainBox(node)
}

/** Registry lookups stay handle-pinned (see [ChainBoxes]), so the erased cast is safe. */
internal fun <S, A, P> ChainBoxes.typed(node: ChainNode<S, A, P>): ChainBox<S, A, P> {
  @Suppress("UNCHECKED_CAST")
  return box(node) as ChainBox<S, A, P>
}

internal fun <S, A, P> ChainBoxes.existingTyped(node: ChainNode<S, A, P>): ChainBox<S, A, P>? {
  @Suppress("UNCHECKED_CAST")
  return existing(node) as ChainBox<S, A, P>?
}

// ── Runner ──────────────────────────────────────────────────────────────────

/** Record/verify for chain scenarios — the chain-dialect sibling of [ScenarioRunner]. */
object ChainScenarioRunner {

  fun verifyOrRecord(scenario: ChainScenario) {
    if (ScenarioRunner.regenerationRequested) {
      record(scenario)
    }
    verify(scenario)
  }

  // ── Record ──

  fun record(scenario: ChainScenario) {
    val json = FixtureRunner.json
    val source =
      scenario.source
        ?: error("record mode needs an explicit source path (no #filePath on the JVM)")
    val boxes = ChainBoxes()
    val steps = mutableListOf<JsonObject>()
    var lastEffectsTree: JsonElement = JsonArray(emptyList())

    for (statement in scenario.statements) {
      when (statement) {
        is ChainStatement.WhenStep -> {
          statement.ensure(boxes)
          val action = statement.actionTree()
          lastEffectsTree = statement.apply(boxes)
          steps.add(
            recordedStep(
              node = statement.nodeKey, label = statement.label, line = statement.line,
              action = action, effects = lastEffectsTree))
        }
        is ChainStatement.HopStep -> {
          check(steps.isNotEmpty()) {
            "Hop cannot be the first chain step (nothing emitted a delegate yet)"
          }
          val payload =
            lastNotifyListenerPayload(lastEffectsTree)
              ?: error(
                "Hop '${statement.label}': the previous step emitted no notifyListener delegate")
          steps[steps.size - 1] =
            JsonObject(steps.last() + ("linkToNext" to JsonPrimitive(true)))
          statement.ensure(boxes)
          val derived = statement.derive(payload)
          lastEffectsTree = derived.apply(boxes)
          steps.add(
            recordedStep(
              node = statement.toKey, label = statement.label, line = statement.line,
              action = derived.actionTree, effects = lastEffectsTree))
        }
        is ChainStatement.ThenStep -> {
          val passed =
            statement.assert(boxes)
              ?: error("Then on node '${statement.nodeKey}' before any of its steps")
          if (!passed) {
            // A false then during record is an authoring error — nothing is written.
            fail(
              "chain '${scenario.fixture}': Then '${statement.label}' failed during record " +
                "— fixture not written")
          }
        }
      }
    }

    val document = buildJsonObject {
      put("dialect", 2)
      put("chain", scenario.chain)
      put("description", scenario.description)
      put("scenario", buildJsonObject { put("source", source) })
      put(
        "initialStates",
        buildJsonObject { for (box in boxes.created) put(box.key, box.initialStateTree()) })
      put("steps", JsonArray(steps))
    }
    // Compact artifact — the CLI materializes the §6 file (one writer, F4·S2).
    val artifactDir = File(FixtureRunner.fixturesDirectory().parentFile, ".runs/record/kotlin")
    artifactDir.mkdirs()
    val file = File(artifactDir, "${scenario.fixture}.fixture.json")
    file.writeText(CanonicalJson.canonicalString(document))
    println(
      "ChainScenarioRunner: recorded ${scenario.fixture} (${steps.size} steps) → artifact; " +
        "materialize via `duet record --platform kotlin`")
  }

  private fun recordedStep(
    node: String,
    label: String,
    line: Int,
    action: JsonElement,
    effects: JsonElement,
  ): JsonObject = buildJsonObject {
    put("node", node)
    put("label", label)
    put("line", line)
    put("action", action)
    put("expectedEffects", effects)
  }

  // ── Verify ──

  fun verify(scenario: ChainScenario) {
    val json = FixtureRunner.json
    val fixture = scenario.fixture
    val source = scenario.source

    fun reportAndFail(rawFailure: ParityRunFailure, steps: Int?): Nothing {
      val failure = rawFailure.copy(rendered = FixtureRunner.format(rawFailure, fixture, source))
      RunReport.write(
        fixture = fixture, feature = null, status = "failed",
        steps = steps, scenarioSource = source, failures = listOf(failure))
      fail(failure.rendered ?: failure.kind)
    }

    fun structure(message: String): Nothing {
      reportAndFail(ParityRunFailure(kind = "structure", message = message), steps = null)
    }

    // In a record run, verify against the just-recorded artifact (this lane records
    // compact artifacts the CLI materializes AFTER the test run). Mirrors the Swift
    // runner, whose record mode writes the file and then verifies it.
    val committed = File(FixtureRunner.fixturesDirectory(), "$fixture.fixture.json")
    val artifact =
      File(
        File(FixtureRunner.fixturesDirectory().parentFile, ".runs/record/kotlin"),
        "$fixture.fixture.json")
    val file =
      if (ScenarioRunner.regenerationRequested && artifact.isFile) artifact else committed
    val root =
      runCatching {
        require(file.isFile) { "Fixture not found: ${file.path}" }
        json.parseToJsonElement(file.readText()).jsonObject
      }
        .getOrElse {
          structure("chain fixture missing or unreadable — record it: verify record")
        }
    val dialect = root["dialect"]?.jsonPrimitive?.intOrNull ?: 1
    if (dialect < 2) {
      structure("chain fixture is dialect $dialect (pre-scenario) — regenerate: verify record")
    }
    val rawSteps = root["steps"]?.jsonArray ?: structure("chain fixture has no steps")
    val rawInitialStates = root["initialStates"] as? JsonObject ?: JsonObject(emptyMap())

    // Every node the scenario touches, created upfront so the Given-equivalents gate
    // before any step replays.
    val boxes = ChainBoxes()
    for (statement in scenario.statements) {
      when (statement) {
        is ChainStatement.WhenStep -> statement.ensure(boxes)
        is ChainStatement.HopStep -> statement.ensure(boxes)
        is ChainStatement.ThenStep -> {}
      }
    }
    for (box in boxes.created) {
      val rawInitial =
        rawInitialStates[box.key]
          ?: structure("fixture has no initialStates['${box.key}'] — regenerate: verify record")
      val expected = CanonicalJson.canonicalString(rawInitial)
      val actual = CanonicalJson.canonicalString(box.initialStateTree())
      if (expected != actual) {
        structure(
          "node '${box.key}' seed drifted from recorded initialStates — regenerate: verify record")
      }
    }
    for (key in rawInitialStates.keys) {
      if (boxes.existingKey(key) == null) {
        structure("fixture initialStates has unknown node '$key' — regenerate: verify record")
      }
    }

    val whenCount = scenario.statements.count { it !is ChainStatement.ThenStep }
    if (whenCount != rawSteps.size) {
      structure(
        "chain scenario has $whenCount step(s) but fixture has ${rawSteps.size} " +
          "— regenerate: verify record")
    }

    // The walk. Thens run before their step's byte gate (same deferred-gate contract as
    // ScenarioRunner); a hop byte-gates the PREVIOUS step first, so a divergent
    // delegate fails as `effects` there, not as a confusing decode error here.
    // kotlin.test.fail throws, so the walk ends at the first reported failure — no
    // StopWalk mirror needed on the JVM.
    class Pending(
      val index: Int,
      val nodeKey: String,
      val label: String,
      val line: Int,
      val effectsTree: JsonElement,
      val actionCanonical: String,
    )

    var pending: Pending? = null
    var lastEffectsTree: JsonElement = JsonArray(emptyList())
    var stepIndex = 0

    fun flushPendingGate() {
      val step = pending ?: return
      pending = null
      val rawExpected = rawSteps[step.index].jsonObject["expectedEffects"] ?: JsonArray(emptyList())
      val expected = CanonicalJson.canonicalString(rawExpected)
      val actual = CanonicalJson.canonicalString(step.effectsTree)
      if (expected != actual) {
        val divergence = FixtureDiff.firstDivergence(rawExpected, step.effectsTree)
        reportAndFail(
          ParityRunFailure(
            step = step.index, label = step.label, line = step.line, kind = "effects",
            node = step.nodeKey, path = divergence?.path, expected = divergence?.expected,
            actual = divergence?.actual, action = step.actionCanonical),
          steps = null)
      }
    }

    fun advance(
      nodeKey: String,
      label: String,
      line: Int,
      actionTree: JsonElement,
      apply: (ChainBoxes) -> JsonElement,
      viaHop: Boolean,
    ) {
      val rawStep = rawSteps[stepIndex].jsonObject
      val fixtureNode = rawStep["node"]?.jsonPrimitive?.contentOrNull
      if (fixtureNode != nodeKey) {
        reportAndFail(
          ParityRunFailure(
            step = stepIndex, label = label, line = line, kind = "structure", node = nodeKey,
            message =
              "scenario step is on node '$nodeKey' but the fixture recorded " +
                "'${fixtureNode ?: "?"}' — regenerate: verify record"),
          steps = null)
      }
      val scenarioAction = CanonicalJson.canonicalString(actionTree)
      val fixtureAction = CanonicalJson.canonicalString(rawStep["action"] ?: JsonObject(emptyMap()))
      if (scenarioAction != fixtureAction) {
        reportAndFail(
          ParityRunFailure(
            step = stepIndex, label = label, line = line, kind = "structure", node = nodeKey,
            action = scenarioAction,
            message =
              "scenario ${if (viaHop) "hop-derived " else ""}action drifted from fixture " +
                "(recorded: $fixtureAction) — regenerate: verify record"),
          steps = null)
      }
      if (viaHop && stepIndex > 0 &&
        (rawSteps[stepIndex - 1].jsonObject["linkToNext"] as? JsonPrimitive)?.booleanOrNull != true
      ) {
        reportAndFail(
          ParityRunFailure(
            step = stepIndex, label = label, line = line, kind = "structure", node = nodeKey,
            message =
              "hop step, but fixture step ${stepIndex - 1} is not marked linkToNext " +
                "— regenerate: verify record"),
          steps = null)
      }
      lastEffectsTree = apply(boxes)
      pending =
        Pending(
          index = stepIndex, nodeKey = nodeKey, label = label, line = line,
          effectsTree = lastEffectsTree, actionCanonical = scenarioAction)
      stepIndex += 1
    }

    for (statement in scenario.statements) {
      when (statement) {
        is ChainStatement.WhenStep -> {
          flushPendingGate()
          advance(
            nodeKey = statement.nodeKey, label = statement.label, line = statement.line,
            actionTree = statement.actionTree(), apply = statement.apply, viaHop = false)
        }
        is ChainStatement.HopStep -> {
          flushPendingGate()
          val payload =
            lastNotifyListenerPayload(lastEffectsTree)
              ?: reportAndFail(
                ParityRunFailure(
                  step = stepIndex, label = statement.label, line = statement.line,
                  kind = "structure", node = statement.toKey,
                  message = "Hop, but the previous step emitted no notifyListener delegate"),
                steps = null)
          val derived = statement.derive(payload)
          advance(
            nodeKey = statement.toKey, label = statement.label, line = statement.line,
            actionTree = derived.actionTree, apply = derived.apply, viaHop = true)
        }
        is ChainStatement.ThenStep -> {
          val passed = statement.assert(boxes) ?: continue
          if (!passed) {
            var failure =
              ParityRunFailure(
                step = pending?.index, label = statement.label, line = statement.line,
                kind = "assertion", node = statement.nodeKey,
                message =
                  if (statement.isEffects) {
                    "ThenEffects returned false against the node's last emitted effects"
                  } else {
                    "Then returned false against the node's current state"
                  })
            // Attach the pending step's effects divergence, if any (thens run first).
            val step = pending
            if (step != null) {
              val rawExpected = rawSteps[step.index].jsonObject["expectedEffects"]
              val divergence =
                rawExpected?.let { FixtureDiff.firstDivergence(it, step.effectsTree) }
              if (divergence != null) {
                val joiner = if (divergence.path.startsWith("[")) "" else "."
                failure =
                  failure.copy(
                    path = "expectedEffects$joiner${divergence.path}",
                    expected = divergence.expected,
                    actual = divergence.actual,
                    message =
                      (failure.message ?: "") +
                        " — the step's effects also diverged from the fixture")
              }
            }
            reportAndFail(failure, steps = null)
          }
        }
      }
    }
    flushPendingGate()

    RunReport.write(
      fixture = fixture, feature = null, status = "passed",
      steps = rawSteps.size, scenarioSource = source, failures = emptyList())
  }

  // ── Plumbing ──

  /**
   * The delegate payload of the LAST `notifyListener` effect in a canonical effects
   * tree (null when there is none) — the value a hop forwards.
   */
  internal fun lastNotifyListenerPayload(effectsTree: JsonElement): JsonElement? {
    val effects = effectsTree as? JsonArray ?: return null
    for (effect in effects.reversed()) {
      val payload = (effect as? JsonObject)?.get("payload") as? JsonObject ?: continue
      if ((payload["case"] as? JsonPrimitive)?.content != "notifyListener") continue
      return payload["value"] ?: continue
    }
    return null
  }
}
