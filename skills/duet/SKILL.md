---
name: duet
description: "Build and change native iOS and Android apps on the Duet framework: feature logic as pure reducers over typed State, Action and Effect, SwiftUI and Jetpack Compose shells, and recorded fixtures both apps replay byte-identically in CI. Use when a tree has parity/manifest.yaml, parity/fixtures, tools/duet or parity/duet-tools.ref, or depends on dev.modaal.duet, dev.modaal.duet.services or the Swift packages Duet, DuetShells and DuetTesting; when asked to add or change a feature, write a scenario or a chain, record or verify fixtures, run duet verify, duet record --check, duet lint, duet doctor or duet mcp, mount a store in a shell, compose features with a Dependency and a Component, add a worker, adopt DuetTelemetry or DuetTheming, generate design tokens, or move the family pins; and when a fixture drifts in CI, verify stops at its meta-checks, a Kotlin exception terminates the iOS app, or SwiftPM cannot resolve two duet versions. Covers the Kotlin Multiplatform flavor, the Swift flavor and twins."
license: MIT
metadata:
  repository: https://github.com/modaal-agent/duet
---

# Duet: iOS and Android apps as verifiable twins

A Duet app keeps each feature's logic in a pure reducer, renders it with the platform's own UI, and
records the feature's behavior as fixtures: a scenario goes in, a canonical state and effect trace
comes out. CI replays every fixture on every platform and fails on any byte that differs.

