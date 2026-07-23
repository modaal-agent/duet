// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// The replay-protocol server — a JSON-lines stdio loop over an app's adapter
/// registry. Protocol v1, the versioned flavor seam — normative contract:
/// contracts/replay-protocol-v1.md (formalized at F3 from the proven v0 shape;
/// the wire format is unchanged, the version stamp advances):
///
///   handshake (stdout, on start):
///     {"protocol":"duet-replay","version":1,"platform":"swift","features":[…]}
///   request  (stdin, one JSON object per line):
///     {"op":"reduce","feature":"counter","state":<tree>,"action":<tree>}
///     {"op":"exit"}
///   response (stdout, one JSON object per line):
///     {"state":"<canonical>","effects":"<canonical>"}   |   {"error":"…"}
///
/// State crosses INTO the adapter as a raw JSON tree (the CLI holds the fixture);
/// results cross OUT as canonical strings (the byte-gate objects). The server is
/// stateless per request — the CLI feeds each step the previous step's actual
/// state. An app's replay-runner executable is three lines:
///
///     import DuetReplay
///     ReplayServer.serve(registry: appReplayRegistry)
public enum ReplayServer {
  public static let protocolName = "duet-replay"
  public static let protocolVersion = 1
  public static let platform = "swift"

  /// The handshake object emitted on start.
  public static func handshake(registry: ReplayRegistry) -> [String: Any] {
    [
      "protocol": protocolName,
      "version": protocolVersion,
      "platform": platform,
      "features": registry.features.keys.sorted(),
    ]
  }

  /// One request line → one response object; nil means `exit` was requested.
  /// Pure request handling, split from the stdio loop so it can be receipted
  /// without a subprocess.
  public static func respond(toLine line: String, registry: ReplayRegistry) -> [String: Any]? {
    guard
      let request = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
      let op = request["op"] as? String
    else {
      return ["error": "malformed request line"]
    }
    switch op {
    case "exit":
      return nil
    case "reduce":
      guard let feature = request["feature"] as? String,
        let stateTree = request["state"],
        let actionTree = request["action"]
      else {
        return ["error": "reduce needs feature/state/action"]
      }
      guard let replay = registry.features[feature] else {
        return ["error": "unknown feature '\(feature)'"]
      }
      do {
        let result = try replay.step(stateTree, actionTree)
        return ["state": result.state, "effects": result.effects]
      } catch {
        return ["error": "\(error)"]
      }
    default:
      return ["error": "unknown op '\(op)'"]
    }
  }

  /// The blocking stdio loop: handshake, then one response per request line until
  /// `exit` or EOF. Never returns except by `exit(0)`.
  public static func serve(registry: ReplayRegistry) -> Never {
    setvbuf(stdout, nil, _IONBF, 0)
    emit(handshake(registry: registry))
    while let line = readLine(strippingNewline: true) {
      guard !line.isEmpty else { continue }
      guard let response = respond(toLine: line, registry: registry) else {
        exit(0)
      }
      emit(response)
    }
    exit(0)
  }

  private static func emit(_ object: [String: Any]) {
    // Handshake/response objects are built from JSON-safe values only; a failure
    // here is a programmer error in the server itself.
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}
