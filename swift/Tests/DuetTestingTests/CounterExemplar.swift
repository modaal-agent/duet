// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Duet
import Foundation

// The test-support receipts' exemplar feature — the counter in its harness-proving
// role, WITH the canonical serialization (serialization.md §4) so the scenario
// runners can compile fixtures from it. Test-target-local on purpose: the framework
// ships no features, and this suite's fixtures live under `Tests/parity/fixtures/`
// (the same walk-up convention a consuming repo uses from its own test files).

struct CounterState: Equatable, Codable, Sendable {
  var count: Int = 0
  var isAutoIncrementing: Bool = false
}

enum CounterAction: Equatable, Sendable {
  case increment
  case decrement
  case toggleAutoIncrement
  /// System action, fed back by the ticker effect.
  case tick
}

enum CounterEffectPayload: Equatable, Sendable {
  case startTicker
}

enum CounterEffectIDs {
  static let ticker: EffectID = "counter.ticker"
}

func counterReducer(
  state: inout CounterState, action: CounterAction
) -> [Effect<CounterEffectPayload>] {
  switch action {
  case .increment:
    state.count += 1
    return []
  case .decrement:
    state.count -= 1
    return []
  case .toggleAutoIncrement:
    state.isAutoIncrementing.toggle()
    return state.isAutoIncrementing
      ? [.run(.startTicker, id: CounterEffectIDs.ticker)]
      : [.cancel(id: CounterEffectIDs.ticker)]
  case .tick:
    // Guarded: a stray tick after cancellation must not count.
    if state.isAutoIncrementing {
      state.count += 1
    }
    return []
  }
}

// MARK: - Canonical serialization (serialization.md §4)

extension CounterAction: Codable {
  private enum CodingKeys: String, CodingKey {
    case caseName = "case"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let caseName = try container.decode(String.self, forKey: .caseName)
    switch caseName {
    case "increment": self = .increment
    case "decrement": self = .decrement
    case "toggleAutoIncrement": self = .toggleAutoIncrement
    case "tick": self = .tick
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .caseName, in: container,
        debugDescription: "Unknown CounterAction case '\(caseName)'")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .increment: try container.encode("increment", forKey: .caseName)
    case .decrement: try container.encode("decrement", forKey: .caseName)
    case .toggleAutoIncrement: try container.encode("toggleAutoIncrement", forKey: .caseName)
    case .tick: try container.encode("tick", forKey: .caseName)
    }
  }
}

extension CounterEffectPayload: Codable {
  private enum CodingKeys: String, CodingKey {
    case caseName = "case"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let caseName = try container.decode(String.self, forKey: .caseName)
    switch caseName {
    case "startTicker": self = .startTicker
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .caseName, in: container,
        debugDescription: "Unknown CounterEffectPayload case '\(caseName)'")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .startTicker: try container.encode("startTicker", forKey: .caseName)
    }
  }
}
