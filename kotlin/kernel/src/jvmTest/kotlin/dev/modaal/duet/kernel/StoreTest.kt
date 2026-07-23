// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/**
 * Artifact-level smoke receipts for the Store runtime. The kernel's contract
 * rules are pinned exhaustively by the kernel-trace fixtures (G3, :kernel-test);
 * these receipts prove the published artifact runs them at all.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class StoreTest {

  private sealed interface Action {
    data object Inc : Action
    data object StartTick : Action
    data object CancelTick : Action
    data object Ticked : Action
    data object Burst : Action
    data object B1 : Action
    data object B2 : Action
  }

  private fun makeStore(scope: kotlinx.coroutines.CoroutineScope): Store<Int, Action, String> =
    Store(
      initialState = 0,
      reducer = { state, action ->
        when (action) {
          Action.Inc -> Reduced(state + 1)
          Action.StartTick -> Reduced(state, listOf(Effect.Run("tick", id = "clock")))
          Action.CancelTick -> Reduced(state, listOf(Effect.Cancel("clock")))
          Action.Ticked -> Reduced(state + 10)
          Action.Burst -> Reduced(state, listOf(Effect.Run("burst")))
          Action.B1 -> Reduced(state + 100)
          Action.B2 -> Reduced(state + 10)
        }
      },
      handler = { payload ->
        when (payload) {
          "tick" ->
            flow {
              kotlinx.coroutines.delay(100)
              emit(Action.Ticked)
            }
          "burst" -> flowOf(Action.B1, Action.B2)
          else -> flowOf()
        }
      },
      scope = scope,
    )

  @Test
  fun sendReducesSynchronously() = runTest {
    val store = makeStore(backgroundScope)
    store.send(Action.Inc)
    assertEquals(1, store.state.value)
  }

  @Test
  fun cancelInFlightSuppressesThePendingTick() = runTest {
    val store = makeStore(backgroundScope)
    store.send(Action.StartTick)
    advanceTimeBy(50)
    store.send(Action.CancelTick)
    advanceTimeBy(200)
    runCurrent()
    assertEquals(0, store.state.value)
  }

  @Test
  fun teardownCancelsTheLiveEffect() = runTest {
    val store = makeStore(backgroundScope)
    store.send(Action.StartTick)
    store.teardown()
    advanceTimeBy(200)
    runCurrent()
    assertEquals(0, store.state.value)
  }

  @Test
  fun reentrantDeliveriesQueueAsFlatOrderedCycles() = runTest {
    val store = makeStore(backgroundScope)
    store.send(Action.Burst)
    runCurrent()
    assertEquals(110, store.state.value)
  }
}
