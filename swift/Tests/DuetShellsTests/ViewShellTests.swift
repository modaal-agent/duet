// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Duet
import DuetShells
import Foundation
import XCTest

/// ViewShell receipts (spec 15 §3.3 — the node-lifecycle piece): the `isActive`
/// latch dedupes the bracket, `unbind()` runs BEFORE the host unwinds, the
/// owned host tears down everything `bind()` registered, and re-activation
/// re-runs `bind()` against the re-armed host.
@MainActor
final class ViewShellTests: XCTestCase {

  func testActivateLatchesAndBindsOnce() {
    let shell = RecordingShell()
    shell.activate()
    shell.activate()
    XCTAssertTrue(shell.isActive)
    XCTAssertEqual(shell.events, ["bind"], "a second activate is inert (the latch)")
  }

  func testDeactivateUnbindsThenUnwindsTheHost() {
    let shell = RecordingShell()
    shell.activate()
    shell.host.adopt(teardown: { shell.events.append("host teardown") })
    shell.deactivate()
    XCTAssertFalse(shell.isActive)
    XCTAssertEqual(
      shell.events, ["bind", "unbind", "host teardown"],
      "unbind runs before the host unwinds; deactivate without activate would be inert")

    shell.deactivate()
    XCTAssertEqual(shell.events.count, 3, "a second deactivate is inert (the latch)")
  }

  func testReactivationRebindsAgainstTheRearmedHost() {
    let shell = RecordingShell()
    shell.activate()
    shell.deactivate()
    shell.activate()
    shell.host.adopt(teardown: { shell.events.append("host teardown 2") })
    shell.deactivate()
    XCTAssertEqual(
      shell.events, ["bind", "unbind", "bind", "unbind", "host teardown 2"],
      "re-activation is legal: bind re-runs and the host re-arms")
  }
}

// MARK: - Fixtures

@MainActor
private final class RecordingShell: ViewShell {
  var events: [String] = []
  override func bind() { events.append("bind") }
  override func unbind() { events.append("unbind") }
}
