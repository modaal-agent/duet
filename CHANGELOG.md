# Changelog

## [0.1.0] — 2026-07-29

The first tagged code release: the Swift-flavor extraction — the framework's
first code drop — the KMP flavor's packaging (F3), and the toolchain (F4).
This tag is the anchor for URL-based SPM consumption
(`.package(url: "…/duet.git", exact: "0.1.0")`); pre-1.0, breaking changes
land in minor versions with no deprecation cycle, so consumers pin exact and
re-pin deliberately.

### Fixed — kotlin-authored scenarios can record from scratch (A1's gate run surfaced it)

- **`kernel-test` first-record semantics** (kotlin lane): `verifyOrRecord`'s
  verify half now reads the just-recorded compact artifact in a regen run
  (mirroring the Swift runner, whose record mode writes the fixture file and
  then verifies it), and `FixtureRunner.run` skips — with a note — a replay
  whose committed fixture doesn't exist yet during a regen run (this lane's
  artifacts are materialized by the CLI AFTER the test process exits, so on a
  repo's FIRST record the committed file cannot exist). Until now unreachable:
  the framework's own corpus is committed, and the twin-flavor playground
  authors scenarios Swift-side only — a single-source (KMP-flavor) adopter's
  first `duet record` hit both paths. (In the family: duet-tools learned
  kotlin-only manifests — no `swift:` twins → the Swift lane and its coverage
  half don't apply, `record` defaults to the kotlin runner, and KMP modules'
  lane task is `jvmTest`, since a KMP module has no aggregate `test` task —
  plus the manifest-level `replayRunner:` key for repos whose replay glue
  lives outside every feature package.)

### Fixed — the GA-toolchain floor, and a case-collision the floor work surfaced (post-S5b)

