// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import dev.modaal.duet.kernel.Store

// The generic handle vocabulary — Kotlin twins. Thinness note:
// the Swift handles are UIKit-bound (they carry the child's UIViewController;
// mounts install it view-first). On Compose the view half does not exist —
// composition lifetimes do view mount/teardown — so the twins carry
// exactly the part the platform does NOT absorb: the activate/teardown
// ORDERING contract a composition root must uphold when route state drops a
// child. Swift-flavor mirror: DuetShells/ChildHandles.swift.

/**
 * The lifecycle surface a child shell exposes to its handle — bind on mount,
 * unbind on drop. Swift-flavor mirror: `Activatable` (DuetShells/ViewShell.swift).
 */
interface Activatable {
  fun activate()

  fun deactivate()
}

/**
 * The router-less child handle for an OWNED store: the builder constructs
 * (store + environment + shell in one call), the mount mechanics call
 * [activate], and the owning composition root holds the handle, calling
 * [teardown] when route state drops the child. Store lifetime = mount
 * lifetime; the churn specs are the lifecycle receipt.
 */
class StoreChild<S, A, P>(
  val store: Store<S, A, P>,
  private val shell: Activatable,
) {
  fun activate() {
    shell.activate()
  }

  /**
   * The owning composition root's drop: shell down first (observation stop),
   * then the store (in-flight effects cancel) — one unit, in that order.
   */
  fun teardown() {
    shell.deactivate()
    store.teardown()
  }
}

/**
 * The permanent-tab variant: a shell around a store its OWNER already holds
 * (the composition root's host tears that store down; [StoreChild] would
 * wrongly re-own it). The handle carries shell lifecycle only — [activate] at
 * mount, [deactivate] when the owner dies.
 */
class ViewShellChild(private val shell: Activatable) {
  fun activate() {
    shell.activate()
  }

  fun deactivate() {
    shell.deactivate()
  }
}
