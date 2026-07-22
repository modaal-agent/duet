// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Duet
import DuetTesting
import XCTest

// The chain dialect end-to-end on a minimal two-node duet: a `When` on the
// emitting node, the `Hop` seam (the recorded delegate decoded and mapped the way
// the parent's shell forwards it, with the previous step marked `linkToNext`), and
// node-scoped Then/ThenEffects. Source of `chain-ping-pong.fixture.json`.

private struct PingState: Equatable, Codable, Sendable {
  var sent: Int = 0
}

private enum PingAction: Equatable, Codable, Sendable {
  case fire

  private enum CodingKeys: String, CodingKey {
    case caseName = "case"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .caseName) {
    case "fire": self = .fire
    case let other:
      throw DecodingError.dataCorruptedError(
        forKey: .caseName, in: container, debugDescription: "Unknown PingAction '\(other)'")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("fire", forKey: .caseName)
  }
}

/// The delegate payload the seam carries (decoded by the Hop's typed closure).
private struct PingFired: Equatable, Codable, Sendable {
  var count: Int
}

private enum PingEffectPayload: Equatable, Codable, Sendable {
  case notifyListener(PingFired)

  private enum CodingKeys: String, CodingKey {
    case caseName = "case"
    case value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .caseName) {
    case "notifyListener":
      self = .notifyListener(try container.decode(PingFired.self, forKey: .value))
    case let other:
      throw DecodingError.dataCorruptedError(
        forKey: .caseName, in: container,
        debugDescription: "Unknown PingEffectPayload '\(other)'")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .notifyListener(delegate):
      try container.encode("notifyListener", forKey: .caseName)
      try container.encode(delegate, forKey: .value)
    }
  }
}

private func pingReducer(
  state: inout PingState, action: PingAction
) -> [Effect<PingEffectPayload>] {
  switch action {
  case .fire:
    state.sent += 1
    return [.run(.notifyListener(PingFired(count: state.sent)))]
  }
}

private struct PongState: Equatable, Codable, Sendable {
  var received: Int = 0
  var lastCount: Int?
}

private enum PongAction: Equatable, Codable, Sendable {
  case pingFired(count: Int)

  private enum CodingKeys: String, CodingKey {
    case caseName = "case"
    case value
  }

  private struct Value: Codable {
    var count: Int
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .caseName) {
    case "pingFired":
      self = .pingFired(count: try container.decode(Value.self, forKey: .value).count)
    case let other:
      throw DecodingError.dataCorruptedError(
        forKey: .caseName, in: container, debugDescription: "Unknown PongAction '\(other)'")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .pingFired(count):
      try container.encode("pingFired", forKey: .caseName)
      try container.encode(Value(count: count), forKey: .value)
    }
  }
}

private enum PongEffectPayload: Equatable, Codable, Sendable {
  case unused

  init(from decoder: Decoder) throws {
    throw DecodingError.dataCorrupted(
      DecodingError.Context(
        codingPath: decoder.codingPath, debugDescription: "PongEffectPayload never crosses"))
  }

  func encode(to encoder: Encoder) throws {}
}

private func pongReducer(
  state: inout PongState, action: PongAction
) -> [Effect<PongEffectPayload>] {
  switch action {
  case let .pingFired(count):
    state.received += 1
    state.lastCount = count
    return []
  }
}

private let ping = ChainNode("ping", initial: PingState(), reducer: pingReducer)
private let pong = ChainNode("pong", initial: PongState(), reducer: pongReducer)

private let pingPongChain = ChainScenario(
  chain: "ping-pong",
  description:
    "The seam receipt: ping's fired delegate crosses the Hop as pong's pingFired "
    + "action; the emitting step is marked linkToNext in the fixture."
) {
  When(ping, "fire emits the fired delegate", .fire)
  ThenEffects(ping, "exactly the notifyListener effect") {
    $0 == [.run(.notifyListener(PingFired(count: 1)))]
  }
  Hop("the ping→pong seam", from: ping, to: pong) { (delegate: PingFired) in
    .pingFired(count: delegate.count)
  }
  Then(pong, "the count crossed the seam") { $0.lastCount == 1 && $0.received == 1 }
  When(ping, "a second fire on the same chain", .fire)
  ThenEffects(ping, "the second delegate carries the new count") {
    $0 == [.run(.notifyListener(PingFired(count: 2)))]
  }
}

final class ChainScenarioTests: XCTestCase {
  func testPingPongChain() throws {
    try ChainScenarioRunner.verifyOrRecord(pingPongChain)
  }

  func testChainFixtureMarksTheEmittingStepLinkToNext() throws {
    let fixturesDir = try FixtureRunner.fixturesDirectory()
    let url = fixturesDir.appendingPathComponent("chain-ping-pong.fixture.json")
    let tree = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let steps = try XCTUnwrap(tree?["steps"] as? [[String: Any]])
    XCTAssertEqual(steps.count, 3)
    XCTAssertEqual(steps[0]["linkToNext"] as? Bool, true, "the hop's source step is marked")
    XCTAssertNil(steps[1]["linkToNext"], "the hop's target step is not")
    XCTAssertEqual(steps[1]["node"] as? String, "pong")
  }
}
