// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.replay

import dev.modaal.duet.kernel.serialization.CanonicalJson
import dev.modaal.duet.kernel.serialization.CanonicalSerializers

/**
 * The cross-Apple-boundary replay surface (the FC spike's decisive convergence
 * artifact, productized): the whole decode → reduce → canonical-encode pipeline
 * behind a String-in / String-out face, because neither `KSerializer` generics
 * nor Kotlin `fun` references cross the Kotlin/Native → Swift boundary
 * ergonomically.
 *
 * THE PARITY INVARIANT: every canonical byte returned here is produced by the
 * core's OWN machinery — the app's serializers, the pinned
 * [CanonicalSerializers.json], and [CanonicalJson]. A Swift consumer only loads
 * fixture files, hands each step's `action` JSON in, and byte-compares the
 * returned canonical strings against the fixture's expectations — themselves
 * canonicalized through [canonicalize] (the SAME writer).
 */
object BoundaryReplay {
  /**
   * Canonicalize arbitrary JSON text through the core's [CanonicalJson] — the
   * fixture-expected side of the gate.
   */
  fun canonicalize(rawJson: String): String =
    CanonicalJson.canonicalString(CanonicalSerializers.json.parseToJsonElement(rawJson))

  /**
   * A fresh stateful replay session over [registry]'s [feature], seeded with
   * `initialStateJson`. Leaf fixtures use one session; chain fixtures drive one
   * per node. Named `makeSession` (not `newSession`): the ObjC `new` prefix is a
   * reserved ARC method family — K/N would mangle it on the Swift side.
   */
  fun makeSession(
    registry: ReplayRegistry,
    feature: String,
    initialStateJson: String,
  ): ReplaySession {
    val replay =
      registry.features[feature]
        ?: throw IllegalArgumentException("BoundaryReplay: unknown feature '$feature'")
    return ReplaySession(replay, initialStateJson)
  }
}

/**
 * One node's replay state, exposed to Swift as decode-action → reduce →
 * canonical(state, effects). The threaded state is the previous step's ACTUAL
 * canonical output — the session is a convenience over the stateless
 * [ReplayFeature.step], not a second replay semantics.
 */
class ReplaySession internal constructor(
  private val replay: ReplayFeature,
  initialStateJson: String,
) {
  private var stateCanonical: String = BoundaryReplay.canonicalize(initialStateJson)

  fun step(actionJson: String): StepResult {
    val result = replay.step(stateCanonical, actionJson)
    stateCanonical = result.stateCanonical
    return result
  }
}
