# Duet

One score, two performers. Duet is a framework for building iOS and Android apps as verifiable twins: shared pure logic, platform-native UI, and a recorded fixture corpus that both platforms must replay **byte-identically**. Record a feature's behavior on one platform, verify it on the other — parity is a CI gate, not a code-review aspiration.

> **Status: pre-release.** The Swift-flavor extraction has landed in-repo (`swift/` — kernel, shells, replay protocol, test support; strict-concurrency-complete, tests green) together with the normative contracts (`contracts/`). No artifacts are published yet, and the toolchain CLI is still to come — treat the API surface as a preview until the first tagged release.

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

This repository is the complete, self-sufficient framework: everything a project needs to build, gate, and evolve a Duet app **without any commercial dependency** —

- the kernel and shell runtime (both flavors),
- the test support: scenario DSL, deterministic-async toolkit (virtual time, turn control),
- the `duet` CLI: `verify`, `record`, `record --check`, replay/diff/report machinery, the mock pipeline,
- the lint family and CI templates,
- the contracts (kernel contract, fixture schema, replay protocol) — versioned with the code.

Modaal's commercial side is the *authoring* service around the framework — scaffolding, code generation, migration audits, and agent tooling. The line is deliberate: anything the repo needs to gate itself is open, including fixture re-recording. The open CLI ships no upsell stubs — a verb either works here, or it doesn't exist here.

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
contracts/   the normative contracts, versioned with the code:
             store-kernel-contract.md · serialization.md · presentation-contract.md
```

The Kotlin (KMP) flavor and the `duet` CLI land per the roadmap below.

## Roadmap

1. **Swift-flavor extraction** — kernel, test support (scenario DSL, recorders, the
   record/`--check` machinery), generic shells, the replay-protocol adapter, contracts;
   strict-concurrency-complete (Swift 6 language mode) from the first extraction.
   **Landed** — see `swift/`.
2. **KMP-flavor packaging** — the `commonMain` kernel, serialization, boundary adapters, Compose shell primitives, published artifacts.
3. **Toolchain** — the `duet` CLI verb surface, CI templates, lint family, zero-config mock pipeline.
4. **Docs** — public contracts and guides, distinct from Modaal's product documentation.

Platform and toolchain requirements will be pinned with the first extraction release.

## License

MIT — see [LICENSE](LICENSE).
