// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

import dev.modaal.duet.kernel.Store
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

// Shell duty 1: hosting stores means guaranteeing their teardown. Without this
// helper every composition root hand-enumerates its stores, reconcilers, and
// observations in teardown() — the forgotten-entry bug class the churn specs
// exist to catch. StoreHost turns that enumeration into registration at
// creation time: whatever the shell creates, it registers in the same breath.

/**
 * The composition root's teardown registry. `teardownAll()` unwinds in reverse
 * registration order, so registering things in creation order gives the right
 * shutdown for free: observations stop first, child reconcilers detach next,
 * the node's own stores cancel their effects last. Idempotent — a second
 * `teardownAll()` is a no-op. Swift-flavor mirror: DuetShells/StoreHost.swift.
 *
 * [scope] is the host's coroutine scope — main-confined by contract (the same
 * scope the hosted stores run on) and, per the Q2 decision, a RETAINED/logical
 * scope on Android: the host lives in the component tree that survives
 * configuration change, so rotation never crosses the worker bracket. Adopted
 * workers' `run()` coroutines launch into it; cancelling the scope is the
 * outermost teardown.
 */
class StoreHost(private val scope: CoroutineScope) {
  private val teardowns = mutableListOf<() -> Unit>()

  /**
   * The worker ledger: how many adopted workers' `run()` have not yet
   * returned. Cancellation is cooperative, so this reaches zero shortly AFTER
   * `teardownAll()` — churn specs assert it eventually-zero (a worker that
   * never settles is the leak class the ledger exists to catch).
   */
  var liveWorkerCount: Int = 0
    private set

  /**
   * Hosts a store the shell owns: registers `store.teardown()` (kernel
   * contract §3 rule 5) and hands the store back for assignment.
   */
  fun <S, A, P> host(store: Store<S, A, P>): Store<S, A, P> {
    teardowns.add { store.teardown() }
    return store
  }

  /** Registers a stack reconciler (shell duty 2) for teardown. */
  fun <K : Any, H> adopt(children: ChildStores<K, H>): ChildStores<K, H> {
    teardowns.add { children.teardownAll() }
    return children
  }

  /** Registers a modal-slot reconciler (shell duty 2) for teardown. */
  fun <K : Any, H> adopt(slot: ChildSlot<K, H>): ChildSlot<K, H> {
    teardowns.add { slot.teardownAll() }
    return slot
  }

  /**
   * Registers (and retains) an observation — a [ProjectionJoin] or
   * [StateTransitions] the shell needs alive until teardown.
   */
  fun <O : HostedObservation> adopt(observation: O): O {
    teardowns.add { observation.cancel() }
    return observation
  }

  /**
   * Adopts a worker: launches `run()` at registration and cancels it at
   * `teardownAll()`, LIFO with everything else adopted. Registration order is
   * start order — the start list is visible in one place and teardown provably
   * unwinds it in reverse. The coroutine retains the worker for the mount's
   * life; a remount adopts a fresh instance.
   */
  fun <W : Working> adopt(worker: W): W {
    liveWorkerCount += 1
    val job: Job = scope.launch { worker.run() }
    job.invokeOnCompletion { liveWorkerCount -= 1 }
    teardowns.add { job.cancel() }
    return worker
  }

  /**
   * Escape hatch for anything else that must stop at teardown. (Named, not an
   * `adopt` overload: a bare lambda would be SAM-ambiguous with [Working].)
   */
  fun adoptTeardown(teardown: () -> Unit) {
    teardowns.add(teardown)
  }

  fun teardownAll() {
    val all = teardowns.toList()
    teardowns.clear()
    for (teardown in all.reversed()) {
      teardown()
    }
  }
}

/** Something a [StoreHost] can retain and cancel at teardown. */
interface HostedObservation {
  fun cancel()
}
