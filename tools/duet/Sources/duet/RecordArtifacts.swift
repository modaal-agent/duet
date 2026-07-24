// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetReplay
import Foundation

/// The one-writer half of `duet record` (F4·S2, G1): flavor runners' record modes
/// emit COMPACT canonical document artifacts under `parity/.runs/record/<platform>/`;
/// this materializes them into §6 pretty fixture files through the framework's one
/// pretty writer (`ReplayCanonical`). Also the standalone `duet write-fixtures`
/// verb — the path a framework repo uses to regenerate its own corpus (discovery
/// only, no manifest required).
enum RecordArtifacts {
  static func recordDir(_ repo: Repo) -> URL {
    repo.runsDir.appendingPathComponent("record")
  }

  static func clear(_ repo: Repo) {
    try? FileManager.default.removeItem(at: recordDir(repo))
  }

  /// Materializes every artifact into parity/fixtures; returns the file names written.
  static func materialize(_ repo: Repo) throws -> [String] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: recordDir(repo), includingPropertiesForKeys: nil)
    else { return [] }
    var artifacts: [URL] = []
    for case let url as URL in enumerator
    where url.lastPathComponent.hasSuffix(".fixture.json") {
      artifacts.append(url)
    }
    var written: [String] = []
    for url in artifacts.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      let tree = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
      let pretty = try ReplayCanonical.prettyCanonicalString(fromJSONObject: tree)
      try Data(pretty.utf8)
        .write(to: repo.fixturesDir.appendingPathComponent(url.lastPathComponent))
      written.append(url.lastPathComponent)
    }
    return written
  }

  /// `duet write-fixtures [--json]`
  static func run(repo: Repo, options: Options) throws -> Int32 {
    let written = try materialize(repo)
    if options.json {
      Lanes.emitJSON([
        "status": written.isEmpty ? "no-artifacts" : "written", "written": written,
      ])
      return written.isEmpty ? 1 : 0
    }
    if written.isEmpty {
      print(
        "duet write-fixtures: no record artifacts under parity/.runs/record — "
          + "run a record pass first (REGEN_FIXTURES=1 / -PregenFixtures=1)")
      return 1
    }
    print("duet write-fixtures: materialized \(written.count) fixture file(s):")
    for name in written { print("  parity/fixtures/\(name)") }
    return 0
  }
}
