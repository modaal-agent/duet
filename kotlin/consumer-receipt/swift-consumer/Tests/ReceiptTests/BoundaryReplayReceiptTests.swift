// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetReceipt
import Foundation
import XCTest

/// The packaging receipt: the committed kotlin-corpus lamp fixtures replay
/// across the SKIE/XCFramework boundary. Every canonical byte compared here is
/// produced by the CORE's own machinery (the framework's serializers, pinned
/// configuration, and writer) — Swift only loads the files, threads the steps,
/// and byte-compares. The same files gate the JVM host lane; one corpus, two
/// transports.
final class BoundaryReplayReceiptTests: XCTestCase {

  func testLampFixturesReplayAcrossTheBoundary() throws {
    let fixtures = ["lamp.dimmed-evening", "lamp.timed-off"]
    var steps = 0
    for fixture in fixtures {
      let url = Self.fixturesDirectory.appendingPathComponent("\(fixture).fixture.json")
      let document =
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
      let initialState = try Self.compactString(document["initialState"]!)
      let session = LampBoundary.shared.makeSession(initialStateJson: initialState)

      for rawStep in document["steps"] as! [[String: Any]] {
        let action = try Self.compactString(rawStep["action"]!)
        let result = session.step(actionJson: action)
        let expectedState =
          LampBoundary.shared.canonicalize(rawJson: try Self.compactString(rawStep["expectedState"]!))
        let expectedEffects =
          LampBoundary.shared.canonicalize(rawJson: try Self.compactString(rawStep["expectedEffects"]!))
        XCTAssertEqual(result.stateCanonical, expectedState, "\(fixture): state diverged")
        XCTAssertEqual(result.effectsCanonical, expectedEffects, "\(fixture): effects diverged")
        steps += 1
      }
    }
    XCTAssertGreaterThan(steps, 0, "no steps replayed — fixture loading is broken")
  }

  private static func compactString(_ tree: Any) throws -> String {
    String(
      decoding: try JSONSerialization.data(withJSONObject: tree, options: [.fragmentsAllowed]),
      as: UTF8.self)
  }

  private static var fixturesDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // → ReceiptTests/
      .deletingLastPathComponent()  // → Tests/
      .deletingLastPathComponent()  // → swift-consumer/
      .deletingLastPathComponent()  // → consumer-receipt/
      .deletingLastPathComponent()  // → kotlin/
      .appendingPathComponent("parity/fixtures")
  }
}
