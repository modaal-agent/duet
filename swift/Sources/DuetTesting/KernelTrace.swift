// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Duet
import Foundation

// G3 (spec 18 §2.1) — kernel-trace fixtures: the corpus methodology extended to
// the KERNEL itself. The contract-observable runtime rules (synchronous
// send→reduce, effect start order, cancel-by-id, teardown-cancels-everything,
// reentrancy queueing, virtual-time ordering) are recorded as replayable traces
// both kernel flavors must reproduce under virtual time — machine-verifying
// what the twin TestStores pin per platform by assertion. Contract:
// contracts/kernel-trace-v0.md (v0 — frozen at F3 exit with the Kotlin traces).

/// One observable kernel event, in trace order. Payload strings are canonical
/// JSON (contracts/serialization.md) so the trace itself is byte-comparable.
public enum KernelTraceEvent: Equatable {
  /// The test scripted a send (the stimulus boundary — everything below is the
  /// kernel's response).
  case send(action: String)
  /// The reducer ran for `action`; `state` is the canonical post-reduce state.
  /// Ordering receipt: every `send`/`effectAction` is followed by its `reduce`
  /// BEFORE any nested reduce — the synchronous send→reduce + queued
  /// reentrancy rules, visible as a flat (never nested) event stream.
  case reduce(action: String, state: String)
  /// The handler was invoked for `payload` (the effect's task started).
  case effectStart(payload: String, id: String?)
  /// An effect's stream yielded `action` back into the store.
  case effectAction(action: String)
  /// An effect's stream terminated by cancellation (cancel-by-id, a
  /// same-id restart, or teardown).
  case effectCancelled(payload: String)
  /// An effect's stream ran to completion.
  case effectFinished(payload: String)
  /// The test advanced the virtual clock.
  case advance(nanoseconds: UInt64)
  /// The test tore the store down.
  case teardown
}

extension KernelTraceEvent {
  /// One canonical JSON line per event (jsonl — the fixture's byte form).
  public var canonicalLine: String {
    func line(_ object: [String: Any]) -> String {
      (try? CanonicalJSON.canonicalString(fromJSONObject: object)) ?? "{\"error\":true}"
    }
    switch self {
    case let .send(action):
      return line(["event": "send", "action": action])
    case let .reduce(action, state):
      return line(["event": "reduce", "action": action, "state": state])
    case let .effectStart(payload, id):
      return line(["event": "effectStart", "payload": payload, "id": id ?? NSNull()])
    case let .effectAction(action):
      return line(["event": "effectAction", "action": action])
    case let .effectCancelled(payload):
      return line(["event": "effectCancelled", "payload": payload])
    case let .effectFinished(payload):
      return line(["event": "effectFinished", "payload": payload])
    case let .advance(nanoseconds):
      return line(["event": "advance", "nanoseconds": nanoseconds])
    case .teardown:
      return line(["event": "teardown"])
    }
  }
}

/// Records a kernel trace by wrapping a feature's reducer and handler around a
/// REAL `Store` under a `TestClock`. Effect-side events are appended through a
/// lock (stream termination fires from the cancelling context); scripted steps
/// settle before returning so traces are deterministic by construction.
@MainActor
public final class KernelTraceRecorder<
  State: Equatable & Encodable, Action: Equatable & Encodable, Payload: Equatable & Encodable
