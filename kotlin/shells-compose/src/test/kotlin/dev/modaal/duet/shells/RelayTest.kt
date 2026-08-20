// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import java.lang.ref.WeakReference
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Relay receipts: `send` forwards to whatever [Relay.sink] holds at send time,
 * and [Relay.bindSink]'s owner hold is weak. The control for the weak hold is
 * an owner dropped mid-mount — the relay drops the event, and the owner is
 * collectible with the relay's sink still installed.
 */
class RelayTest {

  private class Owner {
    val received = mutableListOf<Int>()
  }

  @Test
  fun sendForwardsToTheSinkHeldAtSendTime() {
    val relay = Relay<Int>()
    val first = mutableListOf<Int>()
    val second = mutableListOf<Int>()

    // Before wiring: dropped by design.
    relay.send(1)

    relay.sink = { first.add(it) }
    relay.send(2)

    relay.sink = { second.add(it) }
    relay.send(3)

    assertEquals(listOf(2), first)
    assertEquals(listOf(3), second)
  }

  @Test
  fun bindSinkPassesTheOwnerBackToTheHandler() {
    val relay = Relay<Int>()
    val owner = Owner()

    relay.bindSink(owner) { boundOwner, event -> boundOwner.received.add(event) }
    relay.send(7)
    relay.send(8)

    assertEquals(listOf(7, 8), owner.received)
  }

  @Test
  fun bindSinkHoldsTheOwnerWeaklyAndDropsEventsAfterItIsCollected() {
    val relay = Relay<Int>()
    var handlerCalls = 0

    // The owner is created and wired in a frame that returns, so the local slot
    // holding it is gone and the only remaining candidate for a strong
    // reference is the relay's own sink.
    fun wire(): WeakReference<Owner> {
      val owner = Owner()
      relay.bindSink(owner) { boundOwner, event ->
        handlerCalls++
        boundOwner.received.add(event)
      }
      relay.send(1)
      return WeakReference(owner)
    }
    val tracked = wire()

    assertEquals(1, handlerCalls)
    awaitCollection(tracked)
    assertNull(tracked.get(), "bindSink kept the owner reachable after its frame returned")

    relay.send(2)
    assertEquals(1, handlerCalls)
  }

  /**
   * Polls for collection around explicit GC requests — the one assertion class
   * that cannot ride virtual time, and the technique `kernel-test`'s
   * `ChildDeallocLedger` uses. The ledger itself is not imported here because
   * `kernel-test` depends on this module; the dependency runs one way only.
   */
  private fun awaitCollection(reference: WeakReference<*>, timeoutMillis: Long = 2_000) {
    val deadline = System.nanoTime() + timeoutMillis * 1_000_000
    while (reference.get() != null && System.nanoTime() < deadline) {
      System.gc()
      Thread.sleep(20)
    }
  }
}
