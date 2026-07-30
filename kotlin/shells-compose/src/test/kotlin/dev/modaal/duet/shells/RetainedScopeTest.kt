// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import com.arkivanov.essenty.instancekeeper.InstanceKeeperDispatcher
import com.arkivanov.essenty.instancekeeper.getOrCreate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.isActive
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/**
 * The Q2 mechanics receipt (doc 20 §8): Android workers live in the
 * RETAINED/logical scope — the component tree that survives configuration
 * change (Decompose's retained tree, `InstanceKeeper`-backed). The 2026-07-30
 * graduation review promoted the receipt shape to API: [RetainedRoot] is
 * that shape, and essenty moved from test-scope substrate to an `api`
 * dependency with it. This test confirms the mechanics through the graduated
 * type: rotation never crosses the worker bracket; logical destruction is
 * the one teardown, and the component unwinds on a still-live scope.
 */
class RetainedScopeTest {

  /** The app-side composition-root stand-in: a host plus a teardown probe. */
  private class Component(scope: CoroutineScope) {
    val host = StoreHost(scope)
  }

  @Test
  fun rotationNeverCrossesTheWorkerBracket() = runTest {
    val keeper = InstanceKeeperDispatcher()
    val events = mutableListOf<String>()
    val dispatcher = StandardTestDispatcher(testScheduler)
    lateinit var root: RetainedRoot<Component>

    fun createRoot(): RetainedRoot<Component> {
      root =
        keeper.getOrCreate {
          RetainedRoot(dispatcher, { component ->
            // The order pin: the component tears down BEFORE the scope is
            // cancelled — a dead scope here would strand cooperative unwind.
            events.add("teardown scopeAlive=${root.scope.coroutineContext.isActive}")
            component.host.teardownAll()
          }) { scope ->
            Component(scope)
          }
        }
      return root
    }

    // First creation (activity 1): the component adopts a worker.
    val first = createRoot()
    first.component.host.adopt(Working {
      events.add("start")
      try {
        untilCancelled()
      } finally {
        events.add("stop")
      }
    })
    runCurrent()
    assertEquals(listOf("start"), events)
    assertEquals(1, first.component.host.liveWorkerCount)

    // Configuration change: the activity is recreated, the retained tree is
    // not — getOrCreate returns the SAME instance; the bracket never blinks.
    val second = createRoot()
    assertSame(first, second)
    runCurrent()
    assertEquals(listOf("start"), events)
    assertEquals(1, second.component.host.liveWorkerCount)

    // Logical destruction (finish, not rotation): the keeper destroys retained
    // instances — the ONE teardown, LIFO through the host.
    keeper.destroy()
    runCurrent()
    assertEquals(listOf("start", "teardown scopeAlive=true", "stop"), events)
    assertEquals(0, first.component.host.liveWorkerCount)
  }
}
