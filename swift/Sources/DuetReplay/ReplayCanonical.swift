// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// The canonical writers + decoder (contracts/serialization.md §1–§2 compact,
/// §6 pretty) — OUTSIDE any XCTest-linking target so a plain executable (the
/// replay-protocol server, the CLI) can host them. `DuetTesting`'s
/// `CanonicalJSON` delegates both halves here. This is THE §6 writer: the CLI
/// materializes every cross-flavor recording through it and the Kotlin flavor
/// ships no pretty writer at all (the on-disk form has one
/// implementation, so the flavors cannot drift). The Kotlin compact mirror must
/// still produce byte-identical strings — that half is the byte-gate currency.
public enum ReplayCanonical {
  public enum CanonicalError: Error, CustomStringConvertible {
    case nonIntegerNumber(String)
    case unsupportedValue(String)

    public var description: String {
      switch self {
      case let .nonIntegerNumber(context):
        return "Double/float values are forbidden in fixture-visible types (serialization.md §2): \(context)"
      case let .unsupportedValue(context):
        return "Unsupported JSON value: \(context)"
      }
    }
  }

  /// The canonical date form (serialization.md §2). Never mutated after
  /// configuration (DateFormatter is thread-safe once configured).
  public static let iso8601Millis: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return formatter
  }()

  public static func canonicalDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(iso8601Millis)
    return decoder
  }

  /// Encodes an `Encodable` value with the canonical scalar rules, then canonicalizes.
  public static func canonicalString<T: Encodable>(of value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(iso8601Millis.string(from: date))
    }
    let data = try encoder.encode(EncodableBox(value))
    let parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    let unwrapped = (parsed as! [Any])[0]
    return try canonicalString(fromJSONObject: unwrapped)
  }

  /// Canonicalizes an already-parsed JSON tree (`JSONSerialization` output).
  public static func canonicalString(fromJSONObject object: Any) throws -> String {
    var out = ""
    try write(object, into: &out)
    return out
  }

  /// The §6 pretty form (the on-disk fixture format): 2-space indent, canonical
  /// key order and string escaping, `": "` separators, empty composites inline,
  /// one trailing newline.
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
        writeString(key, into: &out)
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
      // Scalars share the compact writer — same escaping, UUID, and number rules.
      try write(value, into: &out)
    }
  }

  private static func write(_ value: Any, into out: inout String) throws {
    switch value {
    case let dict as [String: Any]:
      out.append("{")
      var first = true
      for key in dict.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
        if !first { out.append(",") }
        first = false
        writeString(key, into: &out)
        out.append(":")
        try write(dict[key]!, into: &out)
      }
      out.append("}")
    case let array as [Any]:
      out.append("[")
      var first = true
      for element in array {
        if !first { out.append(",") }
        first = false
        try write(element, into: &out)
      }
      out.append("]")
    case let string as String:
      writeString(string, into: &out)
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        out.append(number.boolValue ? "true" : "false")
      } else if CFNumberIsFloatType(number) {
        throw CanonicalError.nonIntegerNumber("\(number)")
      } else {
        out.append("\(number.int64Value)")
      }
    case is NSNull:
      out.append("null")
    default:
      throw CanonicalError.unsupportedValue("\(type(of: value)): \(value)")
    }
  }

  private static let uuidShape = try! NSRegularExpression(
    pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

  private static func writeString(_ rawString: String, into out: inout String) {
    let range = NSRange(rawString.startIndex..., in: rawString)
    let string =
      uuidShape.firstMatch(in: rawString, range: range) != nil
      ? rawString.lowercased() : rawString
    out.append("\"")
    for scalar in string.unicodeScalars {
      switch scalar {
      case "\"": out.append("\\\"")
      case "\\": out.append("\\\\")
      case "\n": out.append("\\n")
      case "\r": out.append("\\r")
      case "\t": out.append("\\t")
      default:
        if scalar.value < 0x20 {
          out.append(String(format: "\\u%04x", scalar.value))
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    out.append("\"")
  }
}

/// Wraps a value in a single-element array so JSONEncoder can encode scalar fragments too.
private struct EncodableBox<T: Encodable>: Encodable {
  let value: T

  init(_ value: T) {
    self.value = value
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(value)
  }
}
