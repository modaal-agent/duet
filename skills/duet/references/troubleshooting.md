# Troubleshooting

One section per diagnostic. The quoted text is what the CLI, the tree's wrapper or a fixture runner
prints: `<f>` is a feature, `<fixture>` a fixture id, `<p>` a platform (`swift` or `kotlin`),
`<path>` a path, `<n>` a number, and `…` elides text that varies. In a failure list each finding
starts with `✗ `. Run each command through `tools/duet`, or through the skill's script in a tree
without the wrapper ([cli.md](cli.md)).

## Running the CLI

### `duet: not inside a parity repo (…)`

Exit 2. The parenthesis names what the CLI looked for, `no parity/fixtures found walking up`. The
working directory is outside the tree, or the tree has no `parity/fixtures/`. `cd` to
the tree; a tree with no fixtures yet keeps `parity/fixtures/.gitkeep`, because git tracks no empty
directory. An MCP server launched outside the tree exits with this line: set its working directory.

### The wrapper's refusals

| the wrapper prints | action |
| --- | --- |
| `tools/duet: no pin at <path> and no DUET_TOOLS_REF set.` | write a release tag into `parity/duet-tools.ref` |
| `tools/duet: no downloadable release for pin <pin> (offline, unauthenticated,` | allow network access to `github.com` and `release-assets.githubusercontent.com`, or set `DUET_BIN`; the wrapper otherwise clones and builds from source, which takes minutes |
| `tools/duet: CHECKSUM MISMATCH for duet-macos-arm64.zip at pin <pin> — refusing to run it.` | re-run to download again; the failed download stays in a temporary directory for inspection |
| `tools/duet: released binary reports '<v>', the pin wants 'duet <pin>' — refusing.` | the asset at that tag reports another version; build the tag from source and set `DUET_BIN` ([cli.md](cli.md)) |
| `duet-cli: the download failed. It needs network access to github.com and release-assets.githubusercontent.com;` | the skill's script could not download; allow both hosts, or run the command it prints once outside the sandbox, which caches the binary |
| `tools/duet version` prints a version other than the pin | `$DUET_BIN`, a `duet` on `PATH` or `$DUET_TOOLS_HOME` answered, and each outranks the pin: unset the variables or take `duet` off `PATH` |

## Manifest meta-checks

### `duet verify: FAIL (meta-checks) — not running platform lanes`

No lane ran. The line above the findings names the check: `lockstep-lint: FAIL`, `host-lane check:
FAIL` or `spec-fixture check: FAIL`. Fix each `✗` finding below it, then re-run `tools/duet verify`.
`tools/duet lint` runs the `lockstep-lint` checks alone, in seconds.

### `✗ [<f>] fixture listed but missing on disk: <fixture> — just declared? run: tools/duet record --feature <f>`

The feature's `fixtures:` list names a file `parity/fixtures/<fixture>.fixture.json` that does not
exist. Run the command the line names. If no file appears, no branch of the feature's scenario
records that id: add the branch, or delete the line from `fixtures:`. A chain prints
`✗ [chains] fixture listed but missing on disk: <chain> — just declared? run: tools/duet record`;
run `tools/duet record --chain <chain>`.

### Other manifest findings

| finding | action |
| --- | --- |
| `✗ fixture on disk but not in manifest: <fixture>` | a scenario branch wrote it: add the id to the owning feature's `fixtures:` and to `parity/feature-specs/<f>.md`; no scenario writes it: delete the file |
| ``✗ <f>.md: manifest fixture '<fixture>' never mentioned (backticked id, or family glob + `.slug` tokens)`` | write the id in backticks in `parity/feature-specs/<f>.md` (checked when that directory exists) |
| `✗ <f>: no one-pager (<f>.md missing in parity/feature-specs)` | add `parity/feature-specs/<f>.md` |
| `✗ [<f>] scenario file missing on disk: <path>`, `✗ [<f>] missing source file: <path>` | correct the moved path in `parity/manifest.yaml`; `tools/duet scope <path>` names a file's row |
| ``duet verify: FAIL — --kotlin-only: … `kotlin:` path — there is no Kotlin lane to run`` | the flag names a lane the run has no path for (`…` is `the manifest declares no`, or with `--feature <f>`, `feature '<f>' declares no`; `--swift-only` prints the Swift form); drop it, or pass the other lane's flag |
| `✗ [<f>] <Kind> lockstep violation: swift-only=[…] kotlin-only=[…]` | a row with both `swift:` and `kotlin:` has a State field or a case on one side only; cases compare by wire name (the Swift case against the Kotlin `@SerialName`, else the class name in camelCase): add the member, or rename the Swift case |

