// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import com.arkivanov.essenty.instancekeeper.InstanceKeeper
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * The retained carrier (the Q2 mechanics receipt, promoted from receipt to
 * API on the 2026-07-30 graduation review): an `InstanceKeeper.Instance` owning the
 * app's logical scope and its composition root.
 * `instanceKeeper().getOrCreate { RetainedRoot(…) }` in a thin Activity
 * returns the SAME instance across configuration change — rotation never
 * crosses the worker bracket; logical destruction (finish, not rotation) is
 * the ONE teardown. The order is the contract this type exists to pin: the
 * component tears down FIRST (LIFO through its `StoreHost`), on a scope that
 * is still alive, and only then is the scope cancelled — so workers unwind
 * cooperatively instead of dying mid-suspension.
 *
 * iOS has no twin by platform design: `UIApplication`-scoped singletons give
 * the scene glue the same reach app-side (the flavor ledger records the
 * single).
 *
 * [context] is the tree's dispatcher — `Dispatchers.Main.immediate` in an
 * app, the test dispatcher in host tests. [create] builds the composition
 * root on the owned scope; [teardown] is the component's logical-destruction
 * hook (typically forwarding to `StoreHost.teardownAll`).
 */
class RetainedRoot<T : Any>(
  context: CoroutineContext,
  private val teardown: (T) -> Unit,
  create: (CoroutineScope) -> T,
) : InstanceKeeper.Instance {
  /** The retained/logical scope — dies with the instance, never with an Activity. */
  val scope: CoroutineScope = CoroutineScope(SupervisorJob() + context)

  /** The app's composition root, built once on [scope]. */
  val component: T = create(scope)

  override fun onDestroy() {
    teardown(component)
    scope.cancel()
  }
}
