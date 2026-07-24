// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// Repo discovery + the parity manifest model. The manifest has exactly ONE parser —
/// the repo's parity/scripts/lockstep-lint.py — and the CLI consumes its `--json`
/// plan (running the meta-check and loading the manifest are the same call). The
/// repo's tree shape is NOT hardcoded here: the platform roots are derived from the
/// manifest's own per-feature source paths (F4·S1 — the CLI is repo-layout-neutral).
struct Repo {
  let root: URL

  var fixturesDir: URL { root.appendingPathComponent("parity/fixtures") }
  var runsDir: URL { root.appendingPathComponent("parity/.runs") }
  var lockstepLint: URL { root.appendingPathComponent("parity/scripts/lockstep-lint.py") }

  /// Walks up from the working directory to the directory containing parity/fixtures —
  /// the same root convention both test runners use.
  static func discover(from start: String = FileManager.default.currentDirectoryPath) -> Repo? {
    var directory = URL(fileURLWithPath: start)
    while directory.path != "/" {
      let candidate = directory.appendingPathComponent("parity/fixtures")
      if FileManager.default.fileExists(atPath: candidate.path) {
        return Repo(root: directory)
      }
      directory.deleteLastPathComponent()
    }
    return nil
  }
}

struct Feature {
  let name: String
  let swiftSource: String
  let kotlinSource: String
  let stateType: String
  let actionType: String
  let payloadType: String
  let scenario: String?
  let fixtures: [String]

  /// `Sources/<Module>/…` → the SPM module that declares the feature.
  var swiftModule: String? {
    let parts = swiftSource.split(separator: "/").map(String.init)
    guard let index = parts.firstIndex(of: "Sources"), index + 1 < parts.count else {
      return nil
    }
    return parts[index + 1]
  }

  /// The feature's test target — the `swift test --filter` scope.
  var swiftTestTarget: String? { swiftModule.map { "\($0)Tests" } }

  /// `<androidRoot>/<module…>/src/{main,test}/…` → the module's directory path
  /// relative to the Android root (nested Gradle modules keep their nesting).
  var kotlinModulePath: String? {
    let parts = kotlinSource.split(separator: "/").map(String.init)
    guard let srcIndex = parts.firstIndex(of: "src"), srcIndex >= 2,
      srcIndex + 1 < parts.count, ["main", "test"].contains(parts[srcIndex + 1])
    else { return nil }
    return parts[1..<srcIndex].joined(separator: "/")
  }

  /// The Gradle test task for the feature (`:module:test`, nesting colon-joined).
  var gradleTestTask: String? {
    kotlinModulePath.map { ":\($0.replacingOccurrences(of: "/", with: ":")):test" }
  }

  /// Package of the Kotlin sources (`…/kotlin/com/wikimemory/x/File.kt` → com.wikimemory.x).
  var kotlinPackage: String? {
    let parts = kotlinSource.split(separator: "/").map(String.init)
    guard let index = parts.firstIndex(of: "kotlin"), index + 1 < parts.count - 1 else {
      return nil
    }
    return parts[(index + 1)..<(parts.count - 1)].joined(separator: ".")
  }

  /// House convention: `SharePickerState` → `sharePickerReducer`.
  var reducerName: String {
    var base = stateType
    if base.hasSuffix("State") { base = String(base.dropLast("State".count)) }
    guard let first = base.first else { return "reducer" }
    return first.lowercased() + base.dropFirst() + "Reducer"
  }
}

struct Manifest {
  let features: [Feature]
  let chains: [String]
  /// Meta-check verdict from the same lockstep-lint run that produced the plan.
  let lintOK: Bool
  let lintErrors: [String]
  /// The Swift package root (the prefix of any feature's `swift:` path before
  /// /Sources/) and the Android build root (the first component of any feature's
  /// `kotlin:` path) — derived, absolute.
  let swiftPackageDir: URL
  let androidDir: URL

  func feature(named name: String) -> Feature? {
    features.first { $0.name == name }
  }

  /// Owner of a fixture name (chains have no owner feature).
  func feature(forFixture fixture: String) -> Feature? {
    features.first { $0.fixtures.contains(fixture) }
  }

  /// Runs lockstep-lint --json and adopts its plan — one manifest parser (python),
  /// and every CLI invocation gets the meta-check for free.
  static func load(repo: Repo) throws -> Manifest {
    enum ManifestError: Error, CustomStringConvertible {
      case lintUnreadable(String)
      case layoutUnderivable(String)
      var description: String {
        switch self {
        case let .lintUnreadable(detail):
          return "lockstep-lint --json produced no parseable plan: \(detail)"
        case let .layoutUnderivable(detail):
          return "cannot derive the repo layout from the manifest: \(detail)"
        }
      }
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", repo.lockstepLint.path, "--json"]
    process.currentDirectoryURL = repo.root
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rawFeatures = root["features"] as? [String: [String: Any]]
    else {
      throw ManifestError.lintUnreadable(String(data: data, encoding: .utf8) ?? "<binary>")
    }
    let features = rawFeatures
      .map { name, spec in
        Feature(
          name: name,
          swiftSource: spec["swift"] as? String ?? "",
          kotlinSource: spec["kotlin"] as? String ?? "",
          stateType: spec["state"] as? String ?? "",
          actionType: spec["action"] as? String ?? "",
          payloadType: spec["effectPayload"] as? String ?? "",
          scenario: spec["scenario"] as? String,
          fixtures: spec["fixtures"] as? [String] ?? [])
      }
      .sorted { $0.name < $1.name }
    guard
      let swiftRelative = features.lazy
        .compactMap({ feature -> String? in
          let parts = feature.swiftSource.split(separator: "/").map(String.init)
          guard let index = parts.firstIndex(of: "Sources"), index > 0 else { return nil }
          return parts[..<index].joined(separator: "/")
        }).first
    else {
      throw ManifestError.layoutUnderivable(
        "no feature `swift:` path contains /Sources/ (needed for the package root)")
    }
    guard
      let androidRelative = features.lazy
        .compactMap({ feature -> String? in
          let parts = feature.kotlinSource.split(separator: "/")
          return parts.count > 1 ? String(parts[0]) : nil
        }).first
    else {
      throw ManifestError.layoutUnderivable(
        "no feature `kotlin:` path names the Android root directory")
    }
    return Manifest(
      features: features,
      chains: root["chains"] as? [String] ?? [],
      lintOK: (root["status"] as? String) == "ok",
      lintErrors: root["errors"] as? [String] ?? [],
      swiftPackageDir: repo.root.appendingPathComponent(swiftRelative),
      androidDir: repo.root.appendingPathComponent(androidRelative))
  }
}
