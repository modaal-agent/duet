# Scenarios, chains, the manifest and the record loop

A scenario is the authored source of a feature's fixtures: `tools/duet record` runs it with
regeneration on and writes `parity/fixtures/`. Fixtures are build products; never hand-edit one.
The types scenarios drive are in [model.md](model.md), every verb's flags in [cli.md](cli.md).
Snippets are excerpts of [duet-tutorials](https://github.com/modaal-agent/duet-tutorials/blob/main/README.md) trees.

## The loop

1. Add the row to `parity/manifest.yaml` and name each fixture in `parity/feature-specs/<f>.md`.
   `tools/duet lint` then reports `fixture listed but missing on disk: <fixture> — just declared? run: tools/duet record --feature <f>`.
2. Write the scenario, record it, read the diff, then run the gates:

```sh
tools/duet record --feature splash
git diff -- parity/fixtures
tools/duet verify
tools/duet record --feature splash --check
```

- `record` prints `duet record: rewrote N fixture(s):`; `--chain <fixture>` scopes to one chain.
- `verify` runs the meta-checks, every lane, then the coverage gate: each listed fixture must report a
  replay from each lane its feature declares.
- `record --check` fails on a behavioral difference and passes on metadata-only churn (`scenario.source`,
  step `label`, `line`); a failing check leaves `parity/fixtures` untouched.

## The scenario DSL

| Statement | Swift (`DuetTesting`) | Kotlin (`dev.modaal.duet.test`) | In the fixture |
| --- | --- | --- | --- |
| scenario | `Scenario<S, A, P>(feature:, fixture:, description:) { … }` | `scenario<S, A, P>(feature =, fixture =, description =, source =) { … }` | one file per leaf |
| initial state | `Given(state)` | `given(state)` | `initialState` |
| action | `When("label", .action)` | `whenAction("label", Action)` | one step |
| state check | `Then("label") { $0.isArmed }` | `then("label") { it.isArmed }` | nothing; runs locally |
| effects check | `ThenEffects("label") { $0 == [...] }` | `thenEffects("label") { it == effectsOf(...) }` | nothing; runs locally |
| chapter | `Context("label") { … }` | `context("label") { … }` | label prefix `label › step` |
| alternate ending | `Branch("label") { … }` | `branch("label") { … }` | its own file, `<fixture>.<slug>` |

```kotlin
// tutorial1-complete: src-kmp/subtrees/splash/logic/src/jvmTest/kotlin/dev/modaal/foyer/splash/SplashScenarioTest.kt
val s = scenario<SplashState, SplashAction, SplashEffectPayload>(
  feature = "splash", description = "The splash arms a safety net when it appears …",
  source = "src-kmp/subtrees/splash/logic/src/jvmTest/kotlin/dev/modaal/foyer/splash/SplashScenarioTest.kt",
) {
  given(SplashState())
  whenAction("the splash appears", SplashAction.Appeared)
  then("the safety net is armed") { it.isArmed }
  branch("repeat appear inert") {
    whenAction("the splash reports appearing a second time", SplashAction.Appeared)
    thenEffects("nothing: the net is not re-armed") { it.isEmpty() }
  }
}
ScenarioRunner.verifyOrRecord(s, SplashState.serializer(), SplashActionSerializer, SplashEffectPayloadSerializer, ::splashReducer)
```

```swift
// tutorial1-swift-complete: src-ios/Subtrees/Splash/SplashFeature/Tests/SplashFeatureTests/SplashScenarioTests.swift
private let splashScenario = Scenario<SplashState, SplashAction, SplashEffectPayload>(
  feature: "splash", description: "The splash arms a safety net when it appears …") {
  Given(SplashState())
  When("the splash appears", .appeared)
  Branch("ceremony completes") {
    When("the animation reaches its end", .ceremonyFinished)
    ThenEffects("the host is notified, by the ceremony path") { $0 == notified(.ceremony) }
  }
}
// XCTestCase body: try ScenarioRunner.verifyOrRecord(splashScenario, reducer: splashReducer)
```

- One `Given`, first. A `Then` checks the preceding `When` on the authoring platform only, before that
  step's byte gate; a false `Then` during record writes nothing.
- `Context` is linear. After a `Branch`, only `Branch`es follow at that level. A slug is the label
  lowercased with each run of non-alphanumerics as `-`; nested branches append `.<slug>`.
- No data-dependent `if`, `switch` or loop in a body (a Swift compile error; review in Kotlin).
- `fixture` defaults to `feature`. Kotlin needs `source`, the test file's repo-relative path, to record.
- The writer side calls `ScenarioRunner.verifyOrRecord`; a twin that never writes calls
  `ScenarioRunner.verify` with the same arguments. Verify reports a stale fixture as `structure`, and
  a reducer change as `state diverged`, `effects diverged` or `Then failed`.

## Chains

A chain fixture pins a seam: one feature's delegate, received as the next feature's action. A `hop`
decodes the previous step's last payload whose case is `notifyListener`, so each feature names its
delegate payload case `notifyListener` (Kotlin: `@SerialName("notifyListener")` on any class name).

```kotlin
// tutorial3-complete: src-kmp/subtrees/root/logic/src/jvmTest/kotlin/dev/modaal/foyer/root/RootChainsTest.kt
private val root = ChainNode("root", RootState(auth = AuthSnapshot.SignedOut),
  RootState.serializer(), RootActionSerializer, RootEffectPayloadSerializer, ::rootReducer)
private val splash = ChainNode("splash", SplashState(isArmed = true),
  SplashState.serializer(), SplashActionSerializer, SplashEffectPayloadSerializer, ::splashReducer)

@Test fun theSplashSeam() {
  val chain = chainScenario(chain = "root-splash", fixture = "chain-root-splash", description = "…",
    source = "src-kmp/subtrees/root/logic/src/jvmTest/kotlin/dev/modaal/foyer/root/RootChainsTest.kt") {
    whenAction(splash, "the ceremony ends", SplashAction.CeremonyFinished)
    hop("the splash's delegate is the root's action", from = splash, to = root,
      delegateSerializer = SplashDelegateEventSerializer) { event -> RootAction.Splash(event) }
    then(root, "the gate is up") { it.phase == RootPhase.SignIn }
  }
  ChainScenarioRunner.verifyOrRecord(chain)
}
```

- Swift: `ChainNode("splash", initial:, reducer:)`, `ChainScenario(chain:, description:) { … }`,
  `When(node, "label", .action)`, `Hop("label", from:, to:) { (d: SplashDelegateEvent) in .splash(d) }`
  (the parameter type written out), `try ChainScenarioRunner.verifyOrRecord(chain)`.
- One handle per node key, beside the scenario; no `Context` or `Branch`. The fixture defaults to
  `chain-<chain>`; write it as a string literal, because `record --chain` finds tests by the quoted name.
- List it under `chains:` and mention it in the spec of every node in its `initialStates`. Kotlin
  `ChainRunner.run(fixture, nodes)` replays a chain fixture with no scenario.

## Golden tests and record modes

A golden test replays committed fixtures against the pure reducer, one method per fixture:

```kotlin
// src-kmp/subtrees/splash/logic/src/jvmTest/kotlin/dev/modaal/foyer/splash/SplashGoldenTest.kt
@Test fun ceremonyCompletesLeaf() = replay("splash.ceremony-completes")
private fun replay(leaf: String) = FixtureRunner.run(fixture = leaf, stateSerializer = SplashState.serializer(),
  actionSerializer = SplashActionSerializer, payloadSerializer = SplashEffectPayloadSerializer, reducer = ::splashReducer)
```

Swift's is `try FixtureRunner.run(fixture: "splash.ceremony-completes", reducer: splashReducer)`; a Swift
scenario's verify mode replays its fixtures too. Declare `parity/fixtures` an input of each Kotlin `Test`
task (`inputs.dir(...)` in `tutorial1-complete`'s module build file), so a fixture-only change reruns it.

| Writer | Switch | Output |
| --- | --- | --- |
| Swift runners | `REGEN_FIXTURES=1` | fixture files in `parity/fixtures/` |
| Kotlin runners | system property `duet.regenFixtures=1`, or `REGEN_FIXTURES=1` | compact artifacts in `parity/.runs/record/kotlin/` |
| `tools/duet record` | `REGEN_FIXTURES=1` on `swift test`, `-PregenFixtures=1` on `./gradlew` | materializes the Kotlin artifacts into fixture files |

Record through `tools/duet record`; a Kotlin pass alone writes no fixture file. The root build file
carries the Gradle property into the test JVM (`tutorial1-complete/src-kmp/build.gradle.kts`):

```kotlin
subprojects {
  val regenFixtures = providers.gradleProperty("regenFixtures")
  tasks.withType<Test>().configureEach { systemProperty("duet.regenFixtures", regenFixtures.getOrElse("")) }
}
```

With `--feature`, `--platform` must name the language of the row's `scenario:`. Without it, `--feature`
records through Kotlin for a row with no `swift:` path or a `.kt` scenario, through Swift otherwise.

## The manifest

`parity/manifest.yaml` is parsed by the CLI's own line parser, not a YAML engine
([grammar](https://github.com/modaal-agent/duet-tools/blob/main/contracts/manifest.md)): 2-space
indents, and a comment starts at the first `#` anywhere on a line. `tools/duet lint --json` prints the plan.

```yaml
replayRunner: src-ios/Libraries/Replay        # optional: the Swift package holding Sources/replay-runner
kotlinCore: jvm                               # optional: jvm | multiplatform; absent means multiplatform
features:
  splash:                                     # lower-case, one word
    swift: src-ios/Subtrees/Splash/SplashFeature/Sources/SplashFeature/SplashFeature.swift
    kotlin: src-android/subtrees/splash/logic/src/main/kotlin/dev/modaal/foyer/splash/SplashFeature.kt
    state: SplashState
    action: SplashAction
    effectPayload: SplashEffectPayload
    scenario: src-ios/Subtrees/Splash/SplashFeature/Tests/SplashFeatureTests/SplashScenarioTests.swift
    fixtures:
      - splash.ceremony-completes
chains:
  - chain-root-splash
```

| Rule | Detail |
| --- | --- |
| top level | `features`, `chains`, `presentation`, `mocks`, `replayRunner`, `kotlinCore`; any other key is an error. An empty `features:` is valid |
| sides | `swift:`, `kotlin:`, or both (twins); `kotlin: pending` marks a Kotlin port not landed |
| `scenario:` | required and must exist; it names the fixtures' one writer |
| `fixtures:` | each exists as `parity/fixtures/<name>.fixture.json`; every fixture on disk is listed by a feature or a chain |
| Swift naming | module `<X>Feature`, lower(X) = the feature name; subtree path `Subtrees/<Name>/<X>Feature/Sources/<X>Feature/` |
| Kotlin naming | module directory `feature-<name>` or `subtrees/<name>/logic`; a `commonMain` path requires the second |
| both sides | declaration parity by wire name; Swift under `Subtrees/<Name>/` exactly when Kotlin is under `subtrees/<name>/` |
| `kotlinCore: jvm` | plain JVM modules (`src/main`, `src/test`); a multiplatform source set is an error |
| `presentation:` | waivers: `kind`, `feature`, `platform` (`ios`/`android`), `manner`, `reason`, `since`; islands: `id`, `feature`, `boundary`, `reason`, `since` |
| `mocks:` | `bundle:` (the swift-sourcery-templates tag) and `generators:` rows, each with `output`, `template`, `sources` or `package`, optional `args`; one `- item` per line. `tools/duet mocks` writes, `--check` validates |

## Feature specs

When `parity/feature-specs/` exists, `tools/duet verify` checks it before any lane: each feature has
`parity/feature-specs/<name>.md`; each manifest fixture appears in it in backticks
(`` `splash.repeat-appear-inert` ``, or a `` `splash.*` `` glob plus a `` `.slug` `` token per
remaining segment); each backticked `` `chain-…` `` names an existing chain fixture; each chain is
mentioned in the spec of every node in its `initialStates`. A miss fails as
`<f>.md: manifest fixture '<fixture>' never mentioned`.

## Failures

```text
✗ fixture 'splash.both-paths-notify-twice' step 0 'the splash appears' — effects diverged   [kotlin]
  at expectedEffects[0].payload.value.afterMillis
  expected: 2500   actual: 3000
```

`tools/duet explain` re-prints the last run's failures. Reproduce a step as a standalone failing test
with `tools/duet materialize <fixture>#<step> --platform swift|kotlin` (`--clean` deletes them).

## The replay runner and protocol-run

A replay runner serves the reducers over the
[replay protocol](https://github.com/modaal-agent/duet/blob/main/contracts/replay-protocol-v1.md):
JSON lines on stdio, one stateless `reduce` request per step; the CLI compares the canonical strings
it returns with the fixtures. `tools/duet verify` does not run it.

```kotlin
// tutorial1-complete: src-kmp/replay-runner/src/main/kotlin/dev/modaal/foyer/replayrunner/Main.kt
private val registry = ReplayRegistry(listOf<ReplayFeature>(
  ReplayFeature.entry("splash", SplashState.serializer(), SplashActionSerializer, SplashEffectPayloadSerializer, ::splashReducer)))
fun main() { ReplayServer.serve(registry) }
```

```swift
// tutorial1-swift-complete: src-ios/Libraries/Replay/Sources/ReplayAdapter/ReplayAdapter.swift
public let appReplayRegistry = ReplayRegistry([
  ReplayFeature.entry("splash", SplashState.self, SplashAction.self) { state, action in splashReducer(state: &state, action: action) }
])
// Sources/replay-runner/main.swift: ReplayServer.serve(registry: appReplayRegistry)
```

The Kotlin runner is a Gradle `application` module, `:replay-runner`. Give each feature module its own
`base.archivesName` (`"splash-logic"`); two `logic-jvm.jar` files on one classpath fail `installDist`.
`tools/duet protocol-run` builds the `replay-runner` product of the `replayRunner:` package, else the
Kotlin `:replay-runner:installDist`. `--platform both` (twins) drives the Swift runner, then the Kotlin
one, and fails if either fails; `--runner <path>` drives a prebuilt runner. A pass ends `protocol-run: PASS`.

## Mutations

`tools/duet mutate` checks the clean tree is green, then seeds each row of `parity/mutations.json`
alone, runs the suite, requires red, and restores the file's bytes:

```json
{"mutations": [{"name": "splash-arming-guard",
  "file": "src-kmp/subtrees/splash/logic/src/commonMain/kotlin/dev/modaal/foyer/splash/SplashFeature.kt",
  "old": "if (state.isArmed) {", "new": "if (false) {",
  "seeds": "every Appeared arms a new safety net; a splash that reappears fires twice"}]}
```

- `old` must match the file exactly once; a row whose `old` matches zero or several times fails the run.
  `tools/duet mutate <name>` runs one row. Each row is a full suite run: CI runs the drill on a
  schedule ([Tutorial 6](https://docs.modaal.dev/tutorials/duet-06-checks-in-ci)).
- `✗ <name>: SURVIVED — the corpus does not pin this behavior`: write the scenario branch that pins
  it, record it, rerun the row. Before each row the drill prints the `git checkout -- <file>` that
  restores the file if the run is interrupted.