### ``✗ [mocks] bundle: <tag> is below the <floor> floor — `--check` passes each row's template: and args: to the bundle's mock-templates validate, whose flags for them arrive in <floor>``

Measured: a tree whose `lint` passed at its old pin fails `lint` and `verify` once
`parity/duet-tools.ref` moves to a release that sets this floor. In the same commit as the pin,
raise `bundle:` under `mocks:` in `parity/manifest.yaml` to `<floor>` or later, run
`tools/duet mocks` (a fingerprint recording another bundle tag fails `mocks --check`), then
`tools/duet mocks --check`, and commit the regenerated files with both pins.

## Lanes and fixtures

### `✗ fixture '<fixture>' step <n> '<label>' — <kind> diverged`

`<kind>` is `state` or `effects`. `verify` prints the block with the lane after it:

```text
✗ fixture '<fixture>' step <n> '<label>' — state diverged   [<p>]
  at expectedState.<path>
  expected: <the fixture's value>   actual: <the reducer's value>
  action: <the step's action>
  scenario: <scenario file>:<line>
  next: verify materialize <fixture>#<n> --platform <p>
```

The reducer's output at step `<n>` differs from the recording. `effects diverged` (`at
expectedEffects…`) and `Then failed` print the same shape; a chain's starts
`✗ chain '<chain>' step <n> (<node>)`.

1. Run `git diff -- parity/fixtures/<fixture>.fixture.json`. A hand edit shows there: restore the
   file with `git checkout -- parity/fixtures/<fixture>.fixture.json`.
2. Run the step alone. The `next:` line writes the verb as `verify materialize`; the command is
   `tools/duet materialize <fixture>#<n> --platform <p>`. It prints `run it: …`, the command for the
   generated test; `tools/duet materialize --clean` deletes the generated tests afterwards.
   `tools/duet explain` prints the last run's failures again without running the lanes.
3. For an intended behavior change, run `tools/duet record --feature <f>`, review
   `git diff -- parity/fixtures`, and commit the fixtures with the reducer. Otherwise fix the reducer.

### `✗ missing fixture report(s) — lane ran but did not replay these:`

Each line below it is `<fixture> [<p>]`: the lane passed without replaying that fixture. For
`[kotlin]`, add a replay test per leaf to the feature's `<Feature>GoldenTest.kt` (chains: the chain
fixture test), `@Test fun <leaf>Leaf() = replay("<feature>.<leaf>")`. For `[swift]`, check that the
branch exists in the scenario, then run `tools/duet record --feature <f>`.

### `fixture missing or unreadable (<error>) — record it: verify record --feature <f>`

A scenario or replay test found no file to compare with: a branch added to a scenario that does not
write the fixtures, or a fixture never recorded. The writer is the scenario the row's `scenario:`
names; add the branch there and run `tools/duet record --feature <f>`.

### A red lane with no fixture failure

`verify` prints `--- failure lines (<log>) ---` and `--- log tail (<log>) ---`: a compile error, a
crash, or a failing test that is not a replay. The failure lines name the test or the source line.
`UnsupportedClassVersionError` in the Kotlin lane means Gradle runs an older JDK than a module needs.
With `JAVA_HOME` unset the CLI selects the newest installed JDK 21 or later; state the JDK the tree
needs in `gradle/gradle-daemon-jvm.properties` (`toolchainVersion=<major>`), which Gradle reads first.

### `host-lane check: FAIL`

