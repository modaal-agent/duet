---
type: llm
---
The answer must say that a manifest meta-check failed and that `verify` runs no platform lane
until the meta-checks pass; that the finding is a fixture file in `parity/fixtures/` that no
feature's `fixtures:` list names; and that the fix is to add `settings.toggle-off` to the
settings row's `fixtures:` when the scenario writes it, or to delete the file when no scenario
does. It must rerun `tools/duet lint` or `tools/duet verify` afterwards.

An answer fails this criterion if it blames the test framework, edits the fixture file's
content, or suggests skipping the meta-checks.
