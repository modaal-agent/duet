// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// Subprocess plumbing + the `duet verify` and `duet record` commands.
enum Lanes {
  struct ProcessResult {
    let exitCode: Int32
    let logURL: URL
    let seconds: Double
  }

  /// Launches a process with output captured to a log file. `wait: false` returns
  /// immediately (caller pairs it with `finish`).
  static func launch(
    _ arguments: [String], cwd: URL, extraEnv: [String: String] = [:], logName: String
  ) throws -> (Process, URL, Date) {
    let logURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("duet-\(logName)-\(ProcessInfo.processInfo.processIdentifier).log")
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
    let handle = try FileHandle(forWritingTo: logURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = cwd
    var environment = ProcessInfo.processInfo.environment
    for (key, value) in extraEnv { environment[key] = value }
    process.environment = environment
    process.standardOutput = handle
    process.standardError = handle
    // Lane children must never read the interactive terminal: the Gradle daemon
    // client forwards stdin, and a TTY read from a background process group stops
    // the whole client JVM (SIGTTIN) AFTER "BUILD SUCCESSFUL" — a dual-lane
    // `verify` from a real terminal then hangs in waitUntilExit forever. /dev/null
    // gives every lane instant EOF, which is also what CI provides.
    process.standardInput = FileHandle.nullDevice
    let start = Date()
    try process.run()
    return (process, logURL, start)
  }

  static func finish(_ triple: (Process, URL, Date)) -> ProcessResult {
    let (process, logURL, start) = triple
    process.waitUntilExit()
    return ProcessResult(
      exitCode: process.terminationStatus, logURL: logURL,
      seconds: Date().timeIntervalSince(start))
  }

  /// The Gradle lane needs JAVA_HOME (21) to *configure* even the JVM-only test
  /// task. The Android SDK location is repo/machine config, not toolchain config —
  /// Gradle reads `<android>/local.properties` (sdk.dir) or the caller's
  /// ANDROID_HOME itself; the CLI adds neither.
  static func gradleEnvironment() -> [String: String] {
    var env: [String: String] = [:]
    let current = ProcessInfo.processInfo.environment
    if current["JAVA_HOME"] == nil {
      let probe = Process()
      probe.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
      probe.arguments = ["-v", "21"]
      let pipe = Pipe()
      probe.standardOutput = pipe
      probe.standardError = FileHandle.nullDevice
      if (try? probe.run()) != nil {
        probe.waitUntilExit()
        if probe.terminationStatus == 0,
          let data = try? pipe.fileHandleForReading.readToEnd(),
          let home = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !home.isEmpty
        {
          env["JAVA_HOME"] = home
        }
      }
    }
    return env
  }

  // MARK: - Reports

  static func clearReports(_ repo: Repo) {
    try? FileManager.default.removeItem(at: repo.runsDir)
  }

  /// All fixture reports written by the runners this run, `[platform: [report]]`.
  static func readReports(_ repo: Repo) -> [[String: Any]] {
    var reports: [[String: Any]] = []
    for platform in (try? FileManager.default.contentsOfDirectory(atPath: repo.runsDir.path)) ?? [] {
      let dir = repo.runsDir.appendingPathComponent(platform)
      for file in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
      where file.hasSuffix(".json") {
        if let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
          reports.append(object)
        }
      }
    }
    return reports.sorted {
      (($0["fixture"] as? String) ?? "") < (($1["fixture"] as? String) ?? "")
    }
  }

  /// Failures carry their own runner-rendered block (`rendered`) — the CLI prints it
  /// verbatim and only tags the platform on the header line. One formatter per
  /// platform (the runners'), zero here.
  static func renderedText(failure: [String: Any], of report: [String: Any]) -> String {
    let platform = report["platform"] as? String ?? "?"
    guard let text = failure["rendered"] as? String, !text.isEmpty else {
      let fixture = report["fixture"] as? String ?? "?"
      let kind = failure["kind"] as? String ?? "?"
      return "✗ '\(fixture)' — \(kind) (report has no rendered block — pre-FT2 runner?)   [\(platform)]"
    }
    guard let newline = text.firstIndex(of: "\n") else {
      return "\(text)   [\(platform)]"
    }
    return text.replacingCharacters(in: newline..<newline, with: "   [\(platform)]")
  }

  static func failedReports(_ reports: [[String: Any]]) -> [[String: Any]] {
    reports.filter { ($0["status"] as? String) == "failed" }
  }

  // MARK: - Commands

