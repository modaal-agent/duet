# CI templates

What a repo in the Duet family — or a repo *adopting* Duet — runs in CI.

## Adopter repos

[`adopter-parity.yml`](adopter-parity.yml) is the template: copy it to
`.github/workflows/parity.yml` in your repo and follow the `ADAPT` markers
inside. The gate is two commands:

```sh
duet verify          # meta-checks + both platform lanes + coverage gate
duet record --check  # drift gate — fixtures are build products
```

The toolchain arrives as the released binary: the repo's `tools/duet` wrapper
resolves `parity/duet-tools.ref` to that tag's release asset
(checksum-verified, cached under `.duet-family/duet-bin/`), building from
source only when no release is reachable.

Everything else in the file is toolchain setup. Budget: the lanes themselves
target < 60 s wall-clock on a warm tree; runner setup is outside the budget.

## Framework repos

The family's own workflows live in each repo's `.github/workflows/ci.yml`:

- **duet** — `swift test` (framework suites replay the repo's own fixture
  corpus), `cd kotlin && ./gradlew test` (KMP suites), and
  `python3 scripts/flavor-lockstep-lint.py` (development rule 1: one contract
  surface across the two core flavors).
- **duet-tools** — `swift test` (the CLI's own suite; the `duet` framework
  dependency is an exact-version URL pin), plus `release.yml`: a tag push
  builds the macOS-arm64 `duet` binary and publishes it — with its checksum
  sidecar — as the tag's release assets, the artifact adopter wrappers
  resolve from their `parity/duet-tools.ref` pin.

The commands they run are also the local gate — see each repo's
CONTRIBUTING.
