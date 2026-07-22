// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Duet
import DuetReplay
import Foundation
import XCTest

/// Protocol receipts against `respond(toLine:)` — the pure request handler the
/// stdio loop wraps — so the seam is pinned without a subprocess.
final class ReplayServerTests: XCTestCase {

  private struct MiniState: Equatable, Codable, Sendable {
    var count: Int = 0
  }

  private enum MiniAction: Equatable, Codable, Sendable {
    case bump

    private enum CodingKeys: String, CodingKey {
      case caseName = "case"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      switch try container.decode(String.self, forKey: .caseName) {
      case "bump": self = .bump
      case let other:
        throw DecodingError.dataCorruptedError(
          forKey: .caseName, in: container, debugDescription: "Unknown MiniAction '\(other)'")
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("bump", forKey: .caseName)
    }
  }

  private var registry: ReplayRegistry {
    ReplayRegistry([
      ReplayFeature.entry(
        "mini", MiniState.self, MiniAction.self,
        { (state: inout MiniState, _: MiniAction) -> [Effect<String>] in
          state.count += 1
          return [.run("ping", id: "mini.ping")]
        })
    ])
  }

  func testHandshakeNamesProtocolVersionPlatformAndFeatures() {
    let handshake = ReplayServer.handshake(registry: registry)
    XCTAssertEqual(handshake["protocol"] as? String, "duet-replay")
    XCTAssertEqual(handshake["version"] as? Int, 0)
    XCTAssertEqual(handshake["platform"] as? String, "swift")
    XCTAssertEqual(handshake["features"] as? [String], ["mini"])
  }

  func testReduceReturnsCanonicalStateAndEffects() throws {
    let line = """
      {"op":"reduce","feature":"mini","state":{"count":41},"action":{"case":"bump"}}
      """
    let response = try XCTUnwrap(ReplayServer.respond(toLine: line, registry: registry))
    XCTAssertEqual(response["state"] as? String, "{\"count\":42}")
    XCTAssertEqual(
      response["effects"] as? String,
      "[{\"id\":\"mini.ping\",\"kind\":\"run\",\"payload\":\"ping\"}]")
  }

  func testUnknownFeatureAndMalformedLinesReportErrors() {
    let unknown = ReplayServer.respond(
      toLine: "{\"op\":\"reduce\",\"feature\":\"nope\",\"state\":{},\"action\":{}}",
      registry: registry)
    XCTAssertEqual(unknown?["error"] as? String, "unknown feature 'nope'")

    let malformed = ReplayServer.respond(toLine: "not json", registry: registry)
    XCTAssertEqual(malformed?["error"] as? String, "malformed request line")

    let missingFields = ReplayServer.respond(
      toLine: "{\"op\":\"reduce\",\"feature\":\"mini\"}", registry: registry)
    XCTAssertEqual(missingFields?["error"] as? String, "reduce needs feature/state/action")

    let unknownOp = ReplayServer.respond(toLine: "{\"op\":\"dance\"}", registry: registry)
    XCTAssertEqual(unknownOp?["error"] as? String, "unknown op 'dance'")
  }

  func testExitRequestsShutdown() {
    XCTAssertNil(ReplayServer.respond(toLine: "{\"op\":\"exit\"}", registry: registry))
  }

  func testDecodeFailureSurfacesAsErrorNotCrash() throws {
    let line = """
      {"op":"reduce","feature":"mini","state":{"count":1},"action":{"case":"unknownCase"}}
      """
    let response = try XCTUnwrap(ReplayServer.respond(toLine: line, registry: registry))
    XCTAssertNotNil(response["error"], "a decode failure must come back as an error object")
  }
}
