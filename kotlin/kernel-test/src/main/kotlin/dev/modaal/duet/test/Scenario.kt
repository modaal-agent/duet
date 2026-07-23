// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.Effect

/**
 * FT2 — the scenario DSL, Kotlin dialect. Mirrors DuetTesting/Scenario.swift:
 * a scenario is the authored source of a parity fixture; `Then`/`ThenEffects` closures
 * are local assertions (never exported). Kotlin cannot capture a compile-time source
 * *path* (no `#filePath`), so `source` is an explicit parameter and call-site lines come
 * from the stack (JVM line numbers — reliable under Gradle/JUnit, but a documented
 * platform asymmetry).
 *
 * Control flow inside a scenario body is not blocked by the compiler here (unlike the
 * Swift result builder, which omits buildOptional/buildEither) — R11 relies on review
 * on this platform. A second documented asymmetry. R11's target is *data-dependent*
 * control flow (what gets recorded must never depend on a runtime value); `branch` is
 * static structure — every branch always runs, each as its own recorded fixture — so
 * alternates are expressible without weakening the rule.
 */
sealed interface ScenarioNode<S, A, P> {
  data class Given<S, A, P>(val state: S, val line: Int) : ScenarioNode<S, A, P>

  data class When<S, A, P>(val label: String, val action: A, val line: Int) :
    ScenarioNode<S, A, P>

  data class Then<S, A, P>(val label: String, val line: Int, val assert: (S) -> Boolean) :
    ScenarioNode<S, A, P>

  data class ThenEffects<S, A, P>(
    val label: String,
    val line: Int,
    val assert: (List<Effect<P>>) -> Boolean,
  ) : ScenarioNode<S, A, P>

  data class Context<S, A, P>(val label: String, val nodes: List<ScenarioNode<S, A, P>>) :
    ScenarioNode<S, A, P>

  data class Branch<S, A, P>(
    val label: String,
    val line: Int,
    val nodes: List<ScenarioNode<S, A, P>>,
  ) : ScenarioNode<S, A, P>
}

class Scenario<S, A, P>(
  val feature: String,
  val fixture: String,
  val description: String,
  /** Repo-relative path of this authoring file (explicit — no #filePath on the JVM). */
  val source: String?,
  val nodes: List<ScenarioNode<S, A, P>>,
)

fun <S, A, P> scenario(
  feature: String,
  fixture: String = feature,
  description: String,
  source: String? = null,
  block: ScenarioBuilder<S, A, P>.() -> Unit,
): Scenario<S, A, P> {
  val builder = ScenarioBuilder<S, A, P>()
  builder.block()
  return Scenario(feature, fixture, description, source, builder.nodes)
}

class ScenarioBuilder<S, A, P> internal constructor() {
  internal val nodes = mutableListOf<ScenarioNode<S, A, P>>()

  /** The initial state. Exactly one `given`, first in the scenario body. */
  fun given(state: S) {
    nodes.add(ScenarioNode.Given(state, callSiteLine()))
  }

  /** One dispatched action — one fixture step. (`when` is a Kotlin keyword.) */
  fun whenAction(label: String, action: A) {
    nodes.add(ScenarioNode.When(label, action, callSiteLine()))
  }

  /** Local state assertion against the state produced by the preceding `whenAction`. */
  fun then(label: String, assert: (S) -> Boolean) {
    nodes.add(ScenarioNode.Then(label, callSiteLine(), assert))
  }

  /** Local assertion on the effects emitted by the preceding `whenAction`. */
  fun thenEffects(label: String, assert: (List<Effect<P>>) -> Boolean) {
    nodes.add(ScenarioNode.ThenEffects(label, callSiteLine(), assert))
  }

  /** Narrative grouping — linear, like the Swift dialect (a chapter, not a branch). */
  fun context(label: String, block: ScenarioBuilder<S, A, P>.() -> Unit) {
    val child = ScenarioBuilder<S, A, P>()
    child.block()
    nodes.add(ScenarioNode.Context(label, child.nodes))
  }

  /**
   * A static alternate ending — the Quick-style fork the linear `context` is not. Each
   * sibling `branch` replays the shared prefix (pure reducers make that free), runs its
   * own steps in isolation from its siblings, and compiles to its OWN fixture:
   * `<fixture>.<slug>` (nested branches append: `<fixture>.<slug>.<slug>`). Branches
   * are terminal at their level: once one appears, only branches may follow there.
   *
   * R11 note: branches are *static* alternates — every branch always runs and records;
   * no runtime value chooses between them. Data-dependent control flow stays banned; on
   * the JVM there is still no compile-time enforcement, so R11 relies on review.
   */
  fun branch(label: String, block: ScenarioBuilder<S, A, P>.() -> Unit) {
    val child = ScenarioBuilder<S, A, P>()
    child.block()
    nodes.add(ScenarioNode.Branch(label, callSiteLine(), child.nodes))
  }

  private fun callSiteLine(): Int {
    // First stack frame outside this file = the scenario author's line.
    return Throwable().stackTrace
      .firstOrNull { it.fileName != null && it.fileName != "Scenario.kt" }
      ?.lineNumber ?: 0
  }
}
