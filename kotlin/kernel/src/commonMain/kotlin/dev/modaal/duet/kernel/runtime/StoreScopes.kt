// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.runtime

import dev.modaal.duet.kernel.Store
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * The runtime seam an Apple (SKIE) consumer needs to RUN the common [Store] from Swift —
 * the FC spike's K4 finding, productized. Three things do not cross the Kotlin/Native →
 * Swift boundary usefully on their own:
 *
 *  1. **The host scope.** The store's `scope` must be `Dispatchers.Main.immediate`
 *     (store-kernel-contract §3 rules 1 & 5), and no `CoroutineScope` factory is on the
 *     exported ObjC surface — [mainImmediateStoreScope] is the minimum bridge.
 *  2. **The reducer + handler blocks.** `Store.init`'s function params export as
 *     erased-nullable ObjC blocks, and SKIE re-wraps a returned `Flow` as `SkieSwiftFlow`.
 *     An app therefore keeps per-feature `make<Feature>Store(environment, scope)` factories
 *     in ITS OWN commonMain (scaffold-emitted glue, a few lines each), passing its pure
 *     reducer/handler verbatim — the wiring stays on the Kotlin side by construction.
 *  3. **The typed state stream.** `Store<S, A, P>.state` exports element-untyped; the same
 *     per-feature factories re-expose it in a concrete-typed position
 *     (`fun <feature>StateFlow(store) : StateFlow<FeatureState> = store.state`) so SKIE
 *     bridges it to a `for await`-able `SkieSwiftStateFlow`.
 *
 * Runtime note (M7): on Kotlin/Native Darwin, `Dispatchers.Main` is the main dispatch
 * queue — coroutines progress only while the host services the main run loop.
 */

/**
 * A host [CoroutineScope] on `Dispatchers.Main.immediate` — the production contract
 * dispatcher. `SupervisorJob` so one failed effect does not tear down the scope. Cancel it
 * with [cancelStoreScope]; [Store.teardown] cancels in-flight effects without touching it.
 */
fun mainImmediateStoreScope(): CoroutineScope =
  CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

/** Cancels [scope] and every coroutine launched in it — structured teardown for a host-owned scope. */
fun cancelStoreScope(scope: CoroutineScope) {
  scope.cancel()
}
