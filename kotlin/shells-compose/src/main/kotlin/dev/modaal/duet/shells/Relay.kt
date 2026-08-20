// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import java.lang.ref.WeakReference

// Breaks the child-environment ↔ parent-store construction cycle without
// late-init contortions. The composition root creates the relay, hands `send`
// to the child environment (or worker) it is building, and assigns `sink` once
// the parent store exists. Also the sanctioned ingress for app-level
// orchestration events emitted by workers — the same
// delegate-events-as-actions machinery children use.

/**
 * A settable event funnel: `send` forwards to whatever `sink` holds at that
 * moment. Events before wiring are dropped by design — composition-root
 * construction is synchronous, so nothing real can fire in the gap.
 * Swift-flavor mirror: DuetShells/Relay.swift.
 */
class Relay<Event> {
  var sink: ((Event) -> Unit)? = null

  fun send(event: Event) {
    sink?.invoke(event)
  }

  /**
   * Sets [sink] to a lambda that holds [owner] through a [WeakReference] and
   * passes it back to [handler]. Events sent after [owner] is collected are
   * dropped, the same way events sent before wiring are.
   *
   * This is the sink form for the case where the capture IS an owner object —
   * the store, shell, or worker whose mount the wiring belongs to. The weak
   * hold keeps a torn-down owner collectible: a relay that outlives its owner
   * holds no strong reference back. (The Swift twin's weak hold buys a
   * different thing — there it breaks an ARC cycle across the mount.)
   *
   * ```kotlin
   * routeRelay.bindSink(this) { root, route -> root.store.send(Routed(route)) }
   * ```
   *
   * Assign [sink] directly when the capture is not an owner object —
   * `routeRelay.sink = routeStore::send`, or a lambda over values.
   */
  fun <Owner : Any> bindSink(owner: Owner, handler: (Owner, Event) -> Unit) {
    val reference = WeakReference(owner)
    sink = { event -> reference.get()?.let { handler(it, event) } }
  }
}
