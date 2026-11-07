---
description: The record drift gate fails on a pull request that changed a reducer.
tags: [diagnosis, fixtures]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 8
expected_outcome: |
  The reducer change moved recorded behavior: re-record with tools/duet record --feature settings
  (or record --check --write), review git diff -- parity/fixtures, and commit the fixtures with the
  reducer change. Never edit a fixture by hand; if the change was not intended, fix the reducer.
---

CI fails on my pull request with this:

```
duet record --check: FAIL — behavioral drift in 2 fixture(s):
  parity/fixtures/settings.toggle-on.fixture.json
  parity/fixtures/settings.toggle-off.fixture.json
parity/fixtures is untouched — the would-be rewrite is under parity/.runs/record-check/
```

The pull request changes the settings reducer so that flipping the toggle also emits an effect
that saves the value. `tools/duet verify` passes on my machine. How do I make CI green? The repository's files are not available in this session; answer from what is described here.
