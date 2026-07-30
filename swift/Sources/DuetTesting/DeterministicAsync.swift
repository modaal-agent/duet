// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import XCTest

// The deterministic-async toolkit v1 (spec 15 §6.3): async test code must be
// deterministic BY CONSTRUCTION — R3's no-wall-clock rule extended to test
// helpers, with the corpus's flake-class fixes productized so the deterministic
// shape is the path of least resistance. A test that flakes under virtual time
// is a bug, never a bound-widening opportunity.

/// Suite-wide polling defaults as a TYPE (flake registry: suite-wide 3 s):
/// the framework is assertion-library-agnostic, so these are the VALUES —
/// a Nimble/Quick suite feeds them into `PollingDefaults` (its config type),
/// an XCTest suite into its expectation timeouts. One source, no per-test
/// bound widening.
public enum SuitePollingDefaults {
  /// The settled-host upper bound for an eventually-assertion.
  public static let timeout: TimeInterval = 3.0
  public static let pollInterval: TimeInterval = 0.01
}

/// Turn control: yields until `condition` holds, bounded — settling is an API
/// call, not a poll. Wall-clock-free by construction; a false condition
/// surfaces as the caller's assertion, never a hang. Returns whether the
/// condition held within the budget.
@discardableResult
public func settleUntil(
  _ condition: () -> Bool, maxYields: Int = 10_000
) async -> Bool {
  var budget = maxYields
  while !condition() && budget > 0 {
    await Task.yield()
    budget -= 1
  }
  return condition()
}

/// The re-send-until-projected pattern (flake registry class B, the InviteCode
/// fix, productized): a subscription that attaches on its own task can miss the
/// first emission, so the test RE-SENDS the stimulus each settle round until
/// the projection lands — no sleeps, no bound widening. Returns whether the
/// projection held within the budget.
@discardableResult
public func settle(
  byResending resend: () -> Void,
  until projected: () -> Bool,
  maxRounds: Int = 100,
  yieldsPerRound: Int = 100
) async -> Bool {
  var rounds = maxRounds
  while rounds > 0 {
    resend()
    if await settleUntil(projected, maxYields: yieldsPerRound) { return true }
    rounds -= 1
  }
  return projected()
}

/// The churn-ledger assertion (`ChildDeallocLedger`-class), first-class: track
/// every mounted child object weakly; after churn, `liveCount` must reach zero
/// — a leaked-RETAINED child fails, strictly stronger than balanced
/// attach/detach counts (the LeakDetector handover, productized from the
/// reference adopter’s churn specs).
public final class ChildDeallocLedger {
  private struct WeakBox {
    weak var object: AnyObject?
  }

  private var boxes: [WeakBox] = []
  public private(set) var trackedCount = 0

  public init() {}

  /// Identity-deduped against the LIVE tracked set, so re-reading the same
  /// mounted object twice can't double-count.
  public func track(_ object: AnyObject?) {
    guard let object else { return }
    guard !boxes.contains(where: { $0.object === object }) else { return }
    trackedCount += 1
    boxes.append(WeakBox(object: object))
  }

  public var liveCount: Int { boxes.filter { $0.object != nil }.count }
}

/// Environment health (the flake registry's env-check discipline, opt-in): the
/// degraded-run signature is suite wall-time far above the settled budget — a
/// stale simulator / loaded host should read as a DIAGNOSTIC, not a red test
/// that tempts bound widening. Start it in the suite's setup, assert in
/// teardown; a breach emits the diagnostic without failing unless asked.
public final class SuiteWallClockBudget: @unchecked Sendable {
  private let start = Date()
  private let budget: TimeInterval

  /// `budget` — the settled-host wall-time for the suite (measure it green,
  /// then pin ~3× as the degraded signature).
  public init(budget: TimeInterval) {
    self.budget = budget
  }

  public var elapsed: TimeInterval { Date().timeIntervalSince(start) }
  public var isDegraded: Bool { elapsed > budget }

  /// Emits the degraded-host diagnostic; fails the test only when
  /// `failOnBreach` (default false — the signature usually means "fix the
  /// environment", not "the code broke").
  public func assertBudget(
    failOnBreach: Bool = false, file: StaticString = #filePath, line: UInt = #line
  ) {
    guard isDegraded else { return }
    let message = """
      Suite wall-time \(String(format: "%.1f", elapsed))s exceeded the settled \
      budget \(String(format: "%.1f", budget))s — the degraded-host signature. \
      Check the environment (stale simulator at 100% CPU, host load) before \
      trusting red tests; never widen bounds (flake-registry rule).
      """
    if failOnBreach {
      XCTFail(message, file: file, line: line)
    } else {
      print("[SuiteWallClockBudget] \(message)")
    }
  }
}
