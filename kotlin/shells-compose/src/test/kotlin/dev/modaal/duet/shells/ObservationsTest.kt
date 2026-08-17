// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/** Projection-join + transition-pair receipts, and the registry's sealed-root resolution. */
class ObservationsTest {

  @Test
  fun projectionJoinReAppliesWhenTheAuxSourceLands() = runTest {
    val state = MutableStateFlow("state-1")
    val aux = MutableSharedFlow<Int>()
    val applied = mutableListOf<Pair<String, Int>>()

    val join =
      ProjectionJoin(backgroundScope, state, aux, initialAux = 0) { s, a ->
        applied.add(s to a)
      }
    runCurrent()
    // Project thin against initialAux…
    assertEquals(listOf("state-1" to 0), applied)

    // …self-heal when the aux source lands, and re-apply on state moves.
    aux.emit(42)
    runCurrent()
    state.value = "state-2"
    runCurrent()
    assertEquals(listOf("state-1" to 0, "state-1" to 42, "state-2" to 42), applied)
    assertEquals(42, join.aux)

    join.cancel()
    state.value = "state-3"
    runCurrent()
    assertEquals(3, applied.size)
  }

  @Test
  fun stateTransitionsDeliverPairsWithACurrentCurrentFirst() = runTest {
    val state = MutableStateFlow(1)
    val pairs = mutableListOf<Pair<Int, Int>>()
    val transitions =
      StateTransitions(backgroundScope, state) { old, new -> pairs.add(old to new) }
    runCurrent()
    state.value = 2
    runCurrent()
    state.value = 2 // duplicate — filtered
    state.value = 5
    runCurrent()
    assertEquals(listOf(1 to 1, 1 to 2, 2 to 5), pairs)
    transitions.cancel()
  }

  sealed interface SheetKind {
    data class Edit(val id: Int) : SheetKind
    data object About : SheetKind
  }

  @Test
  fun presentationRegistryResolvesSealedLeavesThroughTheRootRegistration() {
    val registry = PresentationRegistry<String>()
    registry.register(SheetKind::class) { kind ->
      when (kind) {
        is SheetKind.Edit -> "edit-${kind.id}"
        SheetKind.About -> null // declined — child not reconciled yet
      }
    }
    assertEquals("edit-7", registry.surfaceFor(SheetKind.Edit(7)))
    assertNull(registry.surfaceFor(SheetKind.About))
    assertNull(registry.surfaceFor("unregistered kind type"))
  }
}
