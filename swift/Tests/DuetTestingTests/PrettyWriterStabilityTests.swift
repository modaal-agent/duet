// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetTesting
import Foundation
import XCTest

/// §6 writer stability, pinned through the committed fixtures themselves: every
/// fixture on disk, re-emitted by THE pretty writer (ReplayCanonical — the one
/// implementation; the Kotlin flavor ships none), must be
/// byte-identical to the file. This is the framework-side receipt that the
/// on-disk form cannot drift; adopter repos get the same guarantee from
/// `duet record --check`.
final class PrettyWriterStabilityTests: XCTestCase {
  func testCommittedFixturesAreWriterStable() throws {
    let directory = try FixtureRunner.fixturesDirectory()
    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasSuffix(".fixture.json") }
      .sorted()
    XCTAssertFalse(files.isEmpty, "no fixtures found — wrong directory?")
    for file in files {
      let url = directory.appendingPathComponent(file)
      let data = try Data(contentsOf: url)
      let tree = try JSONSerialization.jsonObject(with: data)
      let reEmitted = try CanonicalJSON.prettyCanonicalString(fromJSONObject: tree)
      XCTAssertEqual(
        String(data: data, encoding: .utf8), reEmitted,
        "\(file) is not §6 writer-stable — regenerate: REGEN_FIXTURES=1 swift test")
    }
  }
}
