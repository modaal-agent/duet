---
description: duet verify runs no lane because a meta-check failed.
tags: [diagnosis, manifest]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 8
expected_outcome: |
  A meta-check failed, so verify ran no platform lane. The finding is a fixture file no feature
  lists: add settings.toggle-off to the settings row's fixtures (and name it in the feature spec) if
  the scenario writes it, or delete the file if none does; run tools/duet lint until it passes, then
  tools/duet verify.
---

`tools/duet verify` prints this and exits 1, and none of my tests ran:

```
lockstep-lint: FAIL
  ✗ fixture on disk but not in manifest: settings.toggle-off
duet verify: FAIL (meta-checks) — not running platform lanes
```

Why did no test run, and what do I change? The repository's files are not available in this session; answer from what is described here.
