// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Duet
import DuetTesting
import Foundation
import XCTest

/// The kernel-trace fixtures (Swift side): the contract-observable runtime
/// rules recorded as replayable canonical traces under virtual time. The Kotlin
/// kernel reproduces these; contract text: contracts/kernel-trace-v0.md.
/// Regenerate with REGEN_FIXTURES=1 (the corpus rule: the fixture diff is the
/// review artifact).
@MainActor
final class KernelTraceTests: XCTestCase {

  // The scripted trace feature: an Int counter with string verbs — small
  // enough that every canonical payload is readable in the fixture.
  typealias Recorder = KernelTraceRecorder<Int, String, String>

  private func makeRecorder() -> Recorder {
    Recorder(
      initialState: 0,
      reducer: { state, action in
        switch action {
        case "inc":
          state += 1
          return []
        case "start-ping":
          return [.run("ping")]
        case "start-two":
          return [.run("alpha"), .run("beta")]
        case "start-clocked":
          return [.run("tick", id: "clock")]
        case "cancel-clock":
          return [.cancel(id: "clock")]
        case "start-park":
          return [.run("park")]
        case "burst":
          return [.run("burst")]
        case "pong", "ticked", "b2", "chain-done":
          state += 10
          return []
        case "b1":
          state += 100
          return []
        case "start-chain":
          return [.run("chained")]
        default:
          return []
        }
      },
      handler: { payload, clock in
        switch payload {
        case "ping":
          return AsyncStream { continuation in
            continuation.yield("pong")
            continuation.finish()
          }
        case "alpha":
          return AsyncStream { $0.finish() }
        case "beta":
          // Finishes on the clock, one advance later — cross-effect ending
          // order within one settle window is CONTRACT-UNDEFINED (the trace
          // design's one-ending-per-window rule; kernel-trace-v0.md §3).
          return AsyncStream { continuation in
            let task = Task {
              try? await clock.sleep(nanoseconds: 50_000_000)
              continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
          }
        case "tick":
          return AsyncStream { continuation in
            let task = Task {
              try? await clock.sleep(nanoseconds: 100_000_000)
              if !Task.isCancelled { continuation.yield("ticked") }
              continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
          }
        case "park":
          return AsyncStream { continuation in
            let task = Task {
              try? await clock.sleep(nanoseconds: 10_000_000_000)
              continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
          }
        case "burst":
          return AsyncStream { continuation in
            continuation.yield("b1")
            continuation.yield("b2")
            continuation.finish()
          }
        case "chained":
          return AsyncStream { continuation in
            continuation.yield("chain-done")
            continuation.finish()
          }
        default:
          return AsyncStream { $0.finish() }
        }
      })
  }

  // MARK: - The six rule traces

  func testSendReduceSynchronous() async throws {
    let recorder = makeRecorder()
    await recorder.send("inc")
    await recorder.send("inc")
    await recorder.teardown()
    try verify(recorder, fixture: "send-reduce-sync")
  }

  func testEffectStartOrderIsDeclarationOrder() async throws {
    let recorder = makeRecorder()
    await recorder.send("start-two")
    // alpha ends immediately; beta ends after the advance — each ending in
    // its own settle window (cross-effect ending order is contract-undefined).
    await recorder.advance(byNanoseconds: 50_000_000)
    await recorder.teardown()
    try verify(recorder, fixture: "effect-start-order")
  }

  func testEffectRoundTripDeliversThroughTheQueue() async throws {
    let recorder = makeRecorder()
    await recorder.send("start-ping")
    await recorder.teardown()
    try verify(recorder, fixture: "effect-roundtrip")
  }

  func testCancelInFlightByIdAndSameIdRestart() async throws {
    let recorder = makeRecorder()
    await recorder.send("start-clocked")
    await recorder.advance(byNanoseconds: 50_000_000)
    await recorder.send("cancel-clock")
    await recorder.advance(byNanoseconds: 100_000_000)  // nothing may fire
    await recorder.send("start-clocked")
    await recorder.send("start-clocked")  // same-id restart cancels the first
    await recorder.advance(byNanoseconds: 100_000_000)  // exactly one tick
    await recorder.teardown()
    try verify(recorder, fixture: "cancel-in-flight")
  }

  func testTeardownCancelsEverything() async throws {
    // ONE live effect at teardown: pinning cancellation + post-teardown
    // silence byte-exactly. Multi-effect teardown (LIFO unwind) stays a
    // per-platform TestStore assertion — cross-effect ending order within one
    // window is contract-undefined (the §2.1 fallback, applied at trace-design
    // grain).
    let recorder = makeRecorder()
    await recorder.send("start-park")
    await recorder.teardown()
    await recorder.advance(byNanoseconds: 200_000_000)  // silence after teardown
    try verify(recorder, fixture: "teardown-cancels")
  }

  func testReentrancyQueuesNeverNests() async throws {
    let recorder = makeRecorder()
    // Two back-to-back yields from one effect: each delivery is its own flat
    // send→reduce cycle, in yield order — queued, never nested. (The chained
    // hop is a SEPARATE scripted step: two independent async sources racing
    // for the executor would pin incidental scheduling, not the rule.)
    await recorder.send("burst")
    await recorder.send("start-chain")
    await recorder.teardown()
    try verify(recorder, fixture: "reentrancy-queue")
  }

  // MARK: - The byte gate

  private func verify(
    _ recorder: Recorder, fixture: String,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let url = Self.fixturesDirectory.appendingPathComponent("\(fixture).trace.jsonl")
    let produced = recorder.canonicalTrace()
    if ProcessInfo.processInfo.environment["REGEN_FIXTURES"] == "1" {
      try FileManager.default.createDirectory(
        at: Self.fixturesDirectory, withIntermediateDirectories: true)
      try produced.write(to: url, atomically: true, encoding: .utf8)
      print("KernelTraceTests: recorded \(fixture).trace.jsonl (\(recorder.events.count) events)")
    }
    let committed = try String(contentsOf: url, encoding: .utf8)
    XCTAssertEqual(
      produced, committed,
      "kernel trace '\(fixture)' diverged from the committed fixture — a kernel "
        + "behavior change; regenerate with REGEN_FIXTURES=1 and review the diff",
      file: file, line: line)
  }

  private static var fixturesDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()   // DuetTestingTests
      .deletingLastPathComponent()   // Tests
      .appendingPathComponent("parity/fixtures/kernel-trace")
  }
}