> {
  public let clock = TestClock()
  public private(set) var store: Store<State, Action, Payload>!

  private let log = EventLog()

  public init(
    initialState: State,
    reducer: @escaping (inout State, Action) -> [Effect<Payload>],
    handler: @escaping (Payload, TestClock) -> AsyncStream<Action>
  ) {
    let log = self.log
    let clock = self.clock
    self.store = Store(
      initialState: initialState,
      reducer: { state, action in
        let effects = reducer(&state, action)
        log.append(.reduce(action: canonical(action), state: canonical(state)))
        return effects
      },
      handler: { payload in
        log.append(.effectStart(payload: canonical(payload), id: nil))
        let upstream = handler(payload, clock)
        // Re-wrap so yields and endings are observable in trace order. Two
        // determinism rules make the trace canonical rather than scheduling-
        // shaped: (1) LOCKSTEP forwarding — after yielding an action, wait for
        // its reduce to land before forwarding the next, so delivery order in
        // the trace IS reduce order (the contract's meaningful ordering; a
        // free-running forwarder races the store's consuming task); (2) the
        // ending is logged in ONE place, the wrapper task's tail, after the
        // last lockstep round.
        return AsyncStream { continuation in
          let task = Task { @MainActor in
            for await action in upstream {
              // Canonicalize BEFORE the yield sends the value away (region
              // isolation): the lockstep loop only touches the Sendable string.
              let canonicalAction = canonical(action)
              let mark = log.count
              log.append(.effectAction(action: canonicalAction))
              // The element is forwarded exactly once and never touched again
              // — the lockstep loop below reads only the canonical string.
              // Swift 6.4 proves that unaided; the GA line's 6.3 sending
              // analysis (Xcode 26.x) merges the element's region with the
              // task's captures and reports a phantom use-after-send at the
              // yield. The unsafe binding suppresses exactly that false
              // positive so DuetTesting keeps compiling on GA toolchains —
              // the adopter floor. Remove when the floor moves past 6.3.
              nonisolated(unsafe) let transferred = action
              continuation.yield(transferred)
              var budget = 10_000
              while !Task.isCancelled && budget > 0
                && !log.containsReduce(of: canonicalAction, atOrAfter: mark) {
                await Task.yield()
                budget -= 1
              }
            }
            if Task.isCancelled {
              log.append(.effectCancelled(payload: canonical(payload)))
            } else {
              log.append(.effectFinished(payload: canonical(payload)))
            }
            continuation.finish()
          }
          continuation.onTermination = { _ in
            task.cancel()
          }
        }
      })
  }

  /// Scripted send: logs the stimulus, sends, then settles to QUIESCENCE so
  /// every kernel response that can land does before the next step — a fixed
  /// yield count is not deterministic under host load; "no new events across
  /// consecutive drain rounds" is.
  public func send(_ action: Action) async {
    log.append(.send(action: canonical(action)))
    store.send(action)
    await settleQuiescent()
  }

  public func advance(byNanoseconds delta: UInt64) async {
    log.append(.advance(nanoseconds: delta))
    await clock.advance(byNanoseconds: delta)
    await settleQuiescent()
  }

  public func teardown() async {
    log.append(.teardown)
    store.teardown()
    await settleQuiescent()
  }

  /// Drains until the trace is stable for `stableRounds` consecutive
  /// mega-yield rounds (bounded): pending clocked sleeps produce no events
  /// until advanced, so stability — not idleness — is the quiescence signal.
  private func settleQuiescent(stableRounds: Int = 3, maxRounds: Int = 200) async {
    var streak = 0
    var rounds = 0
    var lastCount = log.count
    while streak < stableRounds && rounds < maxRounds {
      await Task.megaYield()
      rounds += 1
      let count = log.count
      if count == lastCount {
        streak += 1
      } else {
        streak = 0
        lastCount = count
      }
    }
  }

  public var events: [KernelTraceEvent] { log.snapshot() }

  /// The fixture's byte form: one canonical JSON line per event + trailing \n.
  public func canonicalTrace() -> String {
    log.snapshot().map(\.canonicalLine).joined(separator: "\n") + "\n"
  }
}

private func canonical<T: Encodable>(_ value: T) -> String {
  (try? CanonicalJSON.canonicalString(of: value)) ?? "<encoding-error>"
}

/// Lock-guarded event log — effect terminations append from the cancelling
/// context; everything else from the main actor.
private final class EventLog: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [KernelTraceEvent] = []

  func append(_ event: KernelTraceEvent) {
    lock.lock()
    events.append(event)
    lock.unlock()
  }

  func snapshot() -> [KernelTraceEvent] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return events.count
  }

  /// Lockstep support: has `action`'s reduce landed at or after `index`?
  func containsReduce(of action: String, atOrAfter index: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard index < events.count else { return false }
    return events[index...].contains { event in
      if case let .reduce(reduced, _) = event { return reduced == action }
      return false
    }
  }
}
