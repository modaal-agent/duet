// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetReplay
import Foundation

/// The canonical JSON writer facade — contracts/serialization.md §1–§2 compact and
/// §6 pretty. Both halves are owned by `DuetReplay.ReplayCanonical` (the ONE
/// implementation, shared with the replay-protocol server and the `duet` CLI);
/// this facade only spares test code the extra import. The Kotlin flavor
/// mirrors the compact half byte-identically (the byte-gate currency) and ships
/// no pretty writer at all — the on-disk form has one implementation.
public enum CanonicalJSON {
  public typealias CanonicalError = ReplayCanonical.CanonicalError

  /// Canonicalizes an already-parsed JSON tree (`JSONSerialization` output).
  public static func canonicalString(fromJSONObject object: Any) throws -> String {
    try ReplayCanonical.canonicalString(fromJSONObject: object)
  }

  /// Encodes an `Encodable` value with the canonical scalar rules, then canonicalizes.
  public static func canonicalString<T: Encodable>(of value: T) throws -> String {
    try ReplayCanonical.canonicalString(of: value)
  }

  /// The canonical date form (serialization.md §2) — shared with FixtureRunner's decoder.
  public static var iso8601Millis: DateFormatter { ReplayCanonical.iso8601Millis }

  /// The pinned on-disk pretty form (serialization.md §6) — see
  /// `ReplayCanonical.prettyCanonicalString`.
  public static func prettyCanonicalString(fromJSONObject object: Any) throws -> String {
    try ReplayCanonical.prettyCanonicalString(fromJSONObject: object)
  }
}
