// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import com.arkivanov.essenty.instancekeeper.InstanceKeeper
import com.arkivanov.essenty.instancekeeper.InstanceKeeperDispatcher
import com.arkivanov.essenty.instancekeeper.getOrCreate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/**
 * The Q2 mechanics receipt (doc 20 §8): Android workers live in the
 * RETAINED/logical scope — the component tree that survives configuration
 * change (Decompose's retained tree, `InstanceKeeper`-backed). InstanceKeeper
 * is adopted as SUBSTRATE, not API: nothing in this artifact wraps it; the app
 * hosts its `StoreHost` in an `InstanceKeeper.Instance`, exactly as below.
 * This test confirms the mechanics: rotation never crosses the worker bracket;
 * logical destruction is the one teardown.
 */
class RetainedScopeTest {

  /** The app-side shape: a retained instance owning the scope + host. */
  private class RetainedHost(scope: CoroutineScope) : InstanceKeeper.Instance {
    val scope = scope
    val host = StoreHost(scope)

    override fun onDestroy() {
      host.teardownAll()
      scope.cancel()
    }
  }

  @Test
  fun rotationNeverCrossesTheWorkerBracket() = runTest {
    val keeper = InstanceKeeperDispatcher()
    val events = mutableListOf<String>()

    fun createHost(): RetainedHost {
      val retained = keeper.getOrCreate { RetainedHost(backgroundScope) }
      return retained
    }

    // First creation (activity 1): the host adopts a worker.
    val first = createHost()
    first.host.adopt(Working {
      events.add("start")
      try {
        untilCancelled()
      } finally {
        events.add("stop")
      }
    })
    runCurrent()
    assertEquals(listOf("start"), events)
    assertEquals(1, first.host.liveWorkerCount)

    // Configuration change: the activity is recreated, the retained tree is
    // not — getOrCreate returns the SAME instance; the bracket never blinks.
    val second = createHost()
    assertSame(first, second)
    runCurrent()
    assertEquals(listOf("start"), events)
    assertEquals(1, second.host.liveWorkerCount)

    // Logical destruction (finish, not rotation): the keeper destroys retained
    // instances — the ONE teardown, LIFO through the host.
    keeper.destroy()
    runCurrent()
    assertEquals(listOf("start", "stop"), events)
    assertEquals(0, first.host.liveWorkerCount)
  }
}
