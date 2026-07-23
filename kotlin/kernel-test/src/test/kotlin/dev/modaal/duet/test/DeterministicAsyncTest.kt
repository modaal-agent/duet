// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest

/** Toolkit receipts: turn control, re-send settling, the ledger, the budget. */
class DeterministicAsyncTest {

  @Test
  fun settleUntilDrainsReadyWorkAndAdvanceTimeByMovesTheClock() = runTest {
    val started = MutableStateFlow(false)
    val flag = MutableStateFlow(false)
    backgroundScope.launch {
      started.value = true
      delay(5_000)
      flag.value = true
    }
    // Ready work drains without touching the clock…
    settleUntil { started.value }
    assertEquals(false, flag.value)
    // …and virtual time is an explicit act (background timers included).
    advanceTimeBy(5_001)
    assertEquals(true, flag.value)
  }

  @Test
  fun settleByResendingCoversTheSubscriptionRace() = runTest {
    // The class-B shape: the consumer subscribes late; the first send can land
    // before the collector exists. Re-sending until projected absorbs it.
    val events = MutableSharedFlow<Int>()
    val seen = MutableStateFlow(0)
    backgroundScope.launch { events.collect { seen.value = it } }
    settle(byResending = { backgroundScope.launch { events.emit(7) } }) { seen.value == 7 }
    assertEquals(7, seen.value)
  }

  @Test
  fun childDeallocLedgerObservesRelease() {
    val ledger = ChildDeallocLedger()
    var child: Any? = Any()
    ledger.track("child", child!!)
    child = null
    ledger.assertAllReleased()
  }

  @Test
  fun wallClockBudgetPassesUnderBudget() {
    val budget = SuiteWallClockBudget(budgetMillis = 60_000)
    budget.check("DeterministicAsyncTest")
  }
}
