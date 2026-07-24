// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetReplay
import Foundation

/// The replay-protocol lane (G1, doc-18 §2.1 — proven by FC3-a, formalized as
/// contracts/replay-protocol-v1.md): `duet protocol-run` drives every fixture
/// (leaves AND chains — one `reduce` op, CLI-side state slots) through a
/// replay-protocol runner subprocess and byte-gates each step CLI-side. This is
/// the G1 shape: the flavor exposes only decode→reduce→encode; the CLI owns
/// fixture reading, step driving, comparison, and reporting — flavor-neutrally
/// (`--runner` drives any conforming runner). The FC3-a `writer-check` probe verb
/// retired at F4·S2: the CLI-side writer IS the writer now, and `record --check`
/// is its standing byte gate.
enum ProtocolLane {

  // MARK: - protocol-run

  static func run(repo: Repo, options: Options) throws -> Int32 {
    let total = Date()
    let manifest = try Manifest.load(repo: repo)
    if !manifest.lintOK {
      print("lockstep-lint: FAIL — not driving the protocol lane")
      for error in manifest.lintErrors { print("  ✗ \(error)") }
      return 1
    }

    // 1. Ensure the runner is current (the lane's fixed cost — measured, not
    // hidden). `--runner <path>` overrides with a prebuilt executable — the
    // protocol is flavor-neutral (contracts/replay-protocol-v1.md), so any
    // conforming runner (e.g. the Kotlin lane's `:replay-runner:installDist`
    // output) drives the same gate; the caller owns keeping it current.
    var buildSeconds = 0.0
    let executable: URL
    if let override = options.runner {
      executable = URL(fileURLWithPath: override)
      guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        print("protocol-run: FAIL — --runner '\(override)' is not an executable")
        return 1
      }
    } else {
      let build = Lanes.finish(
        try Lanes.launch(
          ["swift", "build", "--product", "replay-runner"],
          cwd: manifest.swiftPackageDir, logName: "replay-runner-build"))
      if build.exitCode != 0 {
        let log = (try? String(contentsOf: build.logURL, encoding: .utf8)) ?? ""
        print(log.split(separator: "\n").suffix(20).joined(separator: "\n"))
        print("protocol-run: FAIL — replay-runner did not build")
        return 1
      }
      buildSeconds = build.seconds
      executable = manifest.swiftPackageDir.appendingPathComponent(".build/debug/replay-runner")
    }

    // 2. Spawn + handshake.
    let spawn = Date()
    let runner = try RunnerClient(executable: executable)
    guard let handshake = try runner.readLine(),
      (handshake["protocol"] as? String) == "duet-replay",
      let version = handshake["version"] as? Int
    else {
      print("protocol-run: FAIL — no valid handshake from the replay runner")
      return 1
    }
    let advertised = Set(handshake["features"] as? [String] ?? [])
    let spawnSeconds = Date().timeIntervalSince(spawn)

