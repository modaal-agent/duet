// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetShells
import Foundation
import XCTest

/// Receipts for the generic spine carrier: deterministic same-platform round-trip,
/// tolerant decode (a stale/foreign payload restores nothing, never fails the
/// boot), and the restore box's one-shot/settled semantics.
@MainActor
final class SpineCodecTests: XCTestCase {

  private struct Spine: Codable, Equatable {
    var tab: String
    var path: [Int]
    var capturedAt: Date
  }

  func testEncodeIsDeterministicAndRoundTrips() throws {
    let spine = Spine(
      tab: "timeline", path: [1, 2, 3],
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000))

    let encoded = try XCTUnwrap(RouteSpineCodec.encode(spine))
    XCTAssertEqual(encoded, RouteSpineCodec.encode(spine), "encode must be deterministic")
    XCTAssertTrue(
      encoded.contains("2023-11-14T22:13:20.000Z"),
      "dates carry the dialect's millis form")

    let decoded: Spine? = RouteSpineCodec.decode(from: encoded)
    XCTAssertEqual(decoded, spine)
  }

  func testForeignPayloadDecodesToNilInsteadOfFailing() {
    XCTAssertNil(RouteSpineCodec.decode(Spine.self, from: "not json at all"))
    XCTAssertNil(RouteSpineCodec.decode(Spine.self, from: "{\"someOther\":\"shape\"}"))
  }

  func testRestoredSpineBoxDrainsOnceAndIgnoresLatePlacementAfterSettling() {
    let box = RestoredSpineBox<String>("restored")

    XCTAssertEqual(box.take(), "restored")
    XCTAssertNil(box.take(), "the box drains on first take")

    box.place("late")
    XCTAssertNil(box.take(), "a settled box must ignore late placement")
  }

  func testRestoredSpineBoxDiscardSettlesForever() {
    let box = RestoredSpineBox<String>("restored")
    box.discard()
    XCTAssertNil(box.take())

    box.place("late")
    XCTAssertNil(box.take())
  }

  func testRestoredSpineBoxAcceptsTheLateDeliveryPathWhenUnsettled() {
    // The iOS-26 shape: the box is built empty at scene connect, the restoration
    // activity arrives after — first placement wins.
    let box = RestoredSpineBox<String>(nil)
    box.place("late-arrival")
    box.place("second-late-arrival")
    XCTAssertEqual(box.take(), "late-arrival")
  }
}
