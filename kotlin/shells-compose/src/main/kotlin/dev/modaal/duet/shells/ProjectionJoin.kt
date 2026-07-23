// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

// Shell duty 4 — the R13 helper. R13 (doc 08 §3.1): a projection over feature
// state PLUS an auxiliary async source must re-apply whenever ANY input arrives
// — the sources race, and a projection that only re-runs on state updates
// silently drops rows when state lands first. This type owns the subscription
// mechanics so the join rule can't be forgotten per call site.

/**
 * Joins a store's state flow with one auxiliary source (an index, a cache, a
 * repository stream) and re-runs [apply] on every input.
 *
 * Semantics, pinned:
 * - `apply` runs with the latest of both; the first state emission applies
 *   against [initialAux] — project thin, self-heal when the aux source lands
 *   (R13). Duplicate states are filtered.
 * - Thinness note (vs the Swift twin's synchronous Combine path): collection
 *   rides [scope] — main-confined, `Main.immediate` in production — so a
 *   reduce is observed within the same main-loop turn, not before `send`
 *   returns; `StateFlow` conflation may coalesce intermediate states. Both are
 *   safe by construction because `apply`/reconcilers are value-driven over the
 *   LATEST state, and both are asserted per-app by the churn specs.
 *
 * Swift-flavor mirror: DuetShells/ProjectionJoin.swift.
 */
class ProjectionJoin<State, Aux>(
  scope: CoroutineScope,
  state: Flow<State>,
  joining: Flow<Aux>,
  initialAux: Aux,
  private val apply: (State, Aux) -> Unit,
) : HostedObservation {
  /** The latest auxiliary value, for hosts that resolve through it outside [apply]. */
  var aux: Aux = initialAux
    private set

  private var latestState: State? = null
  private var hasState = false
  private val jobs = mutableListOf<Job>()

  init {
    jobs.add(
      scope.launch {
        state.distinctUntilChanged().collect { newState ->
          latestState = newState
          hasState = true
          apply(newState, aux)
        }
      })
    jobs.add(
      scope.launch {
        joining.collect { newAux ->
          aux = newAux
          if (hasState) {
            @Suppress("UNCHECKED_CAST")
            apply(latestState as State, newAux)
          }
        }
      })
  }

  override fun cancel() {
    jobs.forEach { it.cancel() }
    jobs.clear()
  }
}

/**
 * Observes a store's state on the host scope, delivering `(old, new)`
 * transition pairs — the seam where shells hang analytics and presentation
 * gates without deciding anything themselves (R8). The first emission delivers
 * `(current, current)`; duplicates are filtered. Swift-flavor mirror:
 * DuetShells/ProjectionJoin.swift (`StateTransitions`).
 */
class StateTransitions<State>(
  scope: CoroutineScope,
  state: Flow<State>,
  private val onChange: (old: State, new: State) -> Unit,
) : HostedObservation {
  private var previous: State? = null
  private var hasPrevious = false
  private val job: Job

  init {
    job =
      scope.launch {
        state.distinctUntilChanged().collect { newState ->
          val old = if (hasPrevious) {
            @Suppress("UNCHECKED_CAST")
            previous as State
          } else {
            newState
          }
          previous = newState
          hasPrevious = true
          onChange(old, newState)
        }
      }
  }

  override fun cancel() {
    job.cancel()
  }
}
