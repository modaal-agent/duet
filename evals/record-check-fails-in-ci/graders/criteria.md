---
type: llm
---
The answer must say that the reducer change altered recorded behavior and that the fixtures are
regenerated with the CLI (`tools/duet record --feature settings`, or `record --check --write`),
that the fixture diff is reviewed, and that the regenerated fixtures are committed with the
reducer change.

An answer fails this criterion if it edits fixture JSON by hand, copies files out of
`parity/.runs/` by hand, removes or skips the `record --check` step in CI, or treats the
failure as flaky.
