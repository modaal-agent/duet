// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetShells
import XCTest

/// Reconciler receipts (shell duties 2+4): build on route appearance, tear down on
/// route disappearance, share by identity — the churn discipline the composed
/// churn drills pin app-side, receipted here on the primitives alone.
@MainActor
final class ChildReconcilerTests: XCTestCase {

  // MARK: - ChildStores (stack routes)

  func testReconcileBuildsNewcomersAndTearsDownLeavers() {
    var torn: [String] = []
    let children = ChildStores<Int, String>(
      build: { "child-\($0)" },
      teardown: { torn.append($0) })

    children.reconcile(keys: [1, 2])
    XCTAssertEqual(children.activeCount, 2)
    XCTAssertEqual(torn, [])

    children.reconcile(keys: [2, 3])
    XCTAssertEqual(children.activeCount, 2)
    XCTAssertEqual(torn, ["child-1"])

    children.teardownAll()
    XCTAssertEqual(children.activeCount, 0)
    XCTAssertEqual(Set(torn), ["child-1", "child-2", "child-3"])
  }

  func testHandleForKeySharesOneChildPerIdentityAndBuildsLazily() {
    var built = 0
    let children = ChildStores<Int, String>(
      build: { built += 1; return "child-\($0)" },
      teardown: { _ in })

    // Lazy pull (the navigationDestination path)…
    XCTAssertEqual(children.handle(for: 5), "child-5")
    // …and the byte-identical key shares the one child (one source of truth).
    XCTAssertEqual(children.handle(for: 5), "child-5")
    XCTAssertEqual(built, 1)
  }

  func testDecliningBuilderYieldsNoHandle() {
    let children = ChildStores<Int, String>(
      build: { _ in nil },
      teardown: { _ in })

    XCTAssertNil(children.handle(for: 9))
    XCTAssertEqual(children.activeCount, 0)
  }

  // MARK: - ChildSlot (modal routes)

  func testSlotRebuildsOnKeyChangeAndDrainsOnNil() {
    var torn: [String] = []
    let slot = ChildSlot<String, String>(
      build: { "sheet-\($0)" },
      teardown: { torn.append($0) })

    slot.reconcile(key: "picker")
    XCTAssertEqual(slot.activeKey, "picker")
    XCTAssertEqual(slot.activeHandle, "sheet-picker")

    // Same key: no churn.
    slot.reconcile(key: "picker")
    XCTAssertEqual(torn, [])

    // Key change: the old child dies BEFORE the new one is built.
    slot.reconcile(key: "invite")
    XCTAssertEqual(torn, ["sheet-picker"])
    XCTAssertEqual(slot.activeHandle, "sheet-invite")

    // Clearing the route drains the slot.
    slot.reconcile(key: nil)
    XCTAssertEqual(torn, ["sheet-picker", "sheet-invite"])
    XCTAssertNil(slot.activeKey)
  }
}
