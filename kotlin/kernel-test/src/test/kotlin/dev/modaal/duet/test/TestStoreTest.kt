// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.Effect
import dev.modaal.duet.kernel.Reduced
import kotlin.test.Test
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest

/** E-rule receipts for the exhaustive TestStore on the virtual scheduler. */
class TestStoreTest {

  private sealed interface Action {
    data object Ping : Action
    data object Pong : Action
    data object Stop : Action
  }

  @Test
  fun sendReceiveExpectFinishRoundTrip() = runTest {
    val store =
      TestStore<Int, Action, String>(
        initialState = 0,
        reducer = { state, action ->
          when (action) {
            Action.Ping -> Reduced(state + 1, listOf(Effect.Run("echo", id = "t.echo")))
            Action.Pong -> Reduced(state + 10)
            Action.Stop -> Reduced(state, listOf(Effect.Cancel("t.echo")))
          }
        },
        handler = { payload ->
          when (payload) {
            "echo" -> flow { emit(Action.Pong) }
            else -> flowOf()
          }
        },
        scope = backgroundScope,
      )

    store.send(Action.Ping) { it + 1 }
    store.expectEffects(effectsOf(Effect.Run("echo", id = "t.echo")))
    store.receive(Action.Pong) { it + 10 }
    store.send(Action.Stop)
    store.expectEffects(effectsOf(Effect.Cancel("t.echo")))
    store.finish()
  }
}