  /// `duet verify [--feature X] [--swift-only|--kotlin-only] [--json]`
  static func run(repo: Repo, options: Options) throws -> Int32 {
    let start = Date()
    // Loading the manifest IS the meta-check (lockstep-lint --json) — a stale
    // manifest makes lane results unreliable, so a lint failure stops here.
    let manifest = try Manifest.load(repo: repo)
    if !manifest.lintOK {
      if options.json {
        emitJSON(["status": "failed", "phase": "meta", "errors": manifest.lintErrors])
      } else {
        print("lockstep-lint: FAIL")
        for error in manifest.lintErrors { print("  ✗ \(error)") }
        print("duet verify: FAIL (meta-checks) — not running platform lanes")
      }
      return 1
    }
    if !options.json { print("duet verify: meta-checks ok") }
    let feature = try options.resolveFeature(in: manifest)
    clearReports(repo)

    var swiftResult: ProcessResult?
    var kotlinResult: ProcessResult?
    var swiftLaunch: (Process, URL, Date)?
    var kotlinLaunch: (Process, URL, Date)?

    if !options.kotlinOnly {
      var arguments = ["swift", "test"]
      if let target = feature?.swiftTestTarget {
        arguments += ["--filter", target]
      }
      swiftLaunch = try launch(arguments, cwd: manifest.swiftPackageDir, logName: "swift")
    }
    if !options.swiftOnly {
      let task = feature?.gradleTestTask ?? "test"
      // --rerun: an up-to-date Gradle test task would silently skip the replays and
      // write no reports — a "PASS" that verified nothing (caught by the coverage
      // check below, but rerunning is the correct behavior for a verification tool).
      kotlinLaunch = try launch(
        ["./gradlew", task, "--rerun", "--console=plain"], cwd: manifest.androidDir,
        extraEnv: gradleEnvironment(), logName: "kotlin")
    }
    // Lanes stream to their log files, not the console — say so before waiting,
    // else a stalled lane is an undiagnosable blank screen.
    if !options.json {
      var running: [String] = []
      if let launch = swiftLaunch { running.append("swift \(launch.1.path)") }
      if let launch = kotlinLaunch { running.append("kotlin \(launch.1.path)") }
      print("duet verify: lanes running — logs: \(running.joined(separator: " · "))")
    }
    if let launch = swiftLaunch { swiftResult = finish(launch) }
    if let launch = kotlinLaunch { kotlinResult = finish(launch) }

    let reports = readReports(repo)
    let failed = failedReports(reports)
    let elapsed = Date().timeIntervalSince(start)

    // Coverage gate: every expected fixture must have reported on every requested
    // platform — a lane that "passed" without replaying is a failure, not a pass.
    // Unscoped runs expect the chain fixtures too.
    var expectedFixtures = (feature.map { [$0] } ?? manifest.features)
      .flatMap { $0.fixtures }
    if feature == nil { expectedFixtures += manifest.chains }
    var missing: [String] = []
    for fixture in expectedFixtures {
      for platform in ["swift", "kotlin"] {
        if platform == "swift" && options.kotlinOnly { continue }
        if platform == "kotlin" && options.swiftOnly { continue }
        if !reports.contains(where: {
          ($0["fixture"] as? String) == fixture && ($0["platform"] as? String) == platform
        }) {
          missing.append("\(fixture) [\(platform)]")
        }
      }
    }

    let laneFailed =
      (swiftResult.map { $0.exitCode != 0 } ?? false)
      || (kotlinResult.map { $0.exitCode != 0 } ?? false)
      || !missing.isEmpty

    if options.json {
      var lanes: [String: Any] = [:]
      if let result = swiftResult {
        lanes["swift"] = ["exit": Int(result.exitCode), "seconds": result.seconds, "log": result.logURL.path]
      }
      if let result = kotlinResult {
        lanes["kotlin"] = ["exit": Int(result.exitCode), "seconds": result.seconds, "log": result.logURL.path]
      }
      emitJSON([
        "status": laneFailed ? "failed" : "passed",
        "elapsedSeconds": elapsed,
        "lanes": lanes,
        "missingReports": missing,
        "reports": reports,
      ])
      return laneFailed ? 1 : 0
    }

    func laneLine(_ name: String, _ result: ProcessResult?) -> String {
      guard let result = result else { return "  - \(name) lane skipped" }
      let mark = result.exitCode == 0 ? "✓" : "✗"
      return "  \(mark) \(name) lane (\(String(format: "%.1f", result.seconds))s)"
    }
    print(laneLine("swift ", swiftResult))
    print(laneLine("kotlin", kotlinResult))

    let passedCount = reports.count - failed.count
    print("duet verify: \(passedCount)/\(reports.count) fixture report(s) passed")
    if !missing.isEmpty {
      print("✗ missing fixture report(s) — lane ran but did not replay these:")
      for entry in missing { print("    \(entry)") }
      // The two platforms miss for different reasons — name the fix, not just the
      // gap (the Swift scenario replays its leaves itself; Kotlin needs the
      // per-leaf @Test convention).
      if missing.contains(where: { $0.hasSuffix("[kotlin]") }) {
        print("  fix [kotlin]: every Branch leaf needs its own replay method — add")
        print("      `@Test fun <leaf>Leaf() = replay(\"<feature>.<leaf>\")` to the feature's")
        print("      <Feature>GoldenTest.kt (chains: the chain fixture tests, e.g. ChainFixtureTest.kt)")
      }
      if missing.contains(where: { $0.hasSuffix("[swift]") }) {
        print("  fix [swift]: the scenario did not replay this leaf — check the Branch exists")
        print("      in the scenario, then `duet record --feature <feature>` and re-run")
      }
    }
    for report in failed {
      for failure in report["failures"] as? [[String: Any]] ?? [] {
        print(renderedText(failure: failure, of: report))
      }
    }
    // A red lane with zero failed fixture reports = infrastructure failure (compile
    // error, crashed suite) — surface the log tail since no report explains it.
    if laneFailed && failed.isEmpty {
      for result in [swiftResult, kotlinResult].compactMap({ $0 }) where result.exitCode != 0 {
        let log = (try? String(contentsOf: result.logURL, encoding: .utf8)) ?? ""
        print("--- log tail (\(result.logURL.path)) ---")
        print(log.split(separator: "\n").suffix(30).joined(separator: "\n"))
      }
    }
    print(
      laneFailed
        ? "duet verify: FAIL in \(String(format: "%.1f", elapsed))s"
        : "duet verify: PASS in \(String(format: "%.1f", elapsed))s")
    return laneFailed ? 1 : 0
  }