| finding | action |
| --- | --- |
| ``[host-lane] host-lane root `<root>` resolves <packages> — outside the allowlist <allowlist>. …`` | the allowlist is `["duet", "duet-services"]`; move the dependency into a sibling package no lane roots; a `condition:` on it gates linking only |
| ``[host-lane] gated Kotlin module `<m>` applies `<plugin>` — outside the plugin allowlist …`` | move code that needs the plugin (AGP included) into an app-side module |
| ``[host-lane] gated Kotlin module `<m>` declares `<dep>` — outside the dependency allowlist …`` | depend on app code through a `project(...)` module, which the check follows |
| ``[host-lane] gated Kotlin module `<m>` wires a symbol processor into `<configuration>` …`` | wire processors into `kspTest` or `kspJvmTest` only |
| `[host-lane/scope] <path>:<n> declares a reducer outside a gated package …` | move the reducer and its State, Action and EffectPayload into the feature package |
| ``[host-lane] host-lane root `<root>` declares remote dependencies and has no Package.resolved, and `swift package resolve` there failed (…)`` | read the named log; in a sandbox, allow network access to `github.com` |

## Recording

### `duet record: FAIL — fixtures not (fully) regenerated`

The last 30 lines of each failing lane's log print above it. Measured cause: a hand-edited fixture,
whose replay test failed in the same Gradle run. Other causes: a compile error, a scenario assertion
that returned false. Fix what the log names, and restore a hand-edited fixture from git. A failed
record writes back each fixture it deleted before the run; with `--check` it leaves
`parity/fixtures` byte-identical.

### `duet record --check: FAIL — behavioral drift in <n> fixture(s):`

```text
duet record --check: FAIL — behavioral drift in <n> fixture(s):
  parity/fixtures/<fixture>.fixture.json
parity/fixtures is untouched — the would-be rewrite is under parity/.runs/record-check/
materialize it with `duet record` (fixtures are build products — never hand-edit)
```

A reducer or scenario changed and its fixtures were not recorded again. Run
`tools/duet record --feature <f>` (`--chain <c>` for a chain fixture), review
`git diff -- parity/fixtures`, and commit the fixtures with the change that moved them. Never edit a
fixture by hand. `metadata-only churn in <n> fixture(s) (admissible — behavioral fields
unchanged)` exits 0: commit those files with the scenario change. `FAIL — stale generated coder
file(s):` needs `tools/duet record` or `tools/duet canonical-sum`.

### `duet record: REFUSED — …`

| text | action |
| --- | --- |
| `duet record: REFUSED — dual-writer feature(s) in the manifest: <f> — …` | record that tree per feature (`--feature <f>`) and per chain (`--chain <c>`), or point the row's `scenario:` at the Swift twin's scenario |
| `duet record: REFUSED — --platform <p> --feature <f>: the feature's scenario is <language> (<path>), and the scenario is the writer of its fixtures. …` | drop `--platform`, or pass the scenario's language; `tools/duet verify --feature <f> --kotlin-only` (or `--swift-only`) replays the recordings on the other platform |

## Generated code

- `Generated code is stale.` (`mocks --check`): an input changed, a source file was added, or the
  output was edited. Run `tools/duet mocks` and commit the files.
- `stale: <path> — regenerate, or restore the hand-edit into <source>` (`design-tokens --check`):
  move any edit of the generated file into the token source, run `tools/duet design-tokens`, commit.
- `orphaned: <path> — the config no longer declares it; delete the file`: delete it.
- A `design-tokens` refusal names the token's file and path, a rule `R1`–`R8` and a fix
  (`rename it '<key>'`). Apply the fix in the token file; nothing is generated while one stands.

## doctor

### `✗ [declarations] <file>: missing — the repo declares no targets`