**If the environment gives you its own Duet instructions or tools** (a `parity/authoring.md` in the
tree, a host application's tools for running or scaffolding Duet apps), follow those; use this
skill for what they do not cover.

## Identify the tree first

| What the tree holds | Shape | Where feature logic goes |
| --- | --- | --- |
| `src-kmp/`, and manifest rows with `kotlin:` only | Kotlin Multiplatform flavor: one Kotlin core both apps consume | `src-kmp/subtrees/<feature>/logic/src/commonMain/` |
| manifest rows with `swift:` only, packages depending on `Duet` | Swift flavor: a pure Swift core, Apple platforms only | `src-ios/Subtrees/<Name>/<Name>Feature/Sources/` |
| rows with both `swift:` and `kotlin:`, `kotlinCore: jvm`, `src-android/` | twins: a Swift core for iPhone, a Kotlin core for Android | both; the row's `scenario:` names the side that records |
| a checkout of `github.com/modaal-agent/duet` itself | the framework | read its `CONTRIBUTING.md`; this skill is for apps |
| no Duet yet | — | open `tutorial1-start` (Kotlin) or `tutorial1-swift-start` (Swift) from [duet-tutorials](https://github.com/modaal-agent/duet-tutorials), or follow the series by hand ([worked-examples.md](references/worked-examples.md)). Modaal (modaal.dev), the authoring service around the framework, scaffolds Duet projects |
| a CombineRIBs app | migration | [duet-migration](https://github.com/modaal-agent/duet-migration) carries the coexistence shim and its port-or-delete recipe |

Then run `tools/duet lanes` for the tree's lanes and what `verify` does not cover, and
`tools/duet lint` for the manifest's state. [model.md](references/model.md) states the three shapes
in full.

## Rules every tree holds you to

- The reducer is pure and takes no Environment: side effects leave it as `Effect` values, and the
  Runtime performs them.
- Fixtures are build products of `tools/duet record`. Never edit one by hand. A behavior change
  re-records in the same change, and the fixture diff is the review artifact.
- Every generated file is regenerated, never hand-edited: fixtures, mocks (`tools/duet mocks`),
  design tokens (`tools/duet design-tokens`), sum coders (`tools/duet canonical-sum`).
- Tests use virtual time and turn control (`TestClock`, the deterministic-async helpers), never the
  wall clock. A test that flakes under virtual time is a bug in the code or the test.
- Navigation is state: routes, sheets and back are actions and state, and shells render them.
- Lifecycle-bound work (subscriptions, sessions, platform services) lives in a worker adopted at the
  composition root. A worker is never `@unchecked Sendable`; `tools/duet doctor` reports it.
- Test doubles live in test targets or a test-support product, never in a product's sources.
- Swift shells are `@MainActor` and build under strict concurrency.
- Family versions are pinned exactly, and duet and duet-services move in the same change.

## The feature loop

1. Add the feature's row to `parity/manifest.yaml` and its spec to `parity/feature-specs/<f>.md`;
   the spec names every fixture in backticks.
2. Write State, Action, EffectPayload and the reducer where the table above says.
3. Write the scenario: actions in, the expected state and effects out, one branch per path.
4. Record: `tools/duet record --feature <f>` (`--chain <c>` for a chain). The side the manifest's
   `scenario:` names writes the fixtures.
5. Read the fixture diff before anything else; it is the behavior you are committing.
6. Mount the feature in each shell: the store in a `StoreHost`, the view rendering its state
   ([composition-and-shells.md](references/composition-and-shells.md)).
7. `tools/duet verify`: the meta-checks, then every lane, then the coverage gate.
8. `tools/duet record --feature <f> --check`: regenerates in memory and fails if a byte changed.

[scenarios-and-fixtures.md](references/scenarios-and-fixtures.md) has the scenario DSL on both
flavors, chains, the manifest grammar and the replay runner.

## Running the CLI

Run `tools/duet <verb>` when the tree has the wrapper: it resolves the CLI at the tree's pin,
`parity/duet-tools.ref`. Without one, run this skill's script, which follows the same pin:

```bash
"${CLAUDE_SKILL_DIR}/scripts/duet-cli.sh" verify
```

`scripts/` is beside this file. The CLI is a macOS Apple-silicon binary; inside an agent sandbox
its first download needs network access to `github.com` and `release-assets.githubusercontent.com`.
`tools/duet help` lists the verbs the tree's pin has. The ones a feature loop uses:

| Verb | What it does |
| --- | --- |
| `verify [--feature <f>]` | meta-checks, then every platform lane, then the coverage gate |
| `lint` | the manifest meta-checks alone, in seconds |
| `record --feature <f>` / `--chain <c>` | regenerate fixtures from the scenario; `--check` fails on a changed byte |
| `lanes` | the lane inventory, and what `verify` does not cover |
| `explain` | re-print the last run's failures from `parity/.runs` |
| `materialize <fixture>#<step> --platform <p>` | write one failing step as a standalone test |
| `scope <path>` | which gates govern a file |
| `doctor` | the declaration cross-check and the worker-isolation lint |
| `mocks [--check]`, `design-tokens [--check]` | the code generators the manifest and the token file drive |
| `protocol-run [--platform swift\|kotlin\|both]` | the corpus through a replay runner; `verify` does not run it |
| `mcp` | the verification verbs as a stdio MCP server |

Each verb above except `mcp` takes `--json`. [cli.md](references/cli.md) has every verb, the MCP entry and the CI
template.

## Pins

```bash
"${CLAUDE_SKILL_DIR}/scripts/family-pins.sh" check            # the tree's pins, exit 1 on a disagreement
"${CLAUDE_SKILL_DIR}/scripts/family-pins.sh" check --latest   # plus the duet version duet-services pins
"${CLAUDE_SKILL_DIR}/scripts/family-pins.sh" latest           # the newest tag of each family repository
```

- duet-services pins duet `exact:`, so SwiftPM fails to resolve a tree that moves one and not the
  other. Move the Swift `exact:` pins and the Gradle catalog's `duet` and `duetServices` together.
- Pre-1.0 minors are breaking. Move `parity/duet-tools.ref` deliberately, and read the "Adopting"
  section of each duet-tools CHANGELOG entry you cross. Moving the CLI pin can also move the
  floor of the manifest's `mocks.bundle`; `tools/duet lint` names it.

## Services

| Product | What it gives an app |
| --- | --- |
| `DuetDiagnostics` | a diagnostics port and an `os.Logger` worker |
| `DuetAppServices` | inbound (URLs, push, lifecycle) and outbound (URL open, pasteboard, haptics, prompts) workers behind narrow ports |
| `DuetTelemetry`, `dev.modaal.duet.services:telemetry` | the tracked-event grammar and a worker that fans events out to sinks |
| `DuetTheming`, `dev.modaal.duet.services:theming` | themes, appearance and the provider the views read |

Adopt them at the composition root; [services.md](references/services.md) has the adoption steps,
design tokens, localization and analytics.

## The Kotlin core on the iPhone

In the Kotlin Multiplatform flavor the iPhone app links the core as one XCFramework. Check these
five first when the iPhone side fails:

- Swift cannot name a type from a module the umbrella does not `export`.
- A Kotlin exception crossing a boundary function without `@Throws` terminates the app.
- A Kotlin store the Swift shell holds keeps running until the shell calls its bridge's
  `cancel()` (`BridgedStore` in the tutorials' bridge library).
- A bare `swift test` links the last assembled framework; assemble first (`scripts/assemble_kit.sh`).
- Builds and tests run `ARCHS=arm64`.

[kotlin-on-apple.md](references/kotlin-on-apple.md) has each, and the boundary file.

## Test doubles

Generated doubles follow the family's mock dialect (`<fn>CallCount`, `<fn>Args`, `<fn>Handler`, …).
Kotlin interfaces get them from the `kotlin-ksp-mocks` skill's processor, Swift protocols from
`tools/duet mocks`, which runs the Sourcery templates the manifest's `mocks:` section names. Install
those skills for their detail: `npx skills add modaal-agent/kotlin-ksp-mocks` and
`npx skills add modaal-agent/swift-sourcery-templates`.

## When it goes wrong

| Output | Action |
| --- | --- |
| `fixture listed but missing on disk: … run: tools/duet record --feature <f>` | record the feature; a fixture comes from its scenario |
| `fixture on disk but not in manifest: <name>` | add it to the row's `fixtures:` or delete the stray file |
| `duet verify: FAIL (meta-checks) — not running platform lanes` | run `tools/duet lint` and fix its finding first |
| `✗ fixture '<name>' step <n> '<label>' — <kind> diverged` | the reducer and the fixture disagree on that step's state or effects; `tools/duet materialize <name>#<n> --platform <platform>` reproduces the step as a test (the `next:` line names the same step) |
| `duet record --check: FAIL — behavioral drift in <n> fixture(s):` | re-record with `tools/duet record --feature <f>`, read the diff, commit it |
| `[mocks] bundle: <v> is below the <v> floor` | raise the manifest's `mocks.bundle` in the change that moves the CLI pin |
| `[declarations] <file>: …` | `.modaal/project.json` disagrees with the disk; [troubleshooting.md](references/troubleshooting.md) has each row |
| `[workers] … '@unchecked Sendable'` | isolate the worker (`@MainActor`) or prove it `Sendable` |
| `duet: not inside a parity repo` | run from inside the tree; its root holds `parity/fixtures` |
| the iOS app terminates on a Kotlin call | add `@Throws` to the boundary function and call it with `try` |
| SwiftPM cannot resolve two duet versions | move duet and duet-services together; `family-pins.sh check --latest` |

[troubleshooting.md](references/troubleshooting.md) has every diagnostic with its cause.

## References

- [model.md](references/model.md) — State, Action, Effect, the reducer, `Store`, `TestStore`,
  canonical JSON, the fixture dialects, the three shapes.
- [scenarios-and-fixtures.md](references/scenarios-and-fixtures.md) — the scenario and chain DSLs,
  the manifest grammar, record and verify, the replay runner, mutations.
- [composition-and-shells.md](references/composition-and-shells.md) — Dependency, Component and
  Builder, the shell types, workers, navigation as state.
- [kotlin-on-apple.md](references/kotlin-on-apple.md) — the XCFramework, SKIE, `@Throws`,
  `BridgedStore`, assembling before Swift builds.
- [cli.md](references/cli.md) — installing and pinning the CLI, every verb, `duet mcp`, CI.
- [services.md](references/services.md) — duet-services, design tokens, localization, analytics.
- [troubleshooting.md](references/troubleshooting.md) — each diagnostic, its cause, its action.
- [worked-examples.md](references/worked-examples.md) — where the tutorials show each idiom, and
  how to fetch one tree.
