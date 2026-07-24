// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetReplay
import Foundation

/// CLI-side canonical text (G1 — the CLI owns the writers for every flavor). The
/// compact form (serialization.md §1–§2, the byte-gate currency) IS the framework's
/// writer — `ReplayCanonical`, the same code the replay servers run — so the CLI
/// cannot drift from the flavor it gates. The §6 pretty writer (the on-disk fixture
/// form) lives here, proven byte-identical against the committed corpus by
/// `writer-check`; F4·S2 makes it the sole fixture writer (the per-flavor pretty
/// twins retire when `record` moves onto the protocol).
enum CanonicalText {
  /// Compact canonical string of a parsed JSON tree — the framework's own writer.
  static func canonicalString(fromJSONObject object: Any) throws -> String {
    try ReplayCanonical.canonicalString(fromJSONObject: object)
  }

  /// The §6 pretty form: two-space indent, byte-sorted keys, compact leaves, one
  /// trailing newline.
  static func prettyCanonicalString(fromJSONObject object: Any) throws -> String {
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
      out.append(try ReplayCanonical.canonicalString(fromJSONObject: value))
    }
  }
}
