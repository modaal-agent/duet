// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.Effect

/**
 * Builds the expected-effects list for a `thenEffects` closure without spelling the
 * payload generic: `Effect.Cancel` is non-generic (`Effect<Nothing>`) and poisons bare
 * `listOf` inference, forcing `listOf<Effect<CounterEffectPayload>>(…)` at call sites.
 * With this helper the closure reads `it == effectsOf(Effect.Cancel(id))`.
 */
fun <P> effectsOf(vararg effects: Effect<P>): List<Effect<P>> = effects.toList()
