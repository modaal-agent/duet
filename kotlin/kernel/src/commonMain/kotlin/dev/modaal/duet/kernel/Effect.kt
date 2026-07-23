// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel

/**
 * Identifies an in-flight effect for cancellation. Plain string, namespaced by convention
 * as `"<feature>.<purpose>"`. See contracts/store-kernel-contract.md §2.
 * Swift-flavor mirror: Duet/Effect.swift.
 */
typealias EffectId = String

/**
 * A side-effect *request* as equatable data. The reducer emits these; the store's runtime
 * executes them via the feature's `EffectHandler`. Contract: store-kernel-contract.md §2.
 */
sealed interface Effect<out P> {
  /**
   * Execute [payload] via the handler. A non-null [id] gives cancel-in-flight semantics:
   * any running effect with the same id is cancelled before this one starts.
   */
  data class Run<P>(val payload: P, val id: EffectId? = null) : Effect<P>

  /** Cancel the running effect with [id]; no-op if none. */
  data class Cancel(val id: EffectId) : Effect<Nothing>
}

/**
 * A reducer step's result: the new state plus the effects it requests.
 * Mapping rule from the Swift flavor's `inout` reducer: every mutation sequence becomes
 * one `copy(...)` (contract §1).
 */
data class Reduced<S, out P>(val state: S, val effects: List<Effect<P>> = emptyList())
