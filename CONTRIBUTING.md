# Contributing

This guide is for **contributors to the Duet framework itself**. If you're consuming the framework in an app, start from the [README](README.md).

> **Status: pre-release.** The Swift-flavor extraction has landed (`swift/`); the KMP flavor and the `duet` CLI follow per the README roadmap. The rules below are the standing contract every PR is reviewed against.

## The contribution gate: the corpus

Duet's correctness story is a recorded conformance corpus — fixtures that both platform lanes (and both core flavors, where the change touches the shared contract surface) must replay **byte-identically**. That corpus is also the contribution gate:

1. **A PR must keep the corpus byte-green.** `duet verify` passes on every lane the change touches. No exceptions, no "flaky, re-run it".

2. **Legitimate behavior changes re-record in the same PR.** `duet record --check` (regenerate-and-fail-if-changed) is the CI drift gate. If your change legitimately alters recorded behavior, run `duet record` and commit the fixture diff — the diff *is* the review artifact. Hand-editing fixtures is never acceptable.

3. **Contract changes are versioned, not slipped in.** The kernel contract, the canonical fixture dialect/schema, and the replay protocol are versioned with the code and are a public commitment. A breaking change to a frozen contract is a major-version event with a migration note — not a patch.

## Development rules

1. **The lockstep rule.** The two core flavors share one contract surface. A delta landing on one flavor without its twin fails CI (lockstep lint). If you can only author one side, say so in the PR — maintainers will pair the twin — but the PR does not merge half-landed.

2. **Deterministic tests, by construction.** No wall-clock time in framework tests — virtual time and turn-control helpers only. A test that flakes under virtual time is a bug in the code or the test, never a reason to widen a timeout.

3. **Swift targets are strict-concurrency-complete.** Shell glue is `@MainActor`-native. No free-floating tasks in framework code — effects run through the kernel, where they are observable and cancellable.

4. **No upsell stubs.** This repo is self-sufficient (see the README's open-boundary section). A CLI verb either works here or does not exist here; PRs adding stubs that advertise external tooling are rejected. Authoring/scaffolding machinery is out of scope for this repository.

5. **Match the established template.** New shell primitives, CLI verbs, and test-support helpers model after the existing ones. Deviate only when the shape genuinely requires it, and say why in the PR.

6. **Keep CI green.** Breakages on `main` block all PRs until fixed.

## Licensing of contributions

Duet is MIT-licensed. Contributions are accepted under the same terms (inbound = outbound); submitting a PR means you agree your contribution is licensed under the [MIT License](LICENSE). There is no CLA.

## Code style

- Copyright header: `// Copyright (c) 2026 Modaal.dev`
- MIT license reference in the header
- Swift: strict concurrency complete; public surface documented
- Kotlin: `commonMain`-first for core code; platform source sets only for genuinely platform-bound adapters

## Building

The Swift flavor is a standard SPM package:

```sh
cd swift
swift build            # all four targets, Swift 6 language mode (strict concurrency)
swift test             # the framework suites; replays swift/Tests/parity/fixtures
REGEN_FIXTURES=1 swift test   # re-record the suite's own fixtures (then review the diff)
```

The framework's test fixtures live in `swift/Tests/parity/fixtures/` and are governed by
the same corpus rules as a consuming app's: build products of the scenario record modes,
never hand-edited, byte-stable under the pretty writer (`PrettyWriterParityTests` enforces
this). Test-runner machine artifacts land in `swift/Tests/parity/.runs/` (gitignored).

The `duet` CLI, per-flavor dual lanes, and the lint family ship with the toolchain
milestone; this section grows as they land.
