// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

// Shell duty 2+4, factored once: build children on route appearance, tear them
// down on route disappearance. This is the whole "Router" brain — everything
// else in a shell is observation + forwarding one-liners. Main-confined by
// contract (driven from the host's state observation). Swift-flavor mirror:
// DuetShells/ChildStores.swift.

/**
 * Multi-child reconciler for stack routes. Keyed by the route VALUE: pushing
 * the byte-identical route twice shares one child (one source of truth per
 * identity — Compose's value-keyed navigation has the same semantics).
 */
class ChildStores<K : Any, H>(
  private val build: (K) -> H?,
  private val teardown: (H) -> Unit,
) {
  private val handles = mutableMapOf<K, H>()

  val activeCount: Int
    get() = handles.size

  /**
   * Lazily builds on first access (a destination pulling its child);
   * [reconcile] is the authoritative lifecycle driver.
   */
  fun handleFor(key: K): H? {
    handles[key]?.let { return it }
    val built = build(key) ?: return null
    handles[key] = built
    return built
  }

  /** Tears down every child whose key left the route set, builds newcomers. */
  fun reconcile(keys: Set<K>) {
    val departed = handles.keys.filter { it !in keys }
    for (key in departed) {
      val handle = handles.remove(key) ?: continue
      teardown(handle)
    }
    for (key in keys) {
      if (key !in handles) {
        build(key)?.let { handles[key] = it }
      }
    }
  }

  fun teardownAll() {
    val all = handles.values.toList()
    handles.clear()
    all.forEach(teardown)
  }
}

/**
 * Single-slot reconciler for modal routes (sheet/dialog): at most one child,
 * rebuilt when the route value changes, torn down when it clears.
 */
class ChildSlot<K : Any, H>(
  private val build: (K) -> H?,
  private val teardown: (H) -> Unit,
) {
  private var current: Pair<K, H>? = null

  val activeKey: K?
    get() = current?.first

  val activeHandle: H?
    get() = current?.second

  fun reconcile(key: K?) {
    val existing = current
    if (existing != null && existing.first == key) return
    if (existing != null) {
      current = null
      teardown(existing.second)
    }
    if (key != null) {
      build(key)?.let { current = key to it }
    }
  }

  fun teardownAll() {
    val existing = current ?: return
    current = null
    teardown(existing.second)
  }
}
