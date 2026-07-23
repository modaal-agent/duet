// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/** Host receipts: LIFO teardown, idempotence, the worker bracket + ledger. */
class StoreHostTest {

  @Test
  fun teardownUnwindsInReverseRegistrationOrder() = runTest {
    val host = StoreHost(backgroundScope)
    val order = mutableListOf<String>()
    host.adoptTeardown { order.add("first") }
    host.adoptTeardown { order.add("second") }
    host.adoptTeardown { order.add("third") }
    host.teardownAll()
    assertEquals(listOf("third", "second", "first"), order)
    host.teardownAll()
    assertEquals(3, order.size)
  }

  @Test
  fun workersStartInRegistrationOrderAndUnwindWithTheHost() = runTest {
    val host = StoreHost(backgroundScope)
    val events = mutableListOf<String>()

    fun worker(name: String) = Working {
      events.add("start:$name")
      try {
        untilCancelled()
      } finally {
        events.add("stop:$name")
      }
    }

    host.adopt(worker("a"))
    host.adopt(worker("b"))
    runCurrent()
    assertEquals(listOf("start:a", "start:b"), events)
    assertEquals(2, host.liveWorkerCount)

    host.teardownAll()
    runCurrent()
    assertEquals(listOf("start:a", "start:b", "stop:b", "stop:a"), events)
    assertEquals(0, host.liveWorkerCount)
  }

  @Test
  fun observationsStopBeforeWorkersOnTeardown() = runTest {
    val host = StoreHost(backgroundScope)
    val order = mutableListOf<String>()
    host.adopt(Working {
      try {
        untilCancelled()
      } finally {
        order.add("worker")
      }
    })
    host.adopt(
      object : HostedObservation {
        override fun cancel() {
          order.add("observation")
        }
      })
    runCurrent()
    host.teardownAll()
    runCurrent()
    assertEquals(listOf("observation", "worker"), order)
  }
}
