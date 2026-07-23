// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import kotlin.reflect.KClass

// Layer 3 of the presentation contract (contracts/presentation-contract.md §5):
// the per-HOST kind→renderer registry. A feature ships its kind (a sealed case,
// Layer 1); the platform's composition root binds how that kind renders —
// manner (detents, chrome, wrapping surfaces) lives entirely inside the
// renderer closure, so reducers and fixtures never see it. One registry per
// interior host node; a node whose slot has a single kind may render directly
// (a one-entry registry is ceremony, not a seam).

/**
 * Kind-indexed renderer table. Registration is composition-root work;
 * resolution is host-view work. Renderers may return null (child not built yet
 * — hosts fall back to a placeholder and the reconciler catches up).
 *
 * Thinness note (vs the Swift twin): generic over [Surface] where Swift pins
 * `AnyView` — SwiftUI forces an erasure type; Kotlin needs none, and staying
 * generic keeps this artifact Compose-free (a Compose app instantiates
 * `PresentationRegistry<@Composable () -> Unit>` — or its own surface value —
 * from its composition roots). Swift-flavor mirror:
 * DuetShells/PresentationRegistry.swift.
 */
class PresentationRegistry<Surface : Any> {
  private val renderers = mutableMapOf<KClass<*>, (Any) -> Surface?>()

  /**
   * Bind the renderer for a kind type. Re-registering replaces (last write
   * wins — composition roots register once at construction).
   */
  fun <Kind : Any> register(kind: KClass<Kind>, renderer: (Kind) -> Surface?) {
    renderers[kind] = { anyKind ->
      @Suppress("UNCHECKED_CAST")
      (anyKind as? Kind)?.let(renderer)
    }
  }

  /**
   * Resolve the platform surface for a kind value; null when the kind type has
   * no renderer or the renderer declined (child not reconciled yet).
   *
   * Sealed-hierarchy note (the Swift twin resolves by STATIC type; Kotlin
   * values carry their leaf class): an exact-class entry wins, else the first
   * registered entry whose kind class the value is an instance of — so
   * registering the sealed ROOT covers every case, matching the Swift
   * geometry.
   */
  fun surfaceFor(kind: Any): Surface? {
    val entry =
      renderers[kind::class]
        ?: renderers.entries.firstOrNull { it.key.isInstance(kind) }?.value
    return entry?.invoke(kind)
  }
}
