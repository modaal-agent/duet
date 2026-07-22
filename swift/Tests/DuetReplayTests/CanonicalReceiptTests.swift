// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetReplay
import Foundation
import XCTest

/// Scalar-rule receipts for the compact canonical writer (serialization.md §1–§2):
/// canonical key order, the escaping whitelist, UUID lowercasing, the millis date
/// form, and the float ban.
final class CanonicalReceiptTests: XCTestCase {
  func testKeysSortByUTF8AndOutputIsCompact() throws {
    let tree: [String: Any] = ["b": 1, "a": [2, 3], "Z": ["y": true]]
    XCTAssertEqual(
      try ReplayCanonical.canonicalString(fromJSONObject: tree),
      "{\"Z\":{\"y\":true},\"a\":[2,3],\"b\":1}")
  }

  func testStringEscapingWhitelist() throws {
    XCTAssertEqual(
      try ReplayCanonical.canonicalString(fromJSONObject: "a\"b\\c\nd\u{01}e"),
      "\"a\\\"b\\\\c\\nd\\u0001e\"")
  }

  func testUUIDShapedStringsLowercase() throws {
    XCTAssertEqual(
      try ReplayCanonical.canonicalString(
        fromJSONObject: "0B7C46B0-3B7A-4E96-AD9C-8E0F9E0B1234"),
      "\"0b7c46b0-3b7a-4e96-ad9c-8e0f9e0b1234\"")
    XCTAssertEqual(
      try ReplayCanonical.canonicalString(fromJSONObject: "not-a-uuid-just-dashes"),
      "\"not-a-uuid-just-dashes\"")
  }

  func testDatesEncodeInTheMillisForm() throws {
    struct Stamped: Codable {
      var at: Date
    }
    XCTAssertEqual(
      try ReplayCanonical.canonicalString(
        of: Stamped(at: Date(timeIntervalSince1970: 1_700_000_000))),
      "{\"at\":\"2023-11-14T22:13:20.000Z\"}")
  }

  func testFloatsAreForbidden() {
    XCTAssertThrowsError(
      try ReplayCanonical.canonicalString(fromJSONObject: ["x": 1.5])
    ) { error in
      guard case ReplayCanonical.CanonicalError.nonIntegerNumber = error else {
        return XCTFail("expected nonIntegerNumber, got \(error)")
      }
    }
  }

  func testNullAndBoolScalars() throws {
    XCTAssertEqual(
      try ReplayCanonical.canonicalString(fromJSONObject: ["n": NSNull(), "t": true]),
      "{\"n\":null,\"t\":true}")
  }
}
