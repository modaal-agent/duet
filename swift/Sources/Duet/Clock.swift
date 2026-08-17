// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// The kernel's clock seam. Effects that wait must wait through this — never
/// `Task.sleep` directly — so tests can substitute virtual time
/// (contract §5: a wall-clock sleep in a reducer or effect test is a contract violation).
///
/// Nanosecond-based (not `Duration`): the seam stays a single primitive with an
/// exact Kotlin twin (coroutine virtual time is nanosecond-based too); a
/// `Duration`-typed convenience can layer on top without touching the contract.
public protocol KernelClock: Sendable {
  /// Suspends for the given duration. Throws `CancellationError` if the
  /// surrounding task is cancelled while sleeping.
  func sleep(nanoseconds: UInt64) async throws
}

/// Wall-clock implementation for production wiring.
public struct LiveClock: KernelClock {
  public init() {}

  public func sleep(nanoseconds: UInt64) async throws {
    try await Task.sleep(nanoseconds: nanoseconds)
  }
}
