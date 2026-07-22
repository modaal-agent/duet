// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// Identifies an in-flight effect for cancellation. Plain string, namespaced by convention
/// as `"<feature>.<purpose>"`. See contracts/store-kernel-contract.md §2.
public typealias EffectID = String

/// A side-effect *request* as equatable data. The reducer emits these; the store's runtime
/// executes them via the feature's `EffectHandler`. Contract: contracts/store-kernel-contract.md §2.
public enum Effect<Payload: Equatable>: Equatable {
  /// Execute `payload` via the handler. A non-nil `id` gives cancel-in-flight semantics:
  /// any running effect with the same id is cancelled before this one starts.
  case run(Payload, id: EffectID? = nil)
  /// Cancel the running effect with `id`; no-op if none.
  case cancel(id: EffectID)
}

/// Effects are pure data over the dialect's value types.
extension Effect: Sendable where Payload: Sendable {}

// Canonical serialization shape (contracts/serialization.md §4):
//   {"kind": "run", "id": <string|null>, "payload": {...}}
//   {"kind": "cancel", "id": <string>}
extension Effect: Codable where Payload: Codable {
  private enum CodingKeys: String, CodingKey {
    case kind
    case id
    case payload
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(String.self, forKey: .kind)
    switch kind {
    case "run":
      let payload = try container.decode(Payload.self, forKey: .payload)
      let id = try container.decodeIfPresent(EffectID.self, forKey: .id)
      self = .run(payload, id: id)
    case "cancel":
      let id = try container.decode(EffectID.self, forKey: .id)
      self = .cancel(id: id)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: container, debugDescription: "Unknown effect kind '\(kind)'")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .run(payload, id):
      try container.encode("run", forKey: .kind)
      try container.encodeIfPresent(id, forKey: .id)
      try container.encode(payload, forKey: .payload)
    case let .cancel(id):
      try container.encode("cancel", forKey: .kind)
      try container.encode(id, forKey: .id)
    }
  }
}