    // 3. Drive every leaf fixture, step by step, actual state flowing forward.
    let replayStart = Date()
    var fixturesRun = 0
    var stepsRun = 0
    var failures: [String] = []
    for feature in manifest.features {
      guard advertised.contains(feature.name) else {
        failures.append("\(feature.name): not advertised by the runner")
        continue
      }
      for fixture in feature.fixtures {
        let url = repo.fixturesDir.appendingPathComponent("\(fixture).fixture.json")
        guard let data = try? Data(contentsOf: url),
          let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rawInitial = document["initialState"],
          let rawSteps = document["steps"] as? [[String: Any]]
        else {
          failures.append("\(fixture): unreadable fixture")
          continue
        }
        fixturesRun += 1
        var stateTree: Any = rawInitial
        for (index, rawStep) in rawSteps.enumerated() {
          guard let action = rawStep["action"],
            let rawExpectedState = rawStep["expectedState"],
            let rawExpectedEffects = rawStep["expectedEffects"]
          else {
            failures.append("\(fixture)#\(index): malformed step")
            break
          }
          let response = try runner.request([
            "op": "reduce", "feature": feature.name,
            "state": stateTree, "action": action,
          ])
          guard let actualState = response["state"] as? String,
            let actualEffects = response["effects"] as? String
          else {
            failures.append(
              "\(fixture)#\(index): \(response["error"] as? String ?? "no response")")
            break
          }
          stepsRun += 1
          let expectedState = try ReplayCanonical.canonicalString(fromJSONObject: rawExpectedState)
          let expectedEffects = try ReplayCanonical.canonicalString(
            fromJSONObject: rawExpectedEffects)
          if actualState != expectedState {
            failures.append("\(fixture)#\(index): state diverged")
            break
          }
          if actualEffects != expectedEffects {
            failures.append("\(fixture)#\(index): effects diverged")
            break
          }
          stateTree = try JSONSerialization.jsonObject(
            with: Data(actualState.utf8), options: [.fragmentsAllowed])
        }
      }
    }
    // 3b. Chains need NO new protocol op: steps carry their `node` key, per-node
    // states seed from `initialStates`, and the hop-DERIVED action is recorded in
    // the fixture. The CLI drives a state slot per node; the hop-derivation
    // authoring check (delegate → action, typed) stays in the in-process scenario
    // lane — pure replay crosses the protocol whole.
    var chainsRun = 0
    for chain in manifest.chains {
      let url = repo.fixturesDir.appendingPathComponent("\(chain).fixture.json")
      guard let data = try? Data(contentsOf: url),
        let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let initialStates = document["initialStates"] as? [String: Any],
        let rawSteps = document["steps"] as? [[String: Any]]
      else {
        failures.append("\(chain): unreadable chain fixture")
        continue
      }
      chainsRun += 1
      var slots = initialStates
      for (index, rawStep) in rawSteps.enumerated() {
        guard let node = rawStep["node"] as? String,
          let action = rawStep["action"],
          let rawExpectedEffects = rawStep["expectedEffects"],
          let stateTree = slots[node]
        else {
          failures.append("\(chain)#\(index): malformed chain step")
          break
        }
        let response = try runner.request([
          "op": "reduce", "feature": node,
          "state": stateTree, "action": action,
        ])
        guard let actualState = response["state"] as? String,
          let actualEffects = response["effects"] as? String
        else {
          failures.append(
            "\(chain)#\(index): \(response["error"] as? String ?? "no response")")
          break
        }
        stepsRun += 1
        let expectedEffects = try ReplayCanonical.canonicalString(
          fromJSONObject: rawExpectedEffects)
        if actualEffects != expectedEffects {
          failures.append("\(chain)#\(index) (\(node)): effects diverged")
          break
        }
        if let rawExpectedState = rawStep["expectedState"] {
          let expectedState = try ReplayCanonical.canonicalString(fromJSONObject: rawExpectedState)
          if actualState != expectedState {
            failures.append("\(chain)#\(index) (\(node)): state diverged")
            break
          }
        }
        slots[node] = try JSONSerialization.jsonObject(
          with: Data(actualState.utf8), options: [.fragmentsAllowed])
      }
    }
    runner.exit()
    let replaySeconds = Date().timeIntervalSince(replayStart)

    // 4. Report.
    print("protocol-run: duet-replay v\(version), \(advertised.count) feature(s) advertised")
    print(
      "  runner build \(String(format: "%.2f", buildSeconds))s · spawn+handshake "
        + String(format: "%.3f", spawnSeconds) + "s · replay "
        + String(format: "%.3f", replaySeconds) + "s")
    print(
      "  \(fixturesRun) leaf + \(chainsRun) chain fixture(s), \(stepsRun) step(s) "
        + "byte-gated CLI-side (hop-derivation authoring checks stay in-process)")
    for failure in failures { print("  ✗ \(failure)") }
    let elapsed = Date().timeIntervalSince(total)
    print(
      failures.isEmpty
        ? "protocol-run: PASS in \(String(format: "%.1f", elapsed))s"
        : "protocol-run: FAIL (\(failures.count)) in \(String(format: "%.1f", elapsed))s")
    return failures.isEmpty ? 0 : 1
  }

  // MARK: - Runner client

  /// A JSON-lines stdio client for the replay runner subprocess.
  final class RunnerClient {
    private let process = Process()
    private let requests = Pipe()
    private let responses = Pipe()
    private var buffer = Data()

    init(executable: URL) throws {
      process.executableURL = executable
      process.standardInput = requests
      process.standardOutput = responses
      process.standardError = FileHandle.nullDevice
      try process.run()
    }

    func request(_ object: [String: Any]) throws -> [String: Any] {
      let data = try JSONSerialization.data(withJSONObject: object)
      requests.fileHandleForWriting.write(data)
      requests.fileHandleForWriting.write(Data("\n".utf8))
      guard let response = try readLine() else {
        return ["error": "runner closed the stream"]
      }
      return response
    }

    /// Reads one newline-terminated JSON object from the runner's stdout.
    func readLine() throws -> [String: Any]? {
      while true {
        if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
          let line = buffer.subdata(in: buffer.startIndex..<newline)
          buffer.removeSubrange(buffer.startIndex...newline)
          if line.isEmpty { continue }
          return try JSONSerialization.jsonObject(with: line) as? [String: Any]
        }
        let chunk = responses.fileHandleForReading.availableData
        if chunk.isEmpty { return nil }
        buffer.append(chunk)
      }
    }

    func exit() {
      requests.fileHandleForWriting.write(Data("{\"op\":\"exit\"}\n".utf8))
      try? requests.fileHandleForWriting.close()
      process.waitUntilExit()
    }
  }
}