`<file>` is `.modaal/project.json`. Exit 1, with `duet doctor: 1 finding(s)`, from a release that
checks declarations in every tree. The newest release reports nothing for a tree without the file
and runs the worker lint alone; its `tools/duet help` says "A repo without .modaal/project.json
declares no targets". Move `parity/duet-tools.ref` to it ([cli.md](cli.md), "The pin"). The other
`[declarations]` findings compare a tree that has the file with what is on disk: each names the
target and the field. [Tutorial 2](https://docs.modaal.dev/tutorials/duet-02-two-apps) shows the
file for a tree that declares its iOS and Android app targets.

### `✗ [workers] <path>:<line>: '<Type>' conforms to Working … and is declared '@unchecked Sendable' — …`

The line ends `isolate the worker (@MainActor, or prove Sendable) instead.` Exit 1. Remove
`@unchecked Sendable`, and make the worker an `actor`, a `@MainActor` class, or a class whose stored
state is `Sendable` so the checked conformance compiles. The compiler reports nothing for this stamp,
so `doctor` is its only check. The rule is in
[docs/workers.md](https://github.com/modaal-agent/duet/blob/main/docs/workers.md).

## protocol-run

| text | action |
| --- | --- |
| `duet protocol-run: --platform takes swift, kotlin or both, got '<v>'` | exit 2; pass one of the three |
| `protocol-run [swift]: FAIL — no manifest package root contains Sources/replay-runner` | add `replayRunner: <package dir>` to the manifest, or pass `--runner <path>` |
| ``protocol-run [kotlin]: FAIL — no `replay-runner` Gradle module at <path>`` | add the module, or pass `--runner <path>` |
| `protocol-run [<p>]: FAIL — replay-runner did not build` or `— :replay-runner:installDist did not build` | the log tail above names the error |
| `protocol-run [<p>]: FAIL — no valid handshake from the replay runner` | the runner's first stdout line must be the `duet-replay` handshake and its diagnostics go to stderr ([the protocol](https://github.com/modaal-agent/duet/blob/main/contracts/replay-protocol-v1.md)); move other output to stderr |
| `✗ [<p>] <f>: not advertised by the <p> runner` | register the feature in that runner |
| `✗ [<p>] <fixture>#<n>: state diverged` or `effects diverged` | run `tools/duet verify --feature <f>` for the rendered divergence |

## mutate

- `✗ <name>: SURVIVED — the corpus does not pin this behavior`: no recording sends the input the
  mutated code handles. Add the scenario branch that sends it, list its fixture in the manifest and
  the feature spec, add its replay test, run `tools/duet record --feature <f>`, and re-run
  `tools/duet mutate <name>` until it prints `✓ <name>: caught by [<lane>]`. When removing the guard
  changes no state and no effect, no recording can catch it: delete the row.
- ``!! <name>: `old` matches <n> time(s) — stale row``: `old` must match its file exactly once.
  Update `old` and `new` to the current source. `!! <name>: <file> not readable — stale row`:
  correct `file`.
- `duet mutate: ABORT — the suite is red before any mutation`: make `tools/duet verify` pass first.
- An interrupted drill leaves the seeded file mutated: run the `git checkout -- <file>` line it
  printed before that row.

## The Swift and Kotlin builds

### A Kotlin exception terminates the iOS app

Kotlin/Native terminates the process when an exception reaches Swift through a function without
`@Throws`. Annotate each exported function that can throw, e.g. `@Throws(IllegalArgumentException::class)`;
Swift then sees a `throws` function and receives a Swift `Error`
([Kotlin/Native GC and Swift ARC](https://docs.modaal.dev/articles/kotlin-native-gc-swift-arc)).

### SwiftPM cannot resolve two versions of `duet`

Resolution fails before anything compiles. `duet-services` pins `duet` with `exact:`, and SwiftPM
solves the app and every package it reaches as one graph. Move the app's `duet` and `duet-services`
pins in one change, to the `duet` tag the chosen duet-services release pins
(`"${CLAUDE_SKILL_DIR}/scripts/family-pins.sh" check --latest` reads it from that release's
`Package.swift`), and keep the Kotlin version catalog's `duet` entry on the same tag. A new `duet` release reaches such a tree once
duet-services publishes a release built against it.

### `swift test` exits 0 and ran no test

`swift test` exits 0 when it discovers zero tests. Gate each lane script of your own on its log as
well as on `swift test`'s exit status:

```sh
swift test > swift-test.log 2>&1
tools/duet assert-replayed swift-test.log --min 1
```

`duet assert-replayed: FAIL — max across runner summaries is 0, min 1.` means the target compiled no
test, or a `--filter` matched nothing. A summary line with zero is normal on a green run.
