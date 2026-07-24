// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// Parsed command line. Deliberately hand-rolled (zero third-party dependencies —
/// swift-argument-parser would enter every toolchain build for one flag loop).
struct Options {
  var command: String?
  var feature: String?
  var platform: String?
  var runner: String?
  var target: String?
  var json = false
  var swiftOnly = false
  var kotlinOnly = false
  var clean = false
  var check = false

  enum OptionsError: Error, CustomStringConvertible {
    case unknownFeature(String)

    var description: String {
      switch self {
      case let .unknownFeature(name):
        return "unknown feature '\(name)' (not in parity/manifest.yaml)"
      }
    }
  }

  func resolveFeature(in manifest: Manifest) throws -> Feature? {
    guard let name = feature else { return nil }
    guard let found = manifest.feature(named: name) else {
      throw OptionsError.unknownFeature(name)
    }
    return found
  }

  static func parse(_ arguments: [String]) -> Options? {
    var options = Options()
    var rest = arguments.dropFirst()
    if let first = rest.first, !first.hasPrefix("-") {
      options.command = first
      rest = rest.dropFirst()
    }
    var iterator = rest.makeIterator()
    while let argument = iterator.next() {
      switch argument {
      case "--feature":
        guard let value = iterator.next() else { return nil }
        options.feature = value
      case "--platform":
        guard let value = iterator.next() else { return nil }
        options.platform = value
      case "--runner":
        guard let value = iterator.next() else { return nil }
        options.runner = value
      case "--json":
        options.json = true
      case "--swift-only":
        options.swiftOnly = true
      case "--kotlin-only":
        options.kotlinOnly = true
      case "--clean":
        options.clean = true
      case "--check":
        options.check = true
      case "--help", "-h":
        options.command = "help"
      default:
        if argument.hasPrefix("-") { return nil }
        options.target = argument
      }
    }
    return options
  }
}

let usage = """
  duet — the Duet parity toolchain CLI

  usage:
    duet verify [--feature <name>] [--swift-only|--kotlin-only] [--json]
        meta-checks (lockstep + fixture symmetry), then both platform lanes in
        parallel; failures render with step label, JSON path, and scenario line.
    duet record [--feature <name>] [--platform swift|kotlin] [--check] [--json]
        recompile fixtures from scenarios (scoped when --feature given), then a
        review summary of what changed. Fixtures are build products — review the
        diff like code. --platform kotlin records through the Kotlin runner (§6
        shared writer: byte-identical output). --check = CI regen gate: exit 1 if
        anything was stale (R10).
    duet explain [--json]
        re-render the last run's failures from parity/.runs (no logs, no re-run).
    duet materialize <fixture>#<step> --platform swift|kotlin [--json]
        emit a standalone failing unit test for one fixture step on one platform.
    duet materialize --clean
        delete every generated Materialized_* test.
    duet protocol-run [--runner <path>]
        byte-gate the full corpus through a replay-protocol runner
        (contracts/replay-protocol-v1.md). Default: build + drive the repo's own
        Swift `replay-runner` product; --runner drives any conforming flavor's
        prebuilt runner (e.g. the Kotlin lane's installDist output).
    duet writer-check
        re-emit every committed fixture through the CLI-side §6 writer and
        byte-compare against disk (retires once the writer move lands — F4·S2).

  Run from anywhere inside the repo (root is found via parity/fixtures).
  """

guard let options = Options.parse(CommandLine.arguments), let command = options.command
else {
  print(usage)
  exit(2)
}
if command == "help" {
  print(usage)
  exit(0)
}
guard let repo = Repo.discover() else {
  FileHandle.standardError.write(
    Data("duet: not inside a parity repo (no parity/fixtures found walking up)\n".utf8))
  exit(2)
}

do {
  let code: Int32
  switch command {
  case "verify":
    code = try Lanes.run(repo: repo, options: options)
  case "record":
    code = try Lanes.record(repo: repo, options: options)
  case "explain":
    code = Explain.run(repo: repo, options: options)
  case "materialize":
    code = try Materialize.run(repo: repo, options: options)
  case "protocol-run":
    code = try ProtocolLane.run(repo: repo, options: options)
  case "writer-check":
    code = try ProtocolLane.writerCheck(repo: repo, options: options)
  default:
    print("duet: unknown command '\(command)'\n")
    print(usage)
    code = 2
  }
  exit(code)
} catch {
  FileHandle.standardError.write(Data("duet: \(error)\n".utf8))
  exit(1)
}
