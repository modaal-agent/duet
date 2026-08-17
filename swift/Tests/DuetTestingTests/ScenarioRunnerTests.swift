// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Duet
import DuetTesting
import XCTest

/// The scenario DSL end-to-end: this file is the SOURCE of the suite's
/// `counter*.fixture.json` files under `Tests/parity/fixtures/` (record with
/// `REGEN_FIXTURES=1 swift test`; fixtures are build products, never hand-edited).
/// The linear scenario receipts Given/When/Then/ThenEffects/Context; the branch
/// scenario receipts the static-fork expansion — one fixture per root→leaf path.
private let counterScenario = Scenario<CounterState, CounterAction, CounterEffectPayload>(
  feature: "counter",
  description:
    "The exemplar feature: state changes, guarded system action, effect emission "
    + "with cancel-in-flight id, explicit cancel."
) {
  Given(CounterState())

  When("increment", .increment)
  When("increment again", .increment)
  When("decrement", .decrement)
  When("a stray tick while auto-increment is off must not count", .tick)
  Then("net one after two ups, a down, and the guarded tick") { $0.count == 1 }

  When("toggling auto-increment on starts the ticker", .toggleAutoIncrement)
  ThenEffects("exactly the identified ticker effect") {
    $0 == [.run(.startTicker, id: CounterEffectIDs.ticker)]
  }
  When("a tick counts while auto-incrementing", .tick)
  When("a second tick counts", .tick)
  When("toggling auto-increment off cancels the ticker", .toggleAutoIncrement)
  ThenEffects("exactly the explicit cancel") {
    $0 == [.cancel(id: CounterEffectIDs.ticker)]
  }
  When("a tick after cancellation must not count", .tick)
  Then("the two live ticks stuck; the cancelled one didn't") { $0.count == 3 }
}

/// Static alternate endings (every branch always runs; each records its own
/// `counter-endings.<slug>.fixture.json`).
private let counterBranchScenario = Scenario<CounterState, CounterAction, CounterEffectPayload>(
  feature: "counter",
  fixture: "counter-endings",
  description: "Shared prefix with two static endings — the Branch expansion receipt."
) {
  Given(CounterState())

  When("increment", .increment)
  Then("one on the shared prefix") { $0.count == 1 }

  Branch("keeps counting") {
    When("increment again", .increment)
    Then("two on this ending") { $0.count == 2 }
  }
  Branch("changes its mind") {
    When("decrement", .decrement)
    Then("back to zero on this ending") { $0.count == 0 }
  }
}

final class ScenarioRunnerTests: XCTestCase {
  func testCounterScenario() throws {
    try ScenarioRunner.verifyOrRecord(counterScenario, reducer: counterReducer)
  }

  func testCounterBranchScenario() throws {
    try ScenarioRunner.verifyOrRecord(counterBranchScenario, reducer: counterReducer)
  }

  func testBranchExpansionYieldsOneFixturePerLeaf() throws {
    // The variant-naming contract, pinned via the COMMITTED fixtures (never by
    // re-recording here — a live record call would mask verify drift): one
    // `<fixture>.<slug>` file per root→leaf path, each carrying its branch path.
    let fixturesDir = try FixtureRunner.fixturesDirectory()
    for (name, branch) in [
      ("counter-endings.keeps-counting", "keeps-counting"),
      ("counter-endings.changes-its-mind", "changes-its-mind"),
    ] {
      let document = try FixtureRunner.Document.load(fixture: name, in: fixturesDir)
      XCTAssertEqual(document.dialect, 2)
      let tree = try JSONSerialization.jsonObject(
        with: Data(contentsOf: document.url)) as? [String: Any]
      let scenarioMeta = tree?["scenario"] as? [String: Any]
      XCTAssertEqual(scenarioMeta?["branch"] as? String, branch)
    }
  }
}
