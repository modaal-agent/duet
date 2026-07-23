// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Reconciler receipts: value-keyed identity, departure teardown, slot rebuild. */
class ReconcilersTest {

  @Test
  fun childStoresBuildsNewcomersAndTearsDownDepartures() {
    val built = mutableListOf<String>()
    val torn = mutableListOf<String>()
    val children =
      ChildStores<String, String>(
        build = { key -> built.add(key); "handle-$key" },
        teardown = { handle -> torn.add(handle) })

    children.reconcile(setOf("a", "b"))
    assertEquals(2, children.activeCount)
    children.reconcile(setOf("b", "c"))
    assertEquals(listOf("a", "b", "c"), built)
    assertEquals(listOf("handle-a"), torn)

    children.teardownAll()
    assertEquals(0, children.activeCount)
    assertEquals(listOf("handle-a", "handle-b", "handle-c"), torn)
  }

  @Test
  fun childStoresSharesOneHandlePerRouteValue() {
    var builds = 0
    val children =
      ChildStores<String, Int>(build = { builds += 1; builds }, teardown = {})
    children.reconcile(setOf("route"))
    assertEquals(children.handleFor("route"), children.handleFor("route"))
    assertEquals(1, builds)
  }

  @Test
  fun childSlotRebuildsOnKeyChangeAndClears() {
    val torn = mutableListOf<String>()
    val slot =
      ChildSlot<String, String>(build = { "handle-$it" }, teardown = { torn.add(it) })

    slot.reconcile("sheet-a")
    assertEquals("sheet-a", slot.activeKey)
    slot.reconcile("sheet-a")
    assertEquals(emptyList(), torn)

    slot.reconcile("sheet-b")
    assertEquals(listOf("handle-sheet-a"), torn)
    slot.reconcile(null)
    assertEquals(listOf("handle-sheet-a", "handle-sheet-b"), torn)
    assertNull(slot.activeKey)
  }
}
