// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * The W4 rulings as a harness contract (the Swift original's semantics,
 * pinned for the Kotlin twin): take drains, discard settles, place is the
 * late-delivery path — first write wins and a settled box ignores it.
 */
class RestoredSpineBoxTest {

  @Test
  fun takeDrainsOnceThenEmptyForever() {
    val box = RestoredSpineBox("spine")
    assertEquals("spine", box.take())
    assertNull(box.take())
    // A late placement after the decision must never resurrect a spine.
    box.place("late")
    assertNull(box.take())
  }

  @Test
  fun discardSettlesTheBox() {
    val box = RestoredSpineBox("spine")
    box.discard()
    assertNull(box.take())
    box.place("late")
    assertNull(box.take())
  }

  @Test
  fun placeDeliversLateOnAnUnsettledBox() {
    val box = RestoredSpineBox<String>(null)
    box.place("late")
    assertEquals("late", box.take())
  }

  @Test
  fun firstPlacementWins() {
    val box = RestoredSpineBox<String>(null)
    box.place("first")
    box.place("second")
    assertEquals("first", box.take())
  }

  @Test
  fun placeNeverOverwritesARestoredSpine() {
    val box = RestoredSpineBox("restored")
    box.place("late")
    assertEquals("restored", box.take())
  }
}
