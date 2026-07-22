// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetReplay
import Foundation

/// The canonical JSON writer — contracts/serialization.md §1–§2. The compact half
/// (the byte-gate strings) is owned by `DuetReplay.ReplayCanonical` so XCTest-free
/// hosts (the replay-protocol server, the CLI) share the one implementation; this
/// facade delegates to it and adds the §6 pretty form (the on-disk fixture format),
/// which only the in-process recorders need. The Kotlin mirror must produce
/// byte-identical strings for both forms.
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

  // MARK: - Pretty form (§6) — the on-disk fixture format

  /// The pinned on-disk pretty form (serialization.md §6): 2-space indent, canonical key
  /// order and string escaping, `": "` separators, empty composites inline, one trailing
  /// newline. The Kotlin record mode's pretty writer must produce byte-identical
  /// files — pinned corpus-wide by PrettyWriterParityTests on both platforms.
  public static func prettyCanonicalString(fromJSONObject object: Any) throws -> String {
    var out = ""
    try writePretty(object, indent: 0, into: &out)
    out.append("\n")
    return out
  }

  private static func writePretty(_ value: Any, indent: Int, into out: inout String) throws {
    switch value {
    case let dict as [String: Any]:
      guard !dict.isEmpty else { return out.append("{}") }
      out.append("{\n")
      let pad = String(repeating: "  ", count: indent + 1)
      var first = true
      for key in dict.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
        if !first { out.append(",\n") }
        first = false
        out.append(pad)
        out.append(try ReplayCanonical.canonicalString(fromJSONObject: key))
        out.append(": ")
        try writePretty(dict[key]!, indent: indent + 1, into: &out)
      }
      out.append("\n" + String(repeating: "  ", count: indent) + "}")
    case let array as [Any]:
      guard !array.isEmpty else { return out.append("[]") }
      out.append("[\n")
      let pad = String(repeating: "  ", count: indent + 1)
      var first = true
      for element in array {
        if !first { out.append(",\n") }
        first = false
        out.append(pad)
        try writePretty(element, indent: indent + 1, into: &out)
      }
      out.append("\n" + String(repeating: "  ", count: indent) + "]")
    default:
      // Scalars share the canonical writer — same escaping, UUID, and number rules.
      out.append(try ReplayCanonical.canonicalString(fromJSONObject: value))
    }
  }
}
