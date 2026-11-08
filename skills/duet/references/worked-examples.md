# Worked examples: where the tutorials show each idiom

[duet-tutorials](https://github.com/modaal-agent/duet-tutorials) builds one app, Foyer, in eleven tutorials:
a splash, a sign-in gate, an onboarding gate, a home with a paid feature behind an entitlement, an upgrade
flow and a profile tree. Every tree in the repository is a complete project. Open the file a row names
before writing the same shape in an adopter's tree.

## The three shapes, and where each starts

| shape | first tutorial | opens | ends at |
| --- | --- | --- | --- |
| Kotlin Multiplatform flavor | [Tutorial 1: Your First Feature](https://docs.modaal.dev/tutorials/duet-01-first-feature) | `tutorial1-start` | `tutorial1-complete` |
| Swift flavor | [Swift Tutorial 1: Your First Feature](https://docs.modaal.dev/tutorials/duet-swift-01-first-feature) | `tutorial1-swift-start` | `tutorial1-swift-complete` |
| twins: a Swift core and a Kotlin core | [Twins Tutorial 2: One Behavior, Two Cores](https://docs.modaal.dev/tutorials/duet-twins-02-two-cores) | `tutorial2-twins-start` | `tutorial2-twins-complete` |

To start a new app by hand, copy `tutorial1-start` (Kotlin) or `tutorial1-swift-start` (Swift). Each holds
an empty manifest (`features:`, `chains:`, `presentation:`), `parity/duet-tools.ref` and the `tools/duet`
wrapper; the Kotlin tree adds a Gradle root under `src-kmp/` that declares the family's Maven host. Before
the first feature, move the tree's pins to the newest releases, which the second command prints:

```bash
git ls-remote --tags --refs https://github.com/modaal-agent/duet-tools.git   # the newest duet-tools tag
DUET_TOOLS_REF=<tag> tools/duet pins --latest
```

[model.md](model.md) describes the three shapes and [cli.md](cli.md) the wrapper.

## Concept to file

Pages are on [docs.modaal.dev/tutorials/duet](https://docs.modaal.dev/tutorials/duet); paths are relative to
the tree named. T*n* is Tutorial *n* of the Kotlin series, S1 is Swift Tutorial 1, W2 is Twins Tutorial 2.

| concept | page | tree | files |
| --- | --- | --- | --- |
| feature module and its Gradle wiring | [T1](https://docs.modaal.dev/tutorials/duet-01-first-feature#declare-the-feature-module) | `tutorial1-complete` | `src-kmp/settings.gradle.kts`, `src-kmp/subtrees/splash/logic/build.gradle.kts` |
| first feature: state, actions, effect payloads, reducer | [T1](https://docs.modaal.dev/tutorials/duet-01-first-feature#write-the-state-the-actions-and-the-effect-payloads) | `tutorial1-complete` | `src-kmp/subtrees/splash/logic/src/commonMain/kotlin/dev/modaal/foyer/splash/SplashFeature.kt` |
| sum serializers | [T1](https://docs.modaal.dev/tutorials/duet-01-first-feature#register-the-serializers) | `tutorial1-complete` | `src-kmp/subtrees/splash/logic/src/commonMain/kotlin/dev/modaal/foyer/splash/SplashSerializers.kt` |
| environment and runtime | [T1](https://docs.modaal.dev/tutorials/duet-01-first-feature#add-the-environment-and-the-runtime) | `tutorial1-complete` | `src-kmp/subtrees/splash/logic/src/commonMain/kotlin/dev/modaal/foyer/splash/SplashEnvironment.kt`, `…/SplashRuntime.kt` |
| manifest row and feature spec | [T1](https://docs.modaal.dev/tutorials/duet-01-first-feature#declare-the-feature-in-the-manifest-and-write-its-spec) | `tutorial1-complete` | `parity/manifest.yaml`, `parity/feature-specs/splash.md` |
| scenario, recorded into fixtures | [T1](https://docs.modaal.dev/tutorials/duet-01-first-feature#describe-the-behavior-as-a-scenario-and-record-it) | `tutorial1-complete` | `src-kmp/subtrees/splash/logic/src/jvmTest/kotlin/dev/modaal/foyer/splash/SplashScenarioTest.kt`, `parity/fixtures/` |
| golden test | [T1](https://docs.modaal.dev/tutorials/duet-01-first-feature#replay-the-recordings) | `tutorial1-complete` | `src-kmp/subtrees/splash/logic/src/jvmTest/kotlin/dev/modaal/foyer/splash/SplashGoldenTest.kt` |
| `TestStore` on a test clock, hand-written double | [T1](https://docs.modaal.dev/tutorials/duet-01-first-feature#pin-the-safety-nets-timing-on-a-test-clock) | `tutorial1-complete` | `src-kmp/subtrees/splash/logic/src/jvmTest/kotlin/dev/modaal/foyer/splash/SplashTestStoreTest.kt`, `…/RecordingSplashEnvironment.kt` |
| replay runner (Kotlin) | [T1](https://docs.modaal.dev/tutorials/duet-01-first-feature#add-the-replay-runner) | `tutorial1-complete` | `src-kmp/replay-runner/build.gradle.kts`, `src-kmp/replay-runner/src/main/kotlin/dev/modaal/foyer/replayrunner/Main.kt` |
| XCFramework umbrella and SKIE | [T2](https://docs.modaal.dev/tutorials/duet-02-two-apps#declare-the-apple-framework-module) | `tutorial2-complete` | `src-kmp/apple-umbrella/build.gradle.kts` (`export`, `skie {}`), `src-kmp/build.gradle.kts` |
| the boundary file | [T2](https://docs.modaal.dev/tutorials/duet-02-two-apps#export-the-replay-boundary) | `tutorial2-complete` | `src-kmp/apple-umbrella/src/commonMain/kotlin/dev/modaal/foyer/kit/FoyerBoundary.kt` |
| assembling the framework | [T2](https://docs.modaal.dev/tutorials/duet-02-two-apps#assemble-the-framework-with-one-script) | `tutorial2-complete` | `scripts/assemble_kit.sh` |
| fixtures replayed across the boundary | [T2](https://docs.modaal.dev/tutorials/duet-02-two-apps#replay-the-recordings-across-the-boundary) | `tutorial2-complete` | `src-kmp/apple-umbrella/swift-consumer/Tests/BoundaryTests/SplashBoundaryReplayTests.swift`, `parity/scripts/apple-boundary-lane.sh` |
| `BridgedStore` and the consumer package | [T2](https://docs.modaal.dev/tutorials/duet-02-two-apps#write-the-consumer-package-and-the-store-mirror) | `tutorial2-complete` | `src-ios/Libraries/FoyerKit/Sources/FoyerBridge/BridgedStore.swift`, `src-ios/Libraries/FoyerKit/Package.swift` |
| Swift view shell and its spec | [T2](https://docs.modaal.dev/tutorials/duet-02-two-apps#write-the-swift-shell) | `tutorial2-complete` | `src-ios/Libraries/FoyerKit/Sources/SplashShell/SplashViewShell.swift`, `src-ios/Libraries/FoyerKit/Tests/SplashShellTests/SplashViewShellSpec.swift` |
| iOS app from an XcodeGen spec | [T2](https://docs.modaal.dev/tutorials/duet-02-two-apps#build-the-ios-app) | `tutorial2-complete` | `src-ios/App/xcodegen.yml`, `src-ios/App/Foyer/AppHost.swift` |
| Compose app and its host test | [T2](https://docs.modaal.dev/tutorials/duet-02-two-apps#build-the-compose-app) | `tutorial2-complete` | `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/AppHost.kt`, `src-kmp/app/src/test/kotlin/dev/modaal/foyer/app/AppHostTest.kt` |
| mount-bracket test | [T2](https://docs.modaal.dev/tutorials/duet-02-two-apps#exercise-finish-the-mount-bracket-test) | `tutorial2-complete` | `src-kmp/subtrees/splash/logic/src/jvmTest/kotlin/dev/modaal/foyer/splash/SplashMountBracketTest.kt` |
| ports | [T3](https://docs.modaal.dev/tutorials/duet-03-composing-features#declare-the-four-ports) | `tutorial3-complete` | `src-kmp/ports/src/commonMain/kotlin/dev/modaal/foyer/ports/Ports.kt`, `…/Callbacks.kt` |
| parent level, delegate events as parent actions | [T3](https://docs.modaal.dev/tutorials/duet-03-composing-features#write-the-root-level) | `tutorial3-complete` | `src-kmp/subtrees/root/logic/src/commonMain/kotlin/dev/modaal/foyer/root/RootFeature.kt` |
| KSP mocks | [T3](https://docs.modaal.dev/tutorials/duet-03-composing-features#generate-the-kotlin-test-doubles) | `tutorial3-complete` | `src-kmp/subtrees/home/logic/build.gradle.kts`, `src-kmp/gradle/libs.versions.toml` |
| chain | [T3](https://docs.modaal.dev/tutorials/duet-03-composing-features#pin-the-seams-with-chain-recordings) | `tutorial3-complete` | `src-kmp/subtrees/root/logic/src/jvmTest/kotlin/dev/modaal/foyer/root/RootChainsTest.kt`, `src-kmp/subtrees/profile/logic/src/jvmTest/kotlin/dev/modaal/foyer/profile/ProfileEditNameChainTest.kt` |
| mock services behind the ports | [T3](https://docs.modaal.dev/tutorials/duet-03-composing-features#write-the-mock-services) | `tutorial3-complete` | `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/services/MockAuth.kt`, `src-ios/Libraries/FoyerKit/Sources/FoyerServices/MockAuth.swift` |
| composition level: Dependency, Component, Builder (Android) | [T3](https://docs.modaal.dev/tutorials/duet-03-composing-features#compose-the-tree-on-android) | `tutorial3-complete` | `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/HomeBuilder.kt` |
| `ChildSlot` | [T3](https://docs.modaal.dev/tutorials/duet-03-composing-features#compose-the-tree-on-android) | `tutorial3-complete` | `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/RootBuilder.kt`, `src-ios/Libraries/FoyerKit/Sources/RootShell/RootViewShell.swift` |
| composition level (iOS) | [T3](https://docs.modaal.dev/tutorials/duet-03-composing-features#compose-the-tree-on-ios) | `tutorial3-complete` | `src-ios/Libraries/FoyerKit/Sources/HomeShell/HomeBuilder.swift`, `src-ios/Libraries/FoyerKit/Sources/RootShell/RootComposition.swift`, `src-ios/App/Foyer/SceneComponent.swift` |
| Sourcery Components and mocks via `tools/duet mocks` | [T3](https://docs.modaal.dev/tutorials/duet-03-composing-features#generate-the-swift-components-and-mocks) | `tutorial3-complete` | `parity/manifest.yaml` (`mocks:`), `src-ios/Libraries/FoyerKit/Sources/HomeShell/Generated/HomeShellComponents.swift`, `src-ios/Libraries/FoyerKit/Tests/HomeShellTests/Generated/HomeShellMocks.swift` |
| composition-root tests | [T3](https://docs.modaal.dev/tutorials/duet-03-composing-features#test-the-composition-roots) | `tutorial3-complete` | `src-kmp/app/src/test/kotlin/dev/modaal/foyer/app/RootFlowTest.kt`, `src-ios/Libraries/FoyerKit/Tests/RootShellTests/RootCompositionSpec.swift` |
| streams on the ports | [T4](https://docs.modaal.dev/tutorials/duet-04-workers#add-the-two-streams-to-the-ports) | `tutorial4-complete` | `src-kmp/ports/src/commonMain/kotlin/dev/modaal/foyer/ports/Streams.kt` |
| on-device backend | [T4](https://docs.modaal.dev/tutorials/duet-04-workers#write-the-on-device-backend) | `tutorial4-complete` | `src-kmp/backend-local/src/commonMain/kotlin/dev/modaal/foyer/backend/LocalBackend.kt` |
| workers (Android) | [T4](https://docs.modaal.dev/tutorials/duet-04-workers#write-the-workers-on-android) | `tutorial4-complete` | `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/workers/SessionWorker.kt`, `…/EntitlementWorker.kt` |
| `WorkerTester` | [T4](https://docs.modaal.dev/tutorials/duet-04-workers#test-the-workers-with-the-harness) | `tutorial4-complete` | `src-kmp/app/src/test/kotlin/dev/modaal/foyer/app/workers/SessionWorkerTest.kt`, `src-ios/Libraries/FoyerKit/Tests/RootShellTests/WorkersSpec.swift` |
| workers (iOS), Kotlin flows as async sequences | [T4](https://docs.modaal.dev/tutorials/duet-04-workers#write-the-workers-on-ios) | `tutorial4-complete` | `src-ios/Libraries/FoyerKit/Sources/RootShell/Workers.swift` |
| a slice projected down | [T4](https://docs.modaal.dev/tutorials/duet-04-workers#project-the-entitlement-down-as-a-slice) | `tutorial4-complete` | `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/MainBuilder.kt`, `src-ios/Libraries/FoyerKit/Sources/FoyerBridge/Projected.swift` |
| route state, sheet slot | [T5](https://docs.modaal.dev/tutorials/duet-05-navigation-as-state#draw-the-routes-before-the-screens) | `tutorial5-complete` | `src-kmp/subtrees/main/logic/src/commonMain/kotlin/dev/modaal/foyer/main/MainFeature.kt` (`MainSheet`) |
| lateral state between siblings | [T5](https://docs.modaal.dev/tutorials/duet-05-navigation-as-state#share-readiness-laterally) | `tutorial5-complete` | `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/workers/OnboardingProgressWorker.kt`, `src-ios/Libraries/FoyerKit/Sources/OnboardingShell/OnboardingProgressWorker.swift` |
| a flow with Back as an action | [T5](https://docs.modaal.dev/tutorials/duet-05-navigation-as-state#write-the-upgrade-flow) | `tutorial5-complete` | `src-kmp/subtrees/upgrade/logic/src/commonMain/kotlin/dev/modaal/foyer/upgrade/UpgradeFeature.kt` |
| the sheet mounted per platform | [T5](https://docs.modaal.dev/tutorials/duet-05-navigation-as-state#mount-the-flow-in-each-platforms-idiom) | `tutorial5-complete` | `src-ios/Libraries/FoyerKit/Sources/MainShell/MainView.swift`, `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/MainScreen.kt`, `…/UpgradeSheet.kt` |
| deep link | [T5](https://docs.modaal.dev/tutorials/duet-05-navigation-as-state#grow-the-root-the-second-gate-and-the-deep-link) | `tutorial5-complete` | `src-kmp/ports/src/commonMain/kotlin/dev/modaal/foyer/ports/DeepLink.kt`, `src-ios/App/Foyer/SceneDelegate.swift`, `src-kmp/app/src/main/AndroidManifest.xml` |
| restore after process death | [T5](https://docs.modaal.dev/tutorials/duet-05-navigation-as-state#gather-the-route-spine-and-restore-from-it) | `tutorial5-complete` | `src-kmp/subtrees/root/logic/src/commonMain/kotlin/dev/modaal/foyer/root/RouteSpine.kt`, `src-kmp/subtrees/root/logic/src/jvmTest/kotlin/dev/modaal/foyer/root/RouteSpineTest.kt`, `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/MainActivity.kt` |
| back policy on Android | [T5](https://docs.modaal.dev/tutorials/duet-05-navigation-as-state#make-back-an-action-on-android) | `tutorial5-complete` | `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/BackPolicy.kt`, `src-kmp/app/src/test/kotlin/dev/modaal/foyer/app/BackPolicyTest.kt` |
| lanes the manifest derives | [T6](https://docs.modaal.dev/tutorials/duet-06-checks-in-ci#read-the-lanes-the-manifest-derives) | `tutorial6-complete` | `parity/manifest.yaml` |
| the CI workflow | [T6](https://docs.modaal.dev/tutorials/duet-06-checks-in-ci#put-the-checks-in-a-workflow) | `tutorial6-complete` | `.github/workflows/parity.yml` |
| mutations | [T6](https://docs.modaal.dev/tutorials/duet-06-checks-in-ci#write-the-first-mutation-rows) | `tutorial6-complete` | `parity/mutations.json` |
| design tokens and the generated files | [T7](https://docs.modaal.dev/tutorials/duet-07-theming#declare-the-vocabulary) | `tutorial7-complete` | `parity/design-tokens.yaml`, `src-ios/Libraries/FoyerKit/Sources/Theming/Generated/`, `src-kmp/theming/src/commonMain/kotlin/dev/modaal/foyer/theming/Generated/` |
| theme engines and the main theme | [T7](https://docs.modaal.dev/tutorials/duet-07-theming#link-the-engines-and-declare-the-main-theme) | `tutorial7-complete` | `src-ios/Libraries/FoyerKit/Sources/Theming/Themes.swift`, `…/MainTheme.swift`, `src-kmp/theming/src/commonMain/kotlin/dev/modaal/foyer/theming/Theme.kt` |
| accessors, the theme published once | [T7](https://docs.modaal.dev/tutorials/duet-07-theming#write-the-accessors-and-publish-the-theme-once) | `tutorial7-complete` | `src-ios/Libraries/FoyerKit/Sources/Theming/ThemeAccessors.swift`, `…/FoyerThemeScope.swift`, `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/FoyerTheme.kt` |
| a second theme as a mapping | [T7](https://docs.modaal.dev/tutorials/duet-07-theming#ship-the-second-theme) | `tutorial7-complete` | `src-ios/Libraries/FoyerKit/Sources/Theming/HighContrastTheme.swift` |
| localization: a sealed value in place of a message | [T8](https://docs.modaal.dev/tutorials/duet-08-localization#make-what-the-logic-says-a-value) | `tutorial8-complete` | `src-kmp/subtrees/editname/logic/src/commonMain/kotlin/dev/modaal/foyer/editname/EditNameFeature.kt`, `src-kmp/ports/src/commonMain/kotlin/dev/modaal/foyer/ports/Ports.kt` |
| string catalogs and resources | [T8](https://docs.modaal.dev/tutorials/duet-08-localization#write-the-catalogs-and-link-the-generator) | `tutorial8-complete` | `src-ios/Libraries/FoyerKit/Sources/OnboardingShell/Localizable.xcstrings`, `src-kmp/app/src/main/res/values/strings.xml` |
| a second language held complete | [T8](https://docs.modaal.dev/tutorials/duet-08-localization#add-the-second-language-and-hold-it-complete) | `tutorial8-complete` | `src-ios/Libraries/FoyerKit/Tests/RootShellTests/SecondLanguageSpec.swift`, `src-kmp/app/src/test/kotlin/dev/modaal/foyer/app/TranslationsCompleteTest.kt` |
| no display text in fixtures | [T8](https://docs.modaal.dev/tutorials/duet-08-localization#exercise-pin-the-receipt) | `tutorial8-complete` | `src-kmp/subtrees/root/logic/src/jvmTest/kotlin/dev/modaal/foyer/root/RecordingsHoldNoDisplayTextTest.kt` |
| telemetry grammar module and an app verb | [T9](https://docs.modaal.dev/tutorials/duet-09-analytics#mint-the-apps-verb) | `tutorial9-complete` | `src-kmp/telemetry/build.gradle.kts`, `src-kmp/telemetry/src/commonMain/kotlin/dev/modaal/foyer/telemetry/AppVerbs.kt` |
| `<Feature>Events` and `Track` effects | [T9](https://docs.modaal.dev/tutorials/duet-09-analytics#emit-them-as-track-effects) | `tutorial9-complete` | `src-kmp/subtrees/root/logic/src/commonMain/kotlin/dev/modaal/foyer/root/RootEvents.kt`, `…/RootFeature.kt` |
| `Track` asserted in scenarios and chains | [T9](https://docs.modaal.dev/tutorials/duet-09-analytics#assert-them-in-the-scenarios-and-re-record) | `tutorial9-complete` | `src-kmp/subtrees/upgrade/logic/src/jvmTest/kotlin/dev/modaal/foyer/upgrade/UpgradeScenarioTest.kt`, `src-kmp/subtrees/root/logic/src/jvmTest/kotlin/dev/modaal/foyer/root/RootChainsTest.kt` |
| sink worker behind the fan-out (Android) | [T9](https://docs.modaal.dev/tutorials/duet-09-analytics#wire-the-sink-on-android) | `tutorial9-complete` | `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/workers/ConsoleAnalyticsSink.kt`, `src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/RootBuilder.kt` |
| sink and the bridged-event converter (iOS) | [T9](https://docs.modaal.dev/tutorials/duet-09-analytics#wire-the-sink-on-ios) | `tutorial9-complete` | `src-ios/Libraries/FoyerKit/Sources/FoyerBridge/BridgedAnalyticsWorker.swift`, `src-ios/Libraries/FoyerKit/Sources/RootShell/ConsoleAnalyticsSink.swift` |
| the event taxonomy read back from fixtures | [T9](https://docs.modaal.dev/tutorials/duet-09-analytics#take-the-receipt) | `tutorial9-complete` | `src-kmp/telemetry/src/jvmTest/kotlin/dev/modaal/foyer/telemetry/TrackedEventsInRecordingsTest.kt`, `src-ios/Libraries/FoyerKit/Tests/RootShellTests/TrackedEventEnvelopesSpec.swift` |
| Swift flavor: feature package and manifest row | [S1](https://docs.modaal.dev/tutorials/duet-swift-01-first-feature#declare-the-feature-package-and-its-manifest-row) | `tutorial1-swift-complete` | `src-ios/Subtrees/Splash/SplashFeature/Package.swift`, `parity/manifest.yaml` |
| Swift flavor: first feature and its sum coders | [S1](https://docs.modaal.dev/tutorials/duet-swift-01-first-feature#write-the-state-the-actions-and-the-effect-payloads) | `tutorial1-swift-complete` | `src-ios/Subtrees/Splash/SplashFeature/Sources/SplashFeature/SplashFeature.swift`, `…/SplashSerialization.generated.swift` |
| Swift flavor: scenario | [S1](https://docs.modaal.dev/tutorials/duet-swift-01-first-feature#describe-the-behavior-as-a-scenario-and-record-it) | `tutorial1-swift-complete` | `src-ios/Subtrees/Splash/SplashFeature/Tests/SplashFeatureTests/SplashScenarioTests.swift` |
| Swift flavor: generated environment double | [S1](https://docs.modaal.dev/tutorials/duet-swift-01-first-feature#generate-the-environments-test-double) | `tutorial1-swift-complete` | `src-ios/Subtrees/Splash/SplashFeature/Tests/SplashFeatureTests/Generated/SplashFeatureMocks.swift` |
| Swift flavor: `TestStore` on a test clock | [S1](https://docs.modaal.dev/tutorials/duet-swift-01-first-feature#pin-the-safety-nets-timing-on-a-test-clock) | `tutorial1-swift-complete` | `src-ios/Subtrees/Splash/SplashFeature/Tests/SplashFeatureTests/SplashTestStoreTests.swift` |
| Swift flavor: replay runner | [S1](https://docs.modaal.dev/tutorials/duet-swift-01-first-feature#add-the-replay-runner) | `tutorial1-swift-complete` | `src-ios/Libraries/Replay/Sources/replay-runner/main.swift`, `src-ios/Libraries/Replay/Sources/ReplayAdapter/ReplayAdapter.swift` |
| twins: the Kotlin core on `kotlin.jvm` | [W2](https://docs.modaal.dev/tutorials/duet-twins-02-two-cores#add-the-kotlin-plane) | `tutorial2-twins-complete` | `src-android/settings.gradle.kts`, `src-android/subtrees/splash/logic/build.gradle.kts`, `parity/manifest.yaml` (`kotlinCore: jvm`) |
| twins: Swift fixtures replayed on the Kotlin core | [W2](https://docs.modaal.dev/tutorials/duet-twins-02-two-cores#replay-the-swift-recordings-on-the-kotlin-core) | `tutorial2-twins-complete` | `src-android/subtrees/splash/logic/src/test/kotlin/dev/modaal/foyer/splash/SplashGoldenTest.kt` |
| twins: a Kotlin scenario that checks and writes nothing | [W2](https://docs.modaal.dev/tutorials/duet-twins-02-two-cores#write-the-kotlin-scenario-beside-the-swift-one) | `tutorial2-twins-complete` | `src-android/subtrees/splash/logic/src/test/kotlin/dev/modaal/foyer/splash/SplashScenarioTest.kt` |
| `protocol-run --platform both` | [W2](https://docs.modaal.dev/tutorials/duet-twins-02-two-cores#add-the-kotlin-replay-runner-and-run-both-protocol-lanes) | `tutorial2-twins-complete` | `src-android/replay-runner/src/main/kotlin/dev/modaal/foyer/replayrunner/Main.kt`, `src-ios/Libraries/Replay/Sources/replay-runner/main.swift` |
| twins: the Swift node over the Swift core | [W2](https://docs.modaal.dev/tutorials/duet-twins-02-two-cores#write-the-swift-shell-and-the-swiftui-view) | `tutorial2-twins-complete` | `src-ios/Subtrees/Splash/SplashNode/Sources/SplashNode/SplashViewShell.swift`, `src-ios/Subtrees/Splash/SplashNode/Package.swift` |

A path beginning `…/` is in the directory of the path before it in the same cell. The repository's `docs/`
directory holds every page as Markdown beside the trees.

## A tree's layout

| path | holds | shape |
| --- | --- | --- |
| `parity/` | `manifest.yaml`, `duet-tools.ref`, `feature-specs/`, `fixtures/`; from Tutorial 2, `scripts/apple-boundary-lane.sh`; from Tutorial 6, `mutations.json` | all |
| `tools/duet` | the CLI wrapper, resolving the CLI at `parity/duet-tools.ref` | all |
| `src-kmp/subtrees/<feature>/logic/` | one Kotlin module per feature: `commonMain` logic, `jvmTest` scenario, golden and `TestStore` tests | Kotlin |
| `src-kmp/ports/`, `src-kmp/backend-local/` | the port interfaces (Tutorial 3) and their on-device implementation (Tutorial 4) | Kotlin |
| `src-kmp/telemetry/`, `src-kmp/theming/` | the app's event grammar (Tutorial 9) and its theme module (Tutorial 7) | Kotlin |
| `src-kmp/replay-runner/` | the Kotlin replay runner `tools/duet protocol-run` drives | Kotlin |
| `src-kmp/apple-umbrella/` | the XCFramework module and, in `swift-consumer/`, the boundary replay suite | Kotlin |
| `src-kmp/app/` | the Compose app: Builders, screens, workers and their tests | Kotlin |
| `scripts/assemble_kit.sh` | assembles the XCFramework the iOS package links | Kotlin |
| `src-ios/Libraries/FoyerKit/` | the SwiftUI shells package: one `<Feature>Shell` target per feature, `FoyerBridge`, and `Tests/` | Kotlin |
| `src-ios/App/` | the iOS app: `xcodegen.yml` and the scene and app delegates | Kotlin, twins |
| `src-ios/Subtrees/<Name>/<Name>Feature/` | one Swift package per feature: logic, scenario and `TestStore` tests | Swift, twins |
| `src-ios/Subtrees/<Name>/<Name>Node/` | the feature's view shell and SwiftUI view | twins |
| `src-ios/Libraries/Replay/` | the Swift replay runner and its adapter | Swift, twins |
| `src-android/` | the Gradle root of the Kotlin twin: `subtrees/<feature>/logic/` on `kotlin.jvm`, `replay-runner/`, `app/` | twins |

## Fetching one tree

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/modaal-agent/duet-tutorials
git -C duet-tutorials sparse-checkout set tutorial3-complete
```

`sparse-checkout set` takes several trees; to read what one tutorial changed, check out its `-start` tree
and its `-complete` tree, or the previous tutorial's `-complete` tree, and diff them:

```bash
git -C duet-tutorials sparse-checkout set tutorial6-complete tutorial7-complete
git diff --no-index --stat duet-tutorials/tutorial6-complete duet-tutorials/tutorial7-complete
```

## The start and complete trees

- Each tutorial has a `-start` tree, the one the page opens, and a `-complete` tree, the page's end state.
- From Tutorial 2 on, a `-start` tree is the previous tutorial's `-complete` tree plus one deliberately
  failing test named `Tutorial<N>Exercise…`, the page's closing exercise. `TUTORIAL_SKIP_STUBS=1` leaves it
  out of the run. `tutorial1-start` carries no failing test.
- Tutorials 1 to 6 build on each other in order. Tutorials 7, 8 and 9 each start from Tutorial 6's
  finished tree and can be read in any order. Twins Tutorial 2 starts from Swift Tutorial 1's finished
  tree.
- Every tree resolves the family at the versions in the repository's `pins.env`, and the Swift-first
  track's trees pin a later duet-tools release than the Kotlin series. A tree's pins are the versions it
  was verified against, which can be older than the newest releases; take versions for an adopter's tree
  from `tools/duet pins --latest`, and read the CHANGELOG entries in between
  ([services.md](services.md) has the pin rule).
- A fenced block on a page is a verbatim excerpt of that page's `-complete` tree; the repository's
  `scripts/check-snippets.py` holds them equal.

Run a tree's own checks from inside the tree:

```bash
cd duet-tutorials/tutorial3-complete && tools/duet verify
```

Run every lane the repository's CI runs on a tree from the repository root; `--lane macos` skips the
Android app lane:

```bash
cd duet-tutorials && scripts/run-tree.sh tutorial3-complete --lane macos
```

`scripts/run-tree.sh` needs macOS with Xcode, a JDK 25, and an Android SDK for the trees with an Android
app; the `duet` CLI and Gradle are fetched at the tree's pins on first use.