- **DuetTesting compiles on the GA toolchain line** (verified: Xcode 26.6 /
  Swift 6.3.3 — the adopter floor; the runtime products always compiled on
  26.x). The 6.3 sending analysis reported a phantom use-after-send at
  KernelTrace's lockstep yield — the element is forwarded exactly once, which
  Swift 6.4 proves unaided — now suppressed by a documented one-line
  `nonisolated(unsafe)` binding at that yield. The swift CI job is a two-lane
  matrix (macos-26 pinned to 26.6 + xcode-27's default beta), fail-fast off.
- **(family: duet-tools) the CLI's module renamed `duet` → `DuetCLI`** — the
  product, binary, and `swift run duet` are unchanged. A module literally
  named `duet` collides case-insensitively with the `Duet` library module, so
  on default (case-insensitive) APFS — every hosted CI runner, most machines —
  the toolchain package could not build at all, under any toolchain. Masked
  until now by a case-sensitive dev volume.

### Added — CI templates and the verification MCP surface (F4·S5b)

- **`ci/`** — the adopter parity template (`adopter-parity.yml`: spec-fixture
  lint → `duet verify` → `duet record --check`, with the private-phase steps
  marked for wholesale deletion at publication) plus `ci/README.md`; this repo
  and duet-tools each gained their own `.github/workflows/ci.yml` running
  exactly the CONTRIBUTING "Building" commands. The workflows first execute on
  GitHub at the public flip; the **Modaal-free receipt run** (F4's open gate,
  2026-07-25) proved every one of them green from clean clones of the three
  open repos — adopter corpus verify 122/122 dual-lane, `record --check`
  zero-churn, both flavor suites, both lints — with zero Modaal product bits
  in the loop.
- **`duet mcp`** (in the family: duet-tools) — the standalone agent surface
  (the toolchain plan's §5): a stdio MCP server over the same verification
  verbs (`duet_verify`/`duet_record`/`duet_explain`/`duet_materialize`/
  `duet_scope`), hand-rolled JSON-RPC, zero new dependencies. Tool results are
  the verbs' `--json` reports (returned as `structuredContent` too); the
  authoring verbs are deliberately not served. One `mcpServers` entry gives
  any agent harness the toolchain.

### Added — the flavor-lockstep lint, the parity ledger, and the workers page (F4·S5, G4)

- **`scripts/flavor-lockstep-lint.py`** — the framework's own contract surfaces
  are now twin-mapped (`parity/flavor-parity.yaml`: 22 pairs, 22 declared
  single-flavor files across kernel/replay/shells/testing) and gated: a public
  symbol landing on one flavor without its twin fails the lint unless a per-pair
  delta is declared with a reason. Coverage is closed — a NEW production file on
  either flavor fails until the map says what it is. Errors are self-teaching
  (each names the fix: mirror the symbol, or declare the delta).
- **`parity/flavor-parity-ledger.md`** — generated per-release measurement (LOC
  and open deltas per flavor, per surface; regenerate with `--write-ledger`,
  freshness gated by the default lint run). The dual-flavor revisit trigger now
  fires on a number, not a vibe. First measurement: 22 pairs, 36 open deltas —
  all of them named idioms (casing, argument-label flattening, sealed-case
  types, result-builder plumbing), zero semantic divergences.
- **`docs/workers.md`** — the worker pattern page: `Working`, the
  `StoreHost.adopt` bracket, `WorkerTester` and its leak guarantee, the named
  ingress shapes, and the logical-tests-only stance.

### Changed — the toolchain moves to its own repo; the ceremony killer lands (F4·S3, G2)

- **`tools/` extracted to [`modaal-agent/duet-tools`](https://github.com/modaal-agent/duet-tools)**
  — SwiftPM resolves one URL package per repository root, and the toolchain now
  carries a tool-side swift-syntax pin (the codegen verb), which must never
  enter a library consumer's graph. This repo is again a single, zero-dependency
  URL-consumable package; the README's repository-family table is the map.
- **The Swift ceremony killer shipped** (in the family, not this repo):
  `duet canonical-sum [--check]` in duet-tools — zero-config scan for enums
  declaring the `CanonicalSumCodable` marker protocol (this repo's kernel; its
  sentinel defeats SE-0295 silent synthesis, so a missing generated file fails
  at the enum declaration), one committed `…Serialization.generated.swift` per
  source, **regen folded into `duet record`** and **drift into
  `duet record --check`** (§2.2's "no separate pipeline step") — and the
  `@CanonicalSum` macro as the SUPPORTED OPT-IN in
  [`modaal-agent/duet-macros`](https://github.com/modaal-agent/duet-macros)
  (its own repo: a macro pins swift-syntax into every consumer graph). Both
  vehicles assemble from **one emission rule-set** (`CanonicalSumEmission`,
  exported by duet-tools) — FC3's copy-paste twins are dead; the **arms'
  lockstep gate** pins the same worst-case enum byte-for-byte in both repos'
  tests, so an emission change must consciously update both in one commit.

### Changed — one §6 writer (F4·S2, G1)

- **The §6 pretty writer has exactly ONE implementation** —
  `DuetReplay.ReplayCanonical.prettyCanonicalString` (XCTest-free, hosted by the
  CLI and by `DuetTesting`'s facade). The Kotlin flavor ships **no pretty writer
  at all**: `CanonicalJson.prettyCanonicalString` and the unconsumed
  `BoundaryReplay.prettyCanonicalize` are deleted from `:kernel`. The Kotlin
  record mode now emits COMPACT canonical document artifacts under
  `parity/.runs/record/kotlin/`; the CLI materializes them into §6 fixture files
  (`duet record --platform kotlin`, or the new `duet write-fixtures` verb for a
  framework repo's own corpus). The on-disk form cannot drift per flavor by
  construction — the `PrettyWriterParity`-class proof pairs retire with the twin
  (the Swift-side receipt survives as `PrettyWriterStabilityTests`).
- **`duet writer-check` retired** — the FC3-a probe verb's job is done: the
  CLI-side writer IS the writer, and `duet record --check` is its standing byte
  gate. Chain-schema regeneration (the FC2 remainder) is covered by receipt: an
  unscoped `duet record` regenerates the full corpus — 46 leaf + 15 chain
  fixtures — byte-identically through the one writer.
- `kotlin/` root build gains the `-PregenFixtures=1` → `duet.regenFixtures`
  system-property mapping (the same channel an adopter repo wires — env vars do
  not survive the Gradle daemon boundary).

### Added — the `duet` CLI (`tools/duet`, F4·S1)

- **The open toolchain CLI**, extracted from the reference playground's
  `tools/verify` and renamed to its real verb surface: `duet verify` (meta-checks
  + both platform lanes in parallel + the coverage gate), `duet record`
  (scenario-driven fixture regeneration; `--check` = the R10 CI drift gate),
  `duet explain`, `duet materialize`, `duet protocol-run` (the flavor-neutral
  replay-protocol lane — leaves AND chains through the one `reduce` op;
  `--runner` drives any conforming flavor runner), and `duet writer-check`
  (retires when the writer move lands at F4·S2). Its own SPM package under
  `tools/` — library consumers never resolve it; zero third-party dependencies.
- **Repo-layout neutrality**: the CLI discovers the adopter repo root via
  `parity/fixtures` and derives the platform roots from the repo's own parity
  manifest (the `swift:` path prefix before `/Sources/`; the first component of
  the `kotlin:` path) — no hardcoded tree shape, no machine-specific SDK
  fallback (the Android SDK is repo/machine config: `local.properties` sdk.dir
  or the caller's ANDROID_HOME; the CLI adds neither).
- **One compact writer**: the CLI's byte-gate currency is `DuetReplay`'s
  `ReplayCanonical` — the same writer the replay servers run — so the CLI cannot
  drift from the flavor it gates (G1). The §6 pretty writer lives CLI-side,
  proven byte-identical against the reference corpus by `writer-check`.

### Added — the KMP flavor (`kotlin/`, F3)

- **`dev.modaal.duet:kernel`** — the KMP flavor's core (commonMain): the
  `Store` runtime, `Effect` as data, the `KernelClock` seam, canonical
  serialization (the multiplatform writer, the FC2-derived
  `CanonicalSumSerializer` + registry convention, the pinned configuration,
  platform Instant/UUID serializers), and the boundary adapters — the
  registry-driven replay surface (`ReplayFeature`/`ReplayRegistry`/
  `BoundaryReplay`/`ReplayServer`) and `SpineBoundary` (spine persistence as
  core String functions). Targets: JVM (the host lane Android consumers
  resolve) + the Apple slices aggregated into the `DuetKernel` XCFramework
  (SKIE route; static). One kernel alignment fell out of the G3 gate, exactly
  as designed: **handler invocation moved into `execute`** (synchronous with
  effect start, matching the Swift flavor) — the `cancel-in-flight` restart
  interleaving is unreachable otherwise.
- **`dev.modaal.duet:kernel-test`** — the host-lane test support (JVM): the
  scenario DSL (feature dialect + branch expansion) and record/verify runners
  ported from the reference corpus (the lane's SOLE WRITER; regen via
  `REGEN_FIXTURES=1` / `-Dduet.regenFixtures=1`), fixture replay with
  first-divergence reporting, run reports, `ChainRunner`, the exhaustive
  `TestStore`, `WorkerTester`, the deterministic-async toolkit's Kotlin half,
  and the kernel-trace apparatus. Platform finding, encoded in `settleUntil`:
  coroutine-test's `advanceUntilIdle` is FOREGROUND-filtered — background-scope
  work (workers, shell observations) drains via `runCurrent`/`yield`, and
  virtual time stays an explicit act (`advanceTimeBy`).
- **`dev.modaal.duet:shells-compose`** — the shell half's twins (C6, the
  mirror rule), headless by design (no Compose dependency). Config-change
  stance per doc 20 Q2: hosts live in the RETAINED/logical scope —
  InstanceKeeper as substrate, not API (test-scope dependency only; the
  RetainedScopeTest receipt confirms rotation never crosses the worker
  bracket).
- **Kernel-trace fixtures, both flavors — kernel contract v1 FROZEN**: the
  KMP kernel replays all six committed Swift-recorded traces BYTE-IDENTICALLY
  under coroutine virtual time (repeat-stable; negative control trips). The
  Swift recorder stays the writer of record. Lockstep is structural on Kotlin
  (Flow `emit` reduces synchronously in the collector); the log needs no lock
  (single-threaded virtual scheduler).
- **The replay protocol formalized as v1** (`contracts/replay-protocol-v1.md`)
  — the versioned flavor seam: JSON-lines stdio, ONE `reduce` op (trees in,
  canonical strings out), chains via CLI-side per-node state slots, `record`/
  `--check` through the CLI-side §6 writer. Both servers stamp v1; a
  conforming runner is the flavor's whole obligation.
- **The SKIE packaging receipt** (`kotlin/consumer-receipt/` +
  `kotlin/scripts/xcframework-receipt.sh`): the app-shaped framework (kernel +
  a commonMain receipt feature) built via SKIE, with a Swift consumer
  replaying the committed kotlin-corpus fixtures across the boundary.

#### Twin thinness record (the C6 exit criterion)

| Twin | LOC (K) | Thinness vs the Swift realization |
| --- | --- | --- |
| `StoreHost` + `Working`/`adopt` | ~110 | same duties; scope-parameterized (coroutine structured concurrency replaces ambient `Task`); `adoptTeardown` named (SAM ambiguity) |
| `ChildStores`/`ChildSlot` | ~90 | duty-identical port; main-confined by contract instead of `@MainActor` |
| `ProjectionJoin`/`StateTransitions` | ~110 | R13 duties identical; collection rides the host scope — a reduce is observed within the same main-loop turn, not before `send` returns (StateFlow conflation coalesces intermediates; value-driven appliers make both safe) |
| `Relay` | ~15 | verbatim twin |
| `PresentationRegistry` | ~50 | generic over `Surface` where Swift pins `AnyView` (no erasure type needed; keeps the artifact Compose-free); sealed-leaf → root-registration resolution via `isInstance` |
| Handles (`Activatable`, `StoreChild`, `ViewShellChild`) | ~45 | carry ONLY the activate/teardown ordering contract — Compose composition lifetimes absorb the view half (S4-Q4) |
| `KernelClock` | ~15 | the seam alone: coroutine virtual time IS the test realization (no `TestClock` type) |
| `WorkerTester` | ~60 | same guarantees; no lock (virtual scheduler), no main-loop-pumping caveats |
| `untilCancelled` | 1 | `awaitCancellation` — the platform provides the park |

### Changed

- **The manifest moved to the repo root** (`Package.swift`; sources stay under
  `swift/`, targets carry explicit `path:`s). SwiftPM resolves `.package(url:)`
  dependencies against the repository root only, so this is the URL-consumable
  public shape — `.package(url: "…/duet.git", from: …)` now works once the repo
  is published. One URL-resolvable package per repo: the CombineRIBs coexistence
  helpers live in their own repo (`duet-migration`) so this package's dependency
  graph stays RIBs-free for every consumer.

### Added

- **The deterministic-async toolkit v1** (F2·S5, spec 15 §6.3) — the corpus's
  flake-class fixes productized in `DuetTesting`: `settleUntil` /
  `settle(byResending:until:)` (turn control + the re-send-until-projected
  pattern, class B), `ChildDeallocLedger` (the churn-ledger weak-tracking
  assertion, first-class), `SuiteWallClockBudget` (the degraded-host signature
  as an opt-in diagnostic — never a bound-widening prompt), and
  `SuitePollingDefaults` (the suite-wide bounds as values, assertion-library
  agnostic). Virtual time (`TestClock`) predates the slice.

- **Kernel-trace fixtures, v0** (F2·S5, spec 18 G3 — Swift side): the
  contract-observable runtime rules recorded as replayable canonical traces
  under virtual time — `KernelTraceRecorder`/`KernelTraceEvent` (`DuetTesting`)
  plus six rule fixtures (`swift/Tests/parity/fixtures/kernel-trace/`:
  send-reduce-sync, effect-start-order, effect-roundtrip, cancel-in-flight,
  teardown-cancels, reentrancy-queue) with a byte gate (REGEN_FIXTURES=1 to
  re-record). Design contract: [contracts/kernel-trace-v0.md](contracts/kernel-trace-v0.md)
  — lockstep delivery (delivery order IS reduce order) and
  one-ending-per-window (cross-effect ending order is contract-undefined);
  the Kotlin kernel reproduces the traces at F3, then kernel contract v1
  freezes.

- **The node-lifecycle piece** (F2·S4, spec 15 §3.3) — what retires the six
  RIBs symbols: `Activatable` (the handles' main-actor lifecycle surface,
  replacing the erased `Interactable`) and `ViewShell` (an `isActive` latch,
  `bind()`/`unbind()` hooks, and an owned `StoreHost` that unwinds at
  `deactivate()` — replaces `PresentableInteractor`/`Interactor`/`Presentable`;
  presenter references become plain properties). Decision of record: a CLASS,
  not a protocol-with-default-implementation — the latch and host are stored
  state. The generic handle vocabulary moves framework-side with it:
  `StoreChild` (owned store: `teardown()` = shell down, then store) and
  `ViewShellChild` (hoisted store: activate/deactivate only), UIKit-gated
  (`#if canImport(UIKit)` — receipts live in the consuming app's churn specs;
  the macOS host lane carries the `ViewShell` latch/ordering receipts).

- **The worker seam** — lifecycle-bound stateful processing (the RIBs Worker
  role, re-substrated on structured concurrency): the freestanding `Working`
  protocol (`run() async` is the worker's whole life; cancellation IS stop)
  with the `untilCancelled()` park for subscription-shaped machinery
  (`DuetShells`); `StoreHost.adopt(_ worker:)` — registration starts `run()`
  in registration order, `teardownAll()` cancels LIFO with everything else
  adopted, and the `liveWorkerCount` ledger makes the leak class observable;
  `WorkerTester` (`DuetTesting`) — the logical-test bracket whose `finish()`
  fails on a worker still running after cancellation, wall-clock-free by
  construction. Workers feed features only through the existing seams
  (environment streams / relayed actions); no fixture lane — workers carry
  logical tests only.

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
