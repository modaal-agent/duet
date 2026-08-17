# Contributing

This guide is for **contributors to the Duet framework itself**. If you're consuming the framework in an app, start from the [README](README.md).

> **Status: pre-release.** The Swift flavor (`swift/`), the KMP flavor (`kotlin/`), and the toolchain have landed — the `duet` CLI lives in [`duet-tools`](https://github.com/modaal-agent/duet-tools) and the `@CanonicalSum` opt-in in [`duet-macros`](https://github.com/modaal-agent/duet-macros) (one URL-consumable package per repo; the README's repository-family table is the map — these rules govern PRs to every repo in the family). The rules below are the standing contract every PR is reviewed against.

## The contribution gate: the corpus

Duet's correctness story is a recorded conformance corpus — fixtures that both platform lanes (and both core flavors, where the change touches the shared contract surface) must replay **byte-identically**. That corpus is also the contribution gate:

1. **A PR must keep the corpus byte-green.** `duet verify` passes on every lane the change touches. No exceptions, no "flaky, re-run it".

2. **Legitimate behavior changes re-record in the same PR.** `duet record --check` (regenerate-and-fail-if-changed) is the CI drift gate. If your change legitimately alters recorded behavior, run `duet record` and commit the fixture diff — the diff *is* the review artifact. Hand-editing fixtures is never acceptable.

3. **Contract changes are versioned, not slipped in.** The kernel contract, the canonical fixture dialect/schema, and the replay protocol are versioned with the code and are a public commitment. A breaking change to a frozen contract is a major-version event with a migration note — not a patch.

## Development rules

1. **The lockstep rule.** The two core flavors share one contract surface. A delta landing on one flavor without its twin fails CI (`python3 scripts/flavor-lockstep-lint.py` — the twin map and per-pair waivers live in `parity/flavor-parity.yaml`, the generated per-release measurement in `parity/flavor-parity-ledger.md`). If you can only author one side, say so in the PR — maintainers will pair the twin — but the PR does not merge half-landed: an unmatched symbol either gets its twin, or a declared delta with a reason (which is a ledger entry, not an escape hatch).

2. **Deterministic tests, by construction.** No wall-clock time in framework tests — virtual time and turn-control helpers only. A test that flakes under virtual time is a bug in the code or the test, never a reason to widen a timeout.

3. **Swift targets are strict-concurrency-complete.** Shell glue is `@MainActor`-native. No free-floating tasks in framework code — effects run through the kernel, where they are observable and cancellable.

4. **No upsell stubs.** This repo is self-sufficient (see the README's open-boundary section). A CLI verb either works here or does not exist here; PRs adding stubs that advertise external tooling are rejected. Authoring/scaffolding machinery is out of scope for this repository.

5. **Match the established template.** New shell primitives, CLI verbs, and test-support helpers model after the existing ones. Deviate only when the shape genuinely requires it, and say why in the PR.

6. **Keep CI green.** Breakages on `main` block all PRs until fixed.

7. **A release cut sets the published version, in the commit that gets tagged.** Both flavors are consumed by version, so a tag that does not change what it publishes is not a release. Swift is safe by construction — SwiftPM resolves the git tag itself — but the KMP flavor publishes Maven coordinates, and its version is a *string in `kotlin/build.gradle.kts`* that has no automatic relationship to the tag. Cutting `X.Y.Z` therefore means: set `version = "X.Y.Z-SNAPSHOT"` (or the release version once the Maven publication is live), commit, **then** tag that commit — not tag first and bump after, which leaves the tag publishing its predecessor's coordinate. `main` then stays on `X.Y.Z-SNAPSHOT` until the next cut moves it; the version names the current line, and only a cut advances it.

   The failure this rule exists to prevent already happened: the `0.1.1` cut left `version = "0.1.0-SNAPSHOT"`, so tags `0.1.0` and `0.1.1` published the same mutable coordinate. Nothing in either flavor's build complained — the tags differ in git, and to Maven they are one artifact that the last `publishToMavenLocal` overwrites. An adopter pinned to `0.1.1` built against the `0.1.0` jar and failed at `Unresolved reference` on symbols `0.1.1` had graduated, with no signal pointing at the version. Pre-publication this is invisible precisely because mavenLocal has no provenance; after publication it becomes an immutable, public wrong artifact.

8. **Docs state the present rule, not the transition.** Pattern pages (`docs/`), contract prose, and README sections are forward-looking: state what the system does and the action the reader takes. Do not frame a rule as a replacement of past practice — "X replaces hand-rolled Y", "previously", "no longer" — the reader has no such past. Historical contrast belongs in the changelog, commit messages, and migration guides, where the change itself is the subject.

## Licensing of contributions

Duet is MIT-licensed. Contributions are accepted under the same terms (inbound = outbound); submitting a PR means you agree your contribution is licensed under the [MIT License](LICENSE). There is no CLA.

## Code style

- Copyright header: `// Copyright (c) 2026 Modaal.dev`
- MIT license reference in the header
- Swift: strict concurrency complete; public surface documented
- Kotlin: `commonMain`-first for core code; platform source sets only for genuinely platform-bound adapters

## Building

The Swift flavor is a standard SPM package — the manifest sits at the repo root
(so `.package(url:)` resolves it), sources under `swift/`:

```sh
swift build            # all four targets, Swift 6 language mode (strict concurrency)
swift test             # the framework suites; replays swift/Tests/parity/fixtures
REGEN_FIXTURES=1 swift test   # re-record the suite's own fixtures (then review the diff)
```

The KMP flavor:

```sh
cd kotlin && ./gradlew test   # the KMP suites (pure KMP — no Android SDK needed)
```

The framework's test fixtures live in `swift/Tests/parity/fixtures/` and are governed by
the same corpus rules as a consuming app's: build products of the scenario record modes,
never hand-edited, byte-stable under the ONE pretty writer
(`PrettyWriterStabilityTests` enforces this; the Kotlin flavor ships no pretty writer —
its record modes emit compact artifacts that the CLI materializes, `duet write-fixtures`).
Test-runner machine artifacts land in `swift/Tests/parity/.runs/` (gitignored).

The flavor-lockstep lint (development rule 1) needs only python3:

```sh
python3 scripts/flavor-lockstep-lint.py                 # coverage + pair surfaces + ledger freshness
python3 scripts/flavor-lockstep-lint.py --write-ledger  # regenerate parity/flavor-parity-ledger.md
```

The `duet` CLI itself is developed in [`duet-tools`](https://github.com/modaal-agent/duet-tools)
(a separate package, which resolves this repo by URL at an exact tag).

CI runs exactly the commands above: this repo's gate is `.github/workflows/ci.yml`
(both flavor suites + the flavor-lockstep lint); the adopter-facing parity template
ships in [`ci/`](ci/README.md).
