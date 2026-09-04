# Duet

[![ci](https://github.com/modaal-agent/duet/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/modaal-agent/duet/actions/workflows/ci.yml)

One score, two performers. Duet is a framework for building iOS and Android apps as verifiable twins: shared pure logic, platform-native UI, and a recorded fixture corpus that both platforms must replay **byte-identically**. Record a feature's behavior on one platform, verify it on the other — parity is a CI gate, not a code-review aspiration.

> **Status: pre-release, current line 0.7.0.** Both flavors, the contracts and the toolchain have landed. The Swift packages resolve by URL at a tag; the Kotlin artifacts resolve from the family's static Maven repository (`https://modaal-agent.github.io/maven` — the repository block is in `kotlin/README.md`). Pre-1.0 minors are breaking by family convention, so pin exactly. [CHANGELOG.md](CHANGELOG.md) states what each release carries and which flavor it touches — several releases are Swift-only in effect, and say so.

The CI matrix (each job writes its toolchain and verdict to the run's job summary):

| lane | toolchain | proves |
| --- | --- | --- |
| `swift` · macos-26 | Xcode 26.6 (Swift 6.3.3) | the GA floor — the adopter toolchain |
| `swift` · xcode-27 | Xcode 27 beta (Swift 6.4) | the newest proven line |
| `kotlin` | Temurin 25 · Gradle 9.7.1 · Kotlin 2.4.10 | the KMP flavor suites (pure KMP — no Android SDK) |
| `flavor-lockstep` | python3 | one contract surface across the two flavors, ledger fresh |

A release tag additionally runs `publish.yml`: the Kotlin artifacts are built with the version derived from the tag and landed on the Maven host as one commit; an existing version is never overwritten.

## Why

Teams shipping the same product on iOS and Android pay twice for every feature — and then keep paying, because nothing *proves* the two implementations agree. Screenshot tests diff pixels; shared-UI frameworks trade away native look and feel; hand-discipline drifts.

Duet takes a different position:

- **Logic is shared and pure.** Features are reducers over typed state, with effects as data — deterministic by construction, serialized through one canonical dialect.
- **UI is native and thin.** SwiftUI on Apple platforms, Compose on Android. Navigation is state; shells render it. There is no cross-platform UI layer to fight.
- **Parity is measured, not promised.** Feature behavior is recorded as fixtures — scenario in, canonical state/output trace out. Both platforms replay the same fixtures; the gate is byte equality. A drift on either side is a red build, not a bug report from a user.

The loop, end to end:

```
spec → scenario → duet record   (fixtures captured on one platform)
     → port      → duet verify  (the twin replays them byte-identically)
     → CI        → duet record --check  (regenerate-and-fail-if-changed drift gate)
```

## The core and its two flavors

The **core** is the pure half of an app: kernel, reducers, state and event types, serialization, boundary adapters. It has two interchangeable realizations under one contract:

- **KMP flavor** — the core lives in Kotlin Multiplatform `commonMain`; both apps consume it natively. The default for dual-platform projects: logic is written once.
- **Swift flavor** — the same contract implemented in pure Swift, no Kotlin toolchain in the project. For Apple-only projects, and a hard requirement rather than a convenience: Mac Catalyst and visionOS have no Kotlin/Native target, and an Apple-only team shouldn't pay an FFI toolchain for portability it isn't using.

Both flavors share one invariant spine — the kernel contract, the canonical fixture dialect and schema, the record/verify/`--check` methodology, scenario semantics, the lint family, and the CLI verb surface. A Swift-flavor project that later goes dual hoists its reducers into the KMP flavor mechanically, gated by its own fixtures. Conformance has an operational definition: *speaks the replay protocol, passes the corpus.*

## What ships here (the open boundary)

The **Duet repository family** is the complete, self-sufficient framework: everything a project needs to build, gate, and evolve a Duet app **without any commercial dependency** —

- the kernel and shell runtime (both flavors) — **this repo**,
- the test support: scenario DSL, deterministic-async toolkit (virtual time, turn control), fixture recorder and runner — **this repo**,
- the contracts (kernel contract, serialization, replay protocol, presentation, mock dialect) — versioned with the code, **this repo**,
- the `duet` CLI: `verify`, `record`, `record --check`, `lint`, `doctor`, `mutate`, the codegen verbs, the stdio MCP server (`duet mcp`) — [`duet-tools`](https://github.com/modaal-agent/duet-tools),
- the services layer an app adopts at its composition root: diagnostics, app services, telemetry, theming — [`duet-services`](https://github.com/modaal-agent/duet-services),
- the `@CanonicalSum` macro opt-in — [`duet-macros`](https://github.com/modaal-agent/duet-macros),
- the CombineRIBs coexistence shim for the length of a migration — [`duet-migration`](https://github.com/modaal-agent/duet-migration),
- the lint family (`scripts/`, `parity/`) and the adopter CI template (`ci/`) — **this repo**.

Modaal's commercial side is the *authoring* service around the framework — scaffolding, code generation, migration audits, and agent tooling. The line is deliberate: anything the repo needs to gate itself is open, including fixture re-recording. The open CLI ships no upsell stubs — a verb either works here, or it doesn't exist here.

### The repository family

One package per repository — SwiftPM resolves `.package(url:)` against the repository root only, and dependency pins (swift-syntax, the frozen CombineRIBs fork) must never leak into graphs that didn't ask for them:

| Repo | Ships | Why separate |
|---|---|---|
| [`duet`](https://github.com/modaal-agent/duet) | the framework: `Duet`/`DuetShells`/`DuetReplay`/`DuetTesting` (Swift flavor), `dev.modaal.duet:*` (KMP flavor), the contracts | the zero-dependency core — every consumer resolves this and nothing else |
| [`duet-tools`](https://github.com/modaal-agent/duet-tools) | the `duet` CLI + `CanonicalSumEmission` | carries the tool-side swift-syntax pin; library consumers never resolve it |
| [`duet-services`](https://github.com/modaal-agent/duet-services) | `DuetDiagnostics`/`DuetAppServices`/`DuetTelemetry`/`DuetTheming` and `dev.modaal.duet.services:telemetry`/`:theming` | the environment-side layer; pins this repo `exact:` and re-pins after each framework release |
| [`duet-macros`](https://github.com/modaal-agent/duet-macros) | `@CanonicalSum` (opt-in) | a macro pins swift-syntax into every consumer graph — only opting-in projects take it |
| [`duet-migration`](https://github.com/modaal-agent/duet-migration) | CombineRIBs coexistence shim + the port-or-delete recipe | pins the frozen RIBs fork; added for a migration, deleted at its end |

Beside the family, in the same organization: [`kotlin-ksp-mocks`](https://github.com/modaal-agent/kotlin-ksp-mocks) and [`swift-sourcery-templates`](https://github.com/modaal-agent/swift-sourcery-templates) generate test doubles in the mock dialect this repo's contract fixes, one per language; [`maven`](https://github.com/modaal-agent/maven) is the static host the Kotlin artifacts publish to.

## Identifiers

| Surface | Identifier |
|---|---|
| Repository | `github.com/modaal-agent/duet` |
| Swift packages (SPM) | `Duet`, `DuetShells`, `DuetTesting` (+ `DuetReplay`, the replay-protocol adapter) |
| Kotlin artifacts (Maven) | `dev.modaal.duet:kernel`, `dev.modaal.duet:kernel-test`, `dev.modaal.duet:shells-compose` |
| CLI | `duet` |
| MCP tools | `duet_*` |

## What is in the tree

The Swift flavor, four products under `swift/Sources/`:

| product | carries |
| --- | --- |
| `Duet` | the kernel: `Store`, `Effect` as data, the `Clock` seam, and the `CanonicalSumCodable` marker the sum-coder codegen keys on |
| `DuetShells` | the shell half: `StoreHost` with `host(_:)`/`adopt(_:)` (`Store` conforms to `HostedObservation` here, so a shell adopts a store the way it adopts any observation), the `Working` protocol, `ViewShell`, `ChildStores`/`ChildHandles` for state-driven child mounting, `ProjectionJoin`, `Relay` (a sink bound to a weak owner), `AnyActionHandler` (the view→shell event value), `PresentationRegistry`, `RouteSpineCodec`, and the Combine bridging |
| `DuetReplay` | the replay-protocol adapter: `ReplayFeature`, `ReplayServer`, the canonical replay encoding |
| `DuetTesting` | scenario DSL (feature and chain dialects), `ScenarioRunner`, `FixtureRecorder`/`FixtureRunner`/`FixtureDiff`, `TestStore`, `WorkerTester`, the deterministic-async toolkit and `TestClock`, `KernelTrace`, `ParityRunReport`, and the canonical JSON writer |

The KMP flavor, three published artifacts under `kotlin/` (group `dev.modaal.duet`; the fourth module, `consumer-receipt`, is the unpublished consumer build receipt):

| artifact | targets | carries |
| --- | --- | --- |
| `kernel` | `jvm`, `macosArm64`, `iosArm64`, `iosSimulatorArm64` (the `DuetKernel` static framework, SKIE route) | `Store`, `Effect`, `KernelClock`, canonical serialization (`CanonicalJson`, `CanonicalSumSerializer`, the instant and UUID serializers, `EffectJson`), store scopes, and the replay boundary (`ReplayFeature`, `ReplayServer`, `SpineBoundary`, `BoundaryReplay`) |
| `kernel-test` | `jvm` | the host-lane test support: scenario DSL and chain scenarios, `ScenarioRunner`/`ChainRunner`, `FixtureRunner`/`FixtureDiff`, `TestStore`, `WorkerTester`, `DeterministicAsync`, `KernelTrace`, `RunReport`, effect assertions |
| `shells-compose` | `jvm` | `StoreHost` + `Working`, `ChildStores`/`ChildHandles`, `ProjectionJoin`, `Relay`, `PresentationRegistry`, `RetainedRoot`, `RestoredSpineBox` — headless (coroutines/Flow only, no Compose dependency) |

Every shell-side symbol has a twin or a declared reason for having none; `parity/flavor-parity.yaml` is the map and `parity/flavor-parity-ledger.md` the generated per-release ledger the lint keeps fresh.

## Contracts and pattern pages

The normative contracts under `contracts/`, versioned with the code:

| contract | status | fixes |
| --- | --- | --- |
| `store-kernel-contract.md` | v1, frozen | the State/Action/Effect shapes and the `Store` API both flavors implement |
| `serialization.md` | v0 | the one canonical JSON dialect both encoders produce — the sum-type `{"case": …}` form included |
| `replay-protocol-v1.md` | v1, normative | the wire shape a replay runner speaks; the flavor seam |
| `presentation-contract.md` | v1.0, normative | state-driven presentation: the presentation tree in state and how each platform renders it |
| `kernel-trace-v0.md` | executed | the cross-flavor kernel-trace gate behind the frozen kernel contract |
| `mock-dialect-v1.md` | v1, normative | the member vocabulary generated test doubles expose, identically on both flavors |

The pattern pages under `docs/`: [`workers.md`](docs/workers.md) — lifecycle-bound stateful processing, the layer between platform services and pure logic; [`composition.md`](docs/composition.md) — the `<X>Dependency` + `<X>Component` pair at every composition level, the scope-ownership contract, and factory placement.

## Repository layout

```
Package.swift  the SPM manifest — at the repo root so `.package(url:)` resolves it
               (SwiftPM reads remote manifests from the repository root only)
swift/       the Swift flavor's sources (Duet, DuetShells, DuetReplay, DuetTesting)
             + its test suites and their own fixture corpus (swift/Tests/parity/fixtures)
kotlin/      the KMP flavor: dev.modaal.duet:kernel / :kernel-test / :shells-compose
             (+ consumer-receipt, the unpublished consumer build receipt), the Gradle
             wrapper, and kotlin/scripts/ — the Maven publish gate and the XCFramework receipt
contracts/   the normative contracts, versioned with the code (the table above)
docs/        pattern pages that ship with the framework (workers.md · composition.md)
parity/      the flavor twin map (flavor-parity.yaml) + the generated per-release
             flavor-parity ledger — LOC and open deltas per flavor
scripts/     flavor-lockstep-lint.py, the twin-map gate (CONTRIBUTING, rule 1)
ci/          CI templates: the adopter parity workflow + notes; the family's own
             workflows live in .github/workflows/ (ci.yml, publish.yml)
```

## Toolchain floors

| flavor | floor |
| --- | --- |
| Swift | swift-tools-version 6.0, Swift 6 language mode with strict concurrency; iOS 16, macOS 13; verified on Xcode 26.6 (GA) and Xcode 27 beta |
| Kotlin | Kotlin 2.4.10, Gradle 9.7.1 (wrapper with a pinned distribution digest), JDK 25 toolchain; the KMP suites run with no Android SDK |

The toolchain and the macro opt-in live in their own repos (the family table above): the `duet` CLI runs against an adopter repo (root discovered via `parity/fixtures`, layout derived from the repo's own parity manifest). Each release publishes a prebuilt macOS binary; from a checkout:

```sh
swift run --package-path <duet-tools checkout> duet verify   # meta-checks + both lanes
swift run --package-path <duet-tools checkout> duet help     # the full verb surface
```

## Building

```sh
swift test                            # the Swift flavor's suites; replays swift/Tests/parity/fixtures
cd kotlin && ./gradlew test           # the KMP suites (pure KMP — no Android SDK needed)
python3 scripts/flavor-lockstep-lint.py   # coverage + pair surfaces + ledger freshness
```

CI runs exactly these commands. [CONTRIBUTING.md](CONTRIBUTING.md) states the development rules every PR is reviewed against, the release procedure (the tag is the version of record for both flavors), and the corpus rules the framework's own fixtures follow.

## License

MIT — see [LICENSE](LICENSE).
