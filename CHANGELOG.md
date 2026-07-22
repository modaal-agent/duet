# Changelog

## [Unreleased]

The Swift-flavor extraction — the framework's first code drop.

### Added

- **`swift/` — the Swift flavor as an SPM package**, all targets in Swift 6 language
  mode (strict concurrency complete) from birth:
  - **`Duet`** — the kernel: the `Store` runtime (synchronous reduce, queued
    reentrancy, teardown-cancels-everything), `Effect` as equatable data with
    cancel-in-flight identity, the `KernelClock` seam, and the `CanonicalSumCodable`
    marker protocol.
  - **`DuetShells`** — the app-agnostic composition glue: `StoreHost`,
    `ChildStores`/`ChildSlot` reconcilers, `ProjectionJoin`/`StateTransitions`,
    `Relay`, `PresentationRegistry`, the audited `kernelStream()` Combine bridge
    (now explicitly `Output: Sendable`), and the route-spine carrier
    (`RouteSpineCodec` + `RestoredSpineBox`), made generic over the app's spine type.
  - **`DuetReplay`** — the replay-protocol half, XCTest-free: the compact canonical
    writer/decoder, the typed `ReplayFeature` registry entry, and the JSON-lines
    `ReplayServer` (protocol v0) an app's replay-runner executable wraps in three lines.
  - **`DuetTesting`** — the in-process test support: the scenario DSL (feature +
    chain dialects, `Branch` expansion), record/verify runners, fixture replay with
    first-divergence reporting, run reports, `TestClock` virtual time, and the
    exhaustive `TestStore`. Fixture-directory resolution now always walks up from the
    CONSUMER's source paths, so the library works from a dependency checkout.
- **`contracts/`** — the three normative contracts (store kernel, canonical
  serialization, presentation), versioned with the code; module names updated to the
  Duet targets and internal references made self-contained.
- **Framework test suites** (44 tests) with their own fixture corpus under
  `swift/Tests/parity/fixtures/`, governed by the same corpus rules as a consuming
  repo: kernel runtime + TestStore receipts, shell-glue receipts (R13 join,
  reverse-order teardown, bridge cancellation), reconciler and spine receipts,
  scenario/chain DSL end-to-end (recorded fixtures + `linkToNext`), pretty-writer
  byte-stability, the formatter golden, replay-protocol receipts, and canonical
  scalar-rule receipts.

## [0.0.1] — 2026-07-22

Identity release. No published artifacts — this release fixes who the project is, under what terms, and what lands next.

### Added

- **Name and identifiers.** The framework is **Duet**: repository `github.com/modaal-agent/duet`; SPM products `Duet` / `DuetShells` / `DuetTesting`; Maven coordinates `dev.modaal.duet:kernel` / `:kernel-test` / `:shells-compose`; CLI `duet`; MCP tool namespace `duet_*`.
- **License.** MIT ([LICENSE](LICENSE)), copyright Modaal.dev. Contributions are inbound = outbound MIT; no CLA.
- **Contribution policy.** The conformance corpus is the contribution gate — corpus byte-green on every touched lane, re-record with the fixture diff as the review artifact, lockstep rule across the two core flavors ([CONTRIBUTING.md](CONTRIBUTING.md)).
- **Public identity and roadmap.** What Duet is, the core/flavor model, the open boundary (the repo is self-sufficient; no upsell stubs), and the extraction roadmap ([README.md](README.md)).
