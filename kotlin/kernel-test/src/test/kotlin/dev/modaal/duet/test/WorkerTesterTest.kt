// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.shells.Working
import dev.modaal.duet.shells.untilCancelled
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest

/** The worker harness receipts: bracket, drive, settle. */
class WorkerTesterTest {

  /** A subscription-shaped worker: collects a fake gateway stream into an output state. */
  private class EchoWorker(
    private val input: MutableSharedFlow<Int>,
  ) : Working {
    val seen = MutableStateFlow<List<Int>>(emptyList())

    override suspend fun run() {
      input.collect { value -> seen.value = seen.value + value }
    }
  }

  @Test
  fun driveFakesThenFinishSettles() = runTest {
    val input = MutableSharedFlow<Int>()
    val worker = EchoWorker(input)
    val tester = WorkerTester(worker)
    tester.start(backgroundScope)

    settleUntil { input.subscriptionCount.value == 1 }
    input.emit(1)
    input.emit(2)
    settleUntil { worker.seen.value == listOf(1, 2) }

    tester.finish()
    assertTrue(tester.isFinished)
  }

  @Test
  fun parkedWorkerSettlesViaUntilCancelled() = runTest {
    var entered = false
    var releases = 0
    val worker = Working {
      entered = true
      try {
        untilCancelled()
      } finally {
        releases += 1
      }
    }
    val tester = WorkerTester(worker)
    tester.start(backgroundScope)
    // Drain the start first: a coroutine cancelled before it ever dispatches
    // never runs its body (unlike a Swift Task) — the park must be reached for
    // the release path to be the thing under test.
    settleUntil { entered }
    tester.finish()
    assertEquals(1, releases)
  }
}
