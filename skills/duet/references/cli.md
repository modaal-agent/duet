# The `duet` CLI

`duet` is one executable with no runtime dependencies, released from
[duet-tools](https://github.com/modaal-agent/duet-tools/blob/main/README.md). Every verb derives
what it does from the tree's `parity/manifest.yaml`, whose grammar is
[contracts/manifest.md](https://github.com/modaal-agent/duet-tools/blob/main/contracts/manifest.md).
It finds the tree's root by walking up from the working directory to the first directory holding
`parity/fixtures`; `design-tokens` also accepts `parity/design-tokens.yaml`. `version`, `help` and
`assert-replayed` run anywhere. Every verb except `mcp`, `version` and `help` takes `--json`, and
every JSON report carries a `toolchain` field naming the version that wrote it.

This page describes the newest release. A tree runs the release its pin names, and
`tools/duet help` prints the verbs and flags that release has.

Exit status: 0 passes, 1 is a finding or a failed lane, 2 is a usage error or a run outside a tree.

## Running it

### In a tree that has `tools/duet`

Run every verb through the wrapper, from anywhere inside the tree:

```sh
tools/duet verify
tools/duet version
```

The wrapper reads the pin, a release tag, from the first line of `parity/duet-tools.ref` that is
neither blank nor a comment, and resolves the CLI in this order:

1. `$DUET_BIN`, an explicit binary.
2. `duet` on `PATH`.
3. `$DUET_TOOLS_HOME`, a source checkout, run with `swift run`.
4. The release asset at the pin, downloaded once into `.duet-family/duet-bin/<pin>/duet` and checked
   with `shasum -a 256 -c`. Tag pins on macOS arm64 only.
5. The managed source checkout under `.duet-family/`, moved onto the pin.
6. A fresh clone into `.duet-family/`, built from source (several minutes).

Rungs 1–3 are not checked against the pin. When `tools/duet version` prints a version other than
the pin, one of them is answering: unset `DUET_BIN` and `DUET_TOOLS_HOME`, or take `duet` off
`PATH`. One-off overrides: `DUET_TOOLS_REF=<tag>` replaces the pin for one run,
`DUET_NO_DOWNLOAD=1` skips rung 4, `DUET_NO_CLONE=1` disables rung 6. In a tree without the
wrapper, run the CLI through the skill's script.

### Through the skill's script

The skill's script takes the same verbs and flags as `tools/duet`, in any tree:

```sh
"${CLAUDE_SKILL_DIR}/scripts/duet-cli.sh" verify
"${CLAUDE_SKILL_DIR}/scripts/duet-cli.sh" --print-path
```

Claude Code replaces `${CLAUDE_SKILL_DIR}` with the directory holding `SKILL.md`; in another agent,
write that directory's path in its place. The script runs the first of:

1. the tree's `tools/duet`, when the tree has one;
2. `$DUET_BIN`;
3. `duet` on `PATH`, when its `duet version` prints the pin;
4. a binary cached for the pin: the tree's `.duet-family/duet-bin/<pin>/duet`, or `<pin>/duet` under
   `$DUET_CACHE`, `$HOME/.cache/duet` or `$TMPDIR/duet-cli`;
5. the release asset `duet-macos-arm64.zip` for the pin, checked against its `.sha256` and cached in
   `$DUET_CACHE`, else `$HOME/.cache/duet` when writable, else `$TMPDIR/duet-cli` (macOS arm64 only);
6. `duet` on `PATH` at another version, with a warning naming both versions.

The pin is `--ref <tag>`, else the tree's `parity/duet-tools.ref`, else the newest duet-tools tag.
`--print-path` prints the binary rungs 2–6 resolve and does not run it. `DUET_CLI_RELEASE_BASE` points
the download at a mirror holding `<pin>/duet-macos-arm64.zip` and its `.sha256`. When no rung
resolves, the script prints the source build and exits 2:

```sh
git clone --branch <tag> --depth 1 https://github.com/modaal-agent/duet-tools
cd duet-tools && swift build -c release
```

The built binary is `.build/release/duet`; point `DUET_BIN` at it.

### Installing by hand

```sh
curl -fsSLO https://github.com/modaal-agent/duet-tools/releases/download/<tag>/duet-macos-arm64.zip
curl -fsSLO https://github.com/modaal-agent/duet-tools/releases/download/<tag>/duet-macos-arm64.zip.sha256
shasum -a 256 -c duet-macos-arm64.zip.sha256
unzip duet-macos-arm64.zip
```

The archive holds one `duet` executable; `./duet version` prints `duet <tag>`. The release ships no
Linux binary. On Linux, `tools/duet` falls through to rungs 5 and 6, which need a Swift toolchain.

### Inside an agent sandbox

- The binary download needs network access to `github.com` and `release-assets.githubusercontent.com`.
  Without it the wrapper prints `no downloadable release for pin` and falls back to cloning, which
  needs `github.com` too.
- On a cold cache the lanes need the network as well: SwiftPM resolves the Duet packages from
  GitHub, Gradle resolves `dev.modaal.duet:*` from `https://modaal-agent.github.io/maven`, and
  `mocks` downloads the swift-sourcery-templates release bundle.
- Lane logs are `duet-<lane>-<pid>.log` under `$TMPDIR`, and a failing run prints the log's path.
  SwiftPM and Gradle, which the lanes run, write their caches under the user's home directory
  (Gradle under `~/.gradle` unless `GRADLE_USER_HOME` is set).

## The pin

`parity/duet-tools.ref` holds one tag. Pre-1.0 minors are breaking: a release can add a check, a
refusal or a generated-file change. Move the pin deliberately, in a commit that carries the pin and
the changes it requires and nothing else:

1. Read each `### Adopting` section of the
   [CHANGELOG](https://github.com/modaal-agent/duet-tools/blob/main/CHANGELOG.md) for every release
   between the old tag and the new one. Each states whether the tree must change, which refusals
   are new, and which commands regenerate committed output.
2. Make those changes in the same commit as the pin. Example: a release that sets a floor for
   `mocks: bundle:` needs that key raised in `parity/manifest.yaml` with the pin
   ([troubleshooting.md](troubleshooting.md)).
3. Run `tools/duet version`, then the commands listed under "In CI" below, before committing.

## The verbs

| verb | what it does | key flags |
| --- | --- | --- |
| `verify` | meta-checks, then every lane the manifest derives, in parallel, then the coverage gate | `--feature <f>`; `--swift-only` or `--kotlin-only` |
| `lint` | the manifest meta-checks alone, no lanes, in seconds; `--json` prints the plan (`features`, `chains`, `mocks`) | `--json` |
| `record` | regenerates fixtures from their scenarios (sum coders first) and lists the rewritten files | `--feature <f>` or `--chain <c>`; `--platform swift\|kotlin`; `--check`; `--check --write` |
| `lanes` | the lane inventory: tasks, package roots, chains and their participants, and what `verify` does not cover | `--json` |
| `assert-replayed <log\|->` | exits 1 unless a log shows at least `--min` executed tests (the maximum across XCTest, swift-testing and Gradle summaries) | `--min <n>`, default 1 |
| `explain` | prints the last run's failures again from `parity/.runs`, with no re-run | — |
| `materialize <fixture>#<step>` | writes a standalone failing unit test for one step and prints the command that runs it | `--platform swift\|kotlin`, required; `--clean` deletes every `Materialized_*` test |
| `mocks` | regenerates each `mocks:` row's committed file from the pinned swift-sourcery-templates bundle | `--check` validates each file's fingerprint block; `TEMPLATES_DIR`, `SOURCERY`, `MOCK_TEMPLATES` |
| `protocol-run` | builds the tree's replay runner and byte-compares every feature and chain through the replay protocol | `--platform swift\|kotlin\|both`; `--runner <path>`, not with `both` |
| `write-fixtures` | writes pending artifacts under `parity/.runs/record/` as fixture files; `record` runs it | — |
| `canonical-sum` | regenerates the committed sum coders of every `CanonicalSumCodable` enum; `record` runs it | `--check` |
| `design-tokens` | generates the Swift, Kotlin and web token sources from `parity/design-tokens.yaml` | `--check`; `migrate` rewrites a version-1 config as version 2 |
| `scope <path>` | names the gates that govern a file and the commands that change it | — |
| `doctor` | checks `.modaal/project.json` against the tree, and lints `Working` conformers stamped `@unchecked Sendable`; read-only | — |
| `mutate [<name>]` | seeds each row of `parity/mutations.json`, runs the suite, requires red; minutes per run | `<name>` runs one row |
| `mcp` | serves nine verbs as a stdio MCP server | — |
| `version` | prints `duet <tag>` | — |
| `help` | prints the usage text of the release that runs | — |

Flag rules that refuse a run:

- `record` takes `--feature` or `--chain`, not both. With `--feature`, `--platform` must be the
  language of that feature's `scenario:` file (`.kt` Kotlin, `.swift` Swift); leave it out and the
  CLI records through that language.
- An unscoped `record` refuses while a feature declares both a `swift:` path and a Kotlin
  `scenario:`. Record such a tree per feature and per chain, or point that row's `scenario:` at the
  Swift twin's scenario.
- `--swift-only` or `--kotlin-only` naming a lane the run has no path for is a meta-error.

`record --check` exits 1 on behavioral drift (the replay protocol's fields) and 0 on metadata-only
changes (`scenario.source`, a step's label or line). A failing `--check` leaves `parity/fixtures`
byte-identical and writes the would-be rewrite to `parity/.runs/record-check/`.

## What `verify` covers

`verify` runs, in order, and stops at the first red meta-check:

1. the manifest checks `lint` runs;
2. the host-lane rule: each Swift lane root resolves `duet` and `duet-services` only, each gated
   Kotlin module applies the allowlisted plugins and dependencies only, and reducers and the
   manifest's State, Action and EffectPayload types are declared inside gated packages only;
3. the spec-to-fixture cross-reference, when `parity/feature-specs/` exists;
4. the lanes: one `swift test` per Swift package root, and the Kotlin lane's qualified module tasks
   (`:<module>:test` for a `src/main` module, `:<module>:jvmTest` for a `commonMain` one);
5. the coverage gate: every fixture the manifest lists is reported by each lane its feature declares.

`verify` does not run the Gradle modules and Swift packages the manifest does not name (the apps,
backends, the replay runner), and does not run the protocol lane. An unscoped run prints them as
`not covered by verify — run these in your workflow: …`. A `--feature` run prints
``coverage: scoped run — the landing gate is unscoped `duet verify` ``. List them as data:

```sh
tools/duet lanes --json | python3 -c 'import json, sys; u = json.load(sys.stdin)["uncovered"]; print(*u["gradleModules"], *u["swiftPackages"], sep="\n")'
tools/duet lanes --json | python3 -c 'import json, sys; print(*json.load(sys.stdin)["laneFamilyTasks"], sep="\n")'
```

`laneFamilyTasks` names the unqualified task (`jvmTest`, `test`) that reaches every declared module
from one `./gradlew` line. An unqualified `test` also reaches an Android application module, whose
unit tests need an Android SDK; name tasks with their module path (`:app:testDebugUnitTest`) in
steps of your own.

## The MCP server

`duet mcp` serves nine tools over stdio. Launch it with its working directory inside the tree; the
root is discovered at launch, and outside a tree it exits 2. One `mcpServers` entry:

```json
{ "mcpServers": { "duet": { "command": "duet", "args": ["mcp"] } } }
```

In a tree with the wrapper, set `"command"` to the path of the tree's `tools/duet`, so the server
runs at the pin.

| tool | runs | arguments |
| --- | --- | --- |
| `duet_verify` | `verify --json` | `feature`; `lane`: `swift` or `kotlin` |
| `duet_lint` | `lint --json` | — |
| `duet_record` | `record --json` | `feature`, `chain`, `platform`, `check` (boolean) |
| `duet_lanes` | `lanes --json` | — |
| `duet_explain` | `explain --json` | — |
| `duet_materialize` | `materialize <target> --platform <p> --json` | `target` (`<fixture>#<step>`), `platform`; both required |
| `duet_protocol_run` | `protocol-run --json` | `platform`: `swift`, `kotlin` or `both`; `runner` |
| `duet_scope` | `scope <path> --json` | `path`, required |
| `duet_doctor` | `doctor --json` | — |

Each result is the verb's JSON report, in `structuredContent` and as text, with `isError` set when
the verb exits non-zero. Calls are synchronous, with no progress or cancel. `mutate`, `mocks`,
`design-tokens`, `canonical-sum`, `write-fixtures`, `assert-replayed` and `record --write` run from
a shell only. The
server's `tools/list` is the list of served tools; some releases' `duet help` text names seven.

## In CI

The adopter template is
[ci/adopter-parity.yml](https://github.com/modaal-agent/duet/blob/main/ci/adopter-parity.yml): copy it
to `.github/workflows/parity.yml` and edit the lines marked `ADAPT`. Its gate is two steps on a
`macos-26` runner, `tools/duet verify` and `tools/duet record --check`.
[Tutorial 6](https://docs.modaal.dev/tutorials/duet-06-checks-in-ci) runs the full list in this order;
the last line applies to a tree with `parity/design-tokens.yaml`:

```sh
tools/duet version && tools/duet lint && tools/duet doctor && tools/duet verify
for f in $(tools/duet lint --json | python3 -c 'import json, sys; print(*json.load(sys.stdin)["features"])'); do tools/duet record --feature "$f" --check; done
for c in $(tools/duet lint --json | python3 -c 'import json, sys; print(*json.load(sys.stdin).get("chains", []))'); do tools/duet record --chain "$c" --check; done
tools/duet mocks --check
tools/duet protocol-run
tools/duet design-tokens --check
```

Then add one step per entry of `not covered by verify`: each app's own tests and builds
(`./gradlew :app:testDebugUnitTest :app:assembleDebug`, `xcodebuild build`) and any boundary script
under `parity/scripts/`. Check each lane script of your own with `tools/duet assert-replayed` on its
log. The per-feature and per-chain `record --check` lines check the same fixtures as an unscoped
`record --check`, and they also run on a tree with a feature that declares a `swift:` path and a
Kotlin `scenario:`, where an unscoped record refuses. `tools/duet mutate` takes a full suite run per row;
Tutorial 6 runs it on a nightly schedule and writes its `|` table to `$GITHUB_STEP_SUMMARY`.

The release binary runs on macOS on Apple silicon only; on another runner `tools/duet` builds the CLI
from source at the pin, which needs a Swift toolchain and takes minutes. A job that runs Gradle
only, such as the Android app's unit tests, runs on Ubuntu, whose hosted image carries the Android
SDK; the hosted macOS image carries none.
