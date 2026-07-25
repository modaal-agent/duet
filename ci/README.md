# CI templates

What a repo in the Duet family — or a repo *adopting* Duet — runs in CI.

## Adopter repos

[`adopter-parity.yml`](adopter-parity.yml) is the template: copy it to
`.github/workflows/parity.yml` in your repo and follow the `ADAPT` /
`PRIVATE-PHASE` markers inside. The gate is two commands:

```sh
duet verify          # meta-checks + both platform lanes + coverage gate
duet record --check  # drift gate — fixtures are build products
```

Everything else in the file is toolchain setup. Budget: the lanes themselves
target < 60 s wall-clock on a warm tree; runner setup is outside the budget.

## Framework repos

The family's own workflows live in each repo's `.github/workflows/ci.yml`:

- **duet** — `swift test` (framework suites replay the repo's own fixture
  corpus), `cd kotlin && ./gradlew test` (KMP suites), and
  `python3 scripts/flavor-lockstep-lint.py` (development rule 1: one contract
  surface across the two core flavors).
- **duet-tools** — `swift test` with the `duet` repo checked out as a sibling
  (the pre-publication sibling-path dependency; becomes a URL dependency at
  publication).

The repos are private and unpushed while the family incubates, so these
workflows first execute on GitHub at the public flip; until then the identical
commands are the local gate (see each repo's CONTRIBUTING) and were proven from
clean clones by the Modaal-free receipt run (F4, 2026-07-25).
