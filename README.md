# Duet

[![ci](https://github.com/modaal-agent/duet/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/modaal-agent/duet/actions/workflows/ci.yml)

One score, two performers. Duet is a framework for building iOS and Android apps as verifiable twins: shared pure logic, platform-native UI, and a recorded fixture corpus that both platforms must replay **byte-identically**. Record a feature's behavior on one platform, verify it on the other — parity is a CI gate, not a code-review aspiration.

> **Status: pre-release.** Both flavors and the toolchain have landed (`swift/`, `kotlin/`, the [`duet-tools`](https://github.com/modaal-agent/duet-tools) CLI) together with the normative contracts (`contracts/`). No artifacts are published yet — treat the API surface as a preview until the first tagged release.

The CI matrix (each job writes its toolchain and verdict to the run's job summary):

| lane | toolchain | proves |
| --- | --- | --- |
| `swift` · macos-26 | Xcode 26.6 (Swift 6.3.3) | the GA floor — the adopter toolchain |
| `swift` · xcode-27 | Xcode 27 beta (Swift 6.4) | the newest proven line |
| `kotlin` | Temurin 21 · Gradle | the KMP flavor suites (pure KMP — no Android SDK) |
| `flavor-lockstep` | python3 | one contract surface across the two flavors, ledger fresh |

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
- the test support: scenario DSL, deterministic-async toolkit (virtual time, turn control) — **this repo**,
- the `duet` CLI: `verify`, `record`, `record --check`, replay/diff/report machinery, the codegen verb, the stdio MCP server (`duet mcp`) — [`duet-tools`](https://github.com/modaal-agent/duet-tools),
- the `@CanonicalSum` macro opt-in — [`duet-macros`](https://github.com/modaal-agent/duet-macros),
- the lint family and CI templates,
- the contracts (kernel contract, fixture schema, replay protocol) — versioned with the code, **this repo**.

Modaal's commercial side is the *authoring* service around the framework — scaffolding, code generation, migration audits, and agent tooling. The line is deliberate: anything the repo needs to gate itself is open, including fixture re-recording. The open CLI ships no upsell stubs — a verb either works here, or it doesn't exist here.

### The repository family

One package per repository — SwiftPM resolves `.package(url:)` against the repository root only, and dependency pins (swift-syntax, the frozen CombineRIBs fork) must never leak into graphs that didn't ask for them:

| Repo | Ships | Why separate |
|---|---|---|
| [`duet`](https://github.com/modaal-agent/duet) | the framework: `Duet`/`DuetShells`/`DuetReplay`/`DuetTesting` (Swift flavor), `dev.modaal.duet:*` (KMP flavor), the contracts | the zero-dependency core — every consumer resolves this and nothing else |
| [`duet-tools`](https://github.com/modaal-agent/duet-tools) | the `duet` CLI + `CanonicalSumEmission` | carries the tool-side swift-syntax pin; library consumers never resolve it |
| [`duet-macros`](https://github.com/modaal-agent/duet-macros) | `@CanonicalSum` (opt-in) | a macro pins swift-syntax into every consumer graph — only opting-in projects take it |
| [`duet-migration`](https://github.com/modaal-agent/duet-migration) | CombineRIBs coexistence shim | pins the frozen RIBs fork; added for a migration, deleted at its end |

## Identifiers

| Surface | Identifier |
|---|---|
| Repository | `github.com/modaal-agent/duet` |
| Swift packages (SPM) | `Duet`, `DuetShells`, `DuetTesting` (+ `DuetReplay`, the replay-protocol adapter) |
| Kotlin artifacts (Maven) | `dev.modaal.duet:kernel`, `dev.modaal.duet:kernel-test`, `dev.modaal.duet:shells-compose` |
| CLI | `duet` |
| MCP tools | `duet_*` |

## Repository layout

```
Package.swift  the SPM manifest — at the repo root so `.package(url:)` resolves it
               (SwiftPM reads remote manifests from the repository root only)
swift/       the Swift flavor's sources (Duet, DuetShells, DuetReplay, DuetTesting)
             + its test suites and their own fixture corpus (swift/Tests/parity/fixtures)
kotlin/      the KMP flavor: Maven artifacts dev.modaal.duet:kernel / :kernel-test /
             :shells-compose (+ the DuetKernel XCFramework aggregation, SKIE route)
contracts/   the normative contracts, versioned with the code:
             store-kernel-contract.md · serialization.md · replay-protocol-v1.md ·
             kernel-trace-v0.md · presentation-contract.md
docs/        pattern pages that ship with the framework (workers.md · composition.md)
parity/      the flavor twin map (flavor-parity.yaml) + the generated per-release
             flavor-parity ledger — LOC and open deltas per flavor
scripts/     flavor-lockstep-lint.py, the twin-map gate (CONTRIBUTING, rule 1)
ci/          CI templates: the adopter parity workflow + notes; the family's own
             workflows live in .github/workflows/
```

The toolchain and the macro opt-in live in their own repos (the family table
above): the `duet` CLI runs against an adopter repo (root discovered via
`parity/fixtures`, layout derived from the repo's own parity manifest):

```sh
swift run --package-path <duet-tools checkout> duet verify   # meta-checks + both lanes
swift run --package-path <duet-tools checkout> duet help     # the full verb surface
```

## Roadmap

1. **Swift-flavor extraction** — kernel, test support (scenario DSL, recorders, the
   record/`--check` machinery), generic shells, the replay-protocol adapter, contracts;
   strict-concurrency-complete (Swift 6 language mode) from the first extraction.
   **Landed** — see `swift/`.
2. **KMP-flavor packaging** — the `commonMain` kernel, serialization, boundary adapters, Compose shell primitives, published artifacts. **Landed** — see `kotlin/`.
3. **Toolchain** — the `duet` CLI verb surface (**landed** — [`duet-tools`](https://github.com/modaal-agent/duet-tools)), the Swift ceremony killer (**landed** — `duet canonical-sum` + the [`@CanonicalSum`](https://github.com/modaal-agent/duet-macros) opt-in, one shared emission rule-set), the lint family (**landed** — the flavor-lockstep lint + flavor-parity ledger, `parity/`), CI templates (**landed** — `ci/` + each repo's own workflow), and the verification MCP surface (**landed** — `duet mcp`, a stdio MCP server over the same verbs).
4. **Docs** — public contracts and guides, distinct from Modaal's product documentation.

Platform and toolchain requirements will be pinned with the first extraction release.

## License

MIT — see [LICENSE](LICENSE).
