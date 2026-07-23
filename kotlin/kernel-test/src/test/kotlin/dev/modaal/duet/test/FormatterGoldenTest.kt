// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * The failure-block SHAPE is a cross-flavor contract (one formatter per
 * flavor, zero in the tools — `verify` prints reports' `rendered` verbatim).
 * This pins the Kotlin formatter to the SHARED golden
 * (swift/Tests/parity/fixtures/formatter.golden.txt — the same file the Swift
 * twin, FormatterGoldenTests.swift, renders against). Both tests pass
 * `platform = "swift"` explicitly so the golden text is shared — the parameter
 * is the only platform-dependent fragment.
 */
class FormatterGoldenTest {
  @Test
  fun failureBlocksMatchGolden() {
    val chainDivergence =
      ParityRunFailure(
        step = 2, label = "the feed-share seam", line = 64, kind = "effects",
        node = "timeline",
        path = "[0].payload.value.friendIds[1]",
        expected = "\"friend-ben\"", actual = "\"friend-cara\"",
        action = "{\"case\":\"sharePicker\",\"value\":{\"case\":\"applied\"}}")
    val enrichedAssertion =
      ParityRunFailure(
        step = 8, label = "delegates › apply › applied carries dana", line = 70,
        kind = "assertion",
        path = "expectedState.selected[1].displayName",
        expected = "\"Dana\"", actual = "\"Ben\"",
        action = "{\"case\":\"applyTapped\"}",
        message =
          "Then returned false against the current state — the step's state also " +
            "diverged from the fixture")

    val rendered =
      listOf(
        FixtureRunner.format(
          chainDivergence, "chain-share-apply",
          "src-ios/Tests/ChainScenarioTests.swift", platform = "swift"),
        FixtureRunner.format(
          enrichedAssertion, "sharepicker.apply",
          "src-ios/Tests/SharePickerScenarioTests.swift", platform = "swift"),
      ).joinToString("\n\n") + "\n"

    val golden = File(sharedFixturesDirectory(), "formatter.golden.txt").readText()
    assertEquals(golden, rendered, "formatter drifted from the cross-flavor golden")
  }

  /** The repo's shared cross-flavor fixture set (same resolver as the kernel traces). */
  private fun sharedFixturesDirectory(): File {
    var dir: File? = File(System.getProperty("user.dir")).absoluteFile
    while (dir != null) {
      val candidate = File(dir, "swift/Tests/parity/fixtures")
      if (candidate.isDirectory) return candidate
      dir = dir.parentFile
    }
    error("could not locate swift/Tests/parity/fixtures from ${System.getProperty("user.dir")}")
  }
}