  /// `duet record [--feature X] [--platform swift|kotlin] [--check] [--json]` —
  /// scoped fixture regeneration via the scenario runners, then a review summary.
  /// Recording is a *source-generation* step: the diff is meant to be reviewed like
  /// code (bless-by-git). `--platform kotlin` records through the Kotlin runner
  /// (`-PregenFixtures=1`); the §6 shared writer makes the two platforms' outputs
  /// byte-identical for equivalent scenarios. `--check` is the CI regen gate (R10):
  /// exit 1 if any fixture was stale relative to its scenario.
  /// (No lint gate here on purpose — record is how a lint-red tree gets repaired.)
  static func record(repo: Repo, options: Options) throws -> Int32 {
    let manifest = try Manifest.load(repo: repo)
    let feature = try options.resolveFeature(in: manifest)
    // Snapshot fixture bytes so the summary lists what THIS run rewrote (git diff
    // would also show unrelated uncommitted fixture changes).
    let before = fixtureDigests(repo)
    // Stale artifacts from an earlier record pass must not re-materialize.
    RecordArtifacts.clear(repo)
    let result: ProcessResult
    if options.platform == "kotlin" {
      let task = feature?.gradleTestTask ?? "test"
      result = finish(
        try launch(
          ["./gradlew", task, "--rerun", "-PregenFixtures=1", "--console=plain"],
          cwd: manifest.androidDir, extraEnv: gradleEnvironment(), logName: "record"))
    } else {
      var arguments = ["swift", "test"]
      if let scenario = feature?.scenario {
        let className = URL(fileURLWithPath: scenario)
          .deletingPathExtension().lastPathComponent
        arguments += ["--filter", className]
      }
      result = finish(
        try launch(
          arguments, cwd: manifest.swiftPackageDir,
          extraEnv: ["REGEN_FIXTURES": "1"], logName: "record"))
    }
    if result.exitCode != 0 {
      let log = (try? String(contentsOf: result.logURL, encoding: .utf8)) ?? ""
      if options.json {
        emitJSON(["status": "failed", "log": log])
      } else {
        print(log.split(separator: "\n").suffix(30).joined(separator: "\n"))
        print("duet record: FAIL — fixtures not (fully) regenerated")
      }
      return 1
    }
    // The Kotlin runner records to compact artifacts (it ships no on-disk writer);
    // materialize them through the one §6 writer. The Swift runner writes files
    // directly through the same writer — its pass leaves no artifacts.
    _ = try RecordArtifacts.materialize(repo)
    let after = fixtureDigests(repo)
    let changed = after
      .filter { name, digest in before[name] != digest }
      .keys.sorted()
    if options.check {
      if options.json {
        emitJSON(["status": changed.isEmpty ? "passed" : "failed", "stale": Array(changed)])
      } else if changed.isEmpty {
        print("duet record --check: fixtures are up to date with their scenarios")
      } else {
        print("duet record --check: FAIL — \(changed.count) stale fixture(s) regenerated:")
        for file in changed { print("  parity/fixtures/\(file)") }
        print("commit the regenerated fixtures (R10: fixtures are build products)")
      }
      return changed.isEmpty ? 0 : 1
    }
    if options.json {
      emitJSON(["status": "passed", "regenerated": Array(changed)])
    } else {
      if changed.isEmpty {
        print("duet record: no fixture changes (recorded output identical)")
      } else {
        print("duet record: rewrote \(changed.count) fixture(s):")
        for file in changed { print("  parity/fixtures/\(file)") }
        print("review the diff (git diff -- parity/fixtures), then run `duet verify` for both lanes")
      }
    }
    return 0
  }

  private static func fixtureDigests(_ repo: Repo) -> [String: Int] {
    var digests: [String: Int] = [:]
    for file in
      (try? FileManager.default.contentsOfDirectory(atPath: repo.fixturesDir.path)) ?? []
    where file.hasSuffix(".json") {
      let data = try? Data(contentsOf: repo.fixturesDir.appendingPathComponent(file))
      digests[file] = data?.hashValue ?? 0
    }
    return digests
  }

  static func emitJSON(_ object: [String: Any]) {
    if let data = try? JSONSerialization.data(
      withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    {
      print(text)
    }
  }
}
