// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

// Breaks the child-environment ↔ parent-store construction cycle without
// late-init contortions. The composition root creates the relay, hands `send`
// to the child environment (or worker) it is building, and assigns `sink` once
// the parent store exists. Also the sanctioned ingress for app-level
// orchestration events emitted by workers (doc 20 §4.2) — the same
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
}
