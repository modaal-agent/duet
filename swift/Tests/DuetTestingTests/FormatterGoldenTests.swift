// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetTesting
import Foundation
import XCTest

/// The failure-block SHAPE is a cross-platform contract (one formatter per platform,
/// zero in the tools — the CLI prints reports' `rendered` verbatim). This pins it to
/// `Tests/parity/fixtures/formatter.golden.txt`; the Kotlin twin renders the same
/// synthetic failures against the same file, so the formatters stay lockstep.
final class FormatterGoldenTests: XCTestCase {
  func testFailureBlocksMatchGolden() throws {
    let chainDivergence = ParityRunFailure(
      step: 2, label: "the feed-share seam", line: 64, kind: "effects", node: "timeline",
      path: "[0].payload.value.friendIds[1]",
      expected: "\"friend-ben\"", actual: "\"friend-cara\"",
      action: "{\"case\":\"sharePicker\",\"value\":{\"case\":\"applied\"}}")
    let enrichedAssertion = ParityRunFailure(
      step: 8, label: "delegates › apply › applied carries dana", line: 70,
      kind: "assertion",
      path: "expectedState.selected[1].displayName",
      expected: "\"Dana\"", actual: "\"Ben\"",
      action: "{\"case\":\"applyTapped\"}",
      message: "Then returned false against the current state — the step's state also "
        + "diverged from the fixture")

    let rendered = [
      FixtureRunner.format(
        chainDivergence, fixture: "chain-share-apply",
        scenarioSource: "src-ios/Tests/ChainScenarioTests.swift", platform: "swift"),
      FixtureRunner.format(
        enrichedAssertion, fixture: "sharepicker.apply",
        scenarioSource: "src-ios/Tests/SharePickerScenarioTests.swift", platform: "swift"),
    ].joined(separator: "\n\n") + "\n"

    let goldenURL = try FixtureRunner.fixturesDirectory()
      .appendingPathComponent("formatter.golden.txt")
    let golden = try String(contentsOf: goldenURL, encoding: .utf8)
    XCTAssertEqual(golden, rendered, "formatter drifted from the cross-platform golden")
  }
}
