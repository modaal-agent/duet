# duet-services, design tokens, localization and analytics

[duet-services](https://github.com/modaal-agent/duet-services) is the layer an app adopts at its composition root.
One release tag publishes four Swift library products, one test-support product and two Kotlin Multiplatform
artifacts; an app links each one on its own.

## The products

| product | provides | depends on |
| --- | --- | --- |
| `DuetDiagnostics` | `DiagnosticsWorking`, the structured-logging port, and `DiagnosticsWorker` over `os.Logger`; `DiagnosticsHooks` is the one seam for a crash reporter | `DuetShells` |
| `DuetAppServices` | `InboundAppServicesWorker` (inbound URLs, the APNS token and payloads, lifecycle on `appLifecycle`) and `OutboundAppServicesWorker` (URL opening, pasteboard, haptics, audio session, tracking and push-permission prompts), one port per capability | `DuetShells` |
| `DuetAppServicesTestSupport` | `FakeAudioSession`, the double for the iOS-only audio-session port; test targets only | `DuetAppServices` |
| `DuetTelemetry` | `TrackedEvent`, `TrackedVerb`, `TrackedParam`, the `AnalyticsTracking` port, `AnalyticsTrackingWorking`, and the fan-out `AnalyticsTrackingWorker` | `DuetShells`, nothing outside `duet` |
| `DuetTheming` | `Theme`, `Themed`, `Assetable`, `Appearance<T>`, `ThemeProvider`, `ThemeScope`, `ThemedHostingController`; iOS only | nothing |
| `dev.modaal.duet.services:telemetry` | the same grammar and `AnalyticsTracking` in `commonMain`; `AnalyticsProviding`; `AnalyticsTrackingWorking` and `AnalyticsTrackingWorker` in `jvmMain` only | `dev.modaal.duet:kernel`, `shells-compose` (jvm), `kotlinx-serialization` |
| `dev.modaal.duet.services:theming` | `ColorToken`, `FontToken`, `GradientToken`, `FontFamilyToken`, `DuetFontFamily`, `DuetThemeSpec`, `ResolvedPalette`, `AppearanceStore` | `kotlinx-coroutines` |

The Kotlin artifacts target `jvm`, `iosArm64`, `iosSimulatorArm64` and `macosArm64`; Gradle selects the `-jvm`
variant for Android. No product declares a vendor SDK. Every unconditional Swift port carries
`sourcery: CreateMock`, so a tree's mock generation emits its doubles into the tree's own test targets.

## Adding the packages

Swift, in the package manifest, beside the `duet` line; the module names are the product names:

```swift
.package(url: "https://github.com/modaal-agent/duet.git", exact: "<duet tag>"),
.package(url: "https://github.com/modaal-agent/duet-services.git", exact: "<duet-services tag>"),
.product(name: "DuetTelemetry", package: "duet-services"),   // in a target's dependencies
```

Kotlin: declare the family's Maven host in `settings.gradle.kts`, filtered to `dev.modaal.*` as the tutorial
trees do so Gradle does not probe it for other groups:

```kotlin
dependencyResolutionManagement {
  repositories {
    maven {
      url = uri("https://modaal-agent.github.io/maven")
      content { includeGroupByRegex("""dev\.modaal(\..*)?""") }
    }
    mavenCentral()
    google()
  }
}
```

The tutorial catalogs name `dev.modaal.duet.services:telemetry` and `:theming` as `duet-services-telemetry` and
`duet-services-theming` under a `duetServices` version key beside `duet`. The Maven version is the release tag;
the host's metadata names the newest one in `<release>`:

```bash
curl -s https://modaal-agent.github.io/maven/dev/modaal/duet/services/telemetry/maven-metadata.xml
```

## The pin rule

duet-services pins `duet` with `exact:` in its `Package.swift`, and its Kotlin catalog names the same tag.
SwiftPM version-solves the app tree and every package it reaches as one graph, so a tree whose `duet` pin
differs from the tag its duet-services release carries fails to resolve before anything compiles. Pre-1.0
minors are breaking by family convention.

- Pin both repositories exactly: `exact:` in every Swift manifest, a fixed version in the Gradle catalog.
- Move the duet-services pin and the duet pin in one change, to a duet-services release that carries the new
  duet tag; a new duet tag is usable only once such a release exists. Its
  [CHANGELOG.md](https://github.com/modaal-agent/duet-services/blob/main/CHANGELOG.md) states each release's tag.

```bash
"${CLAUDE_SKILL_DIR}/scripts/family-pins.sh" check            # the tree's pins; exit 1 on a disagreement
"${CLAUDE_SKILL_DIR}/scripts/family-pins.sh" check --latest   # plus the duet tag the tree's duet-services pins
"${CLAUDE_SKILL_DIR}/scripts/family-pins.sh" latest           # the newest tag of each family repository
```

## Diagnostics and app services at the composition root

Each implementation is a worker ([composition-and-shells.md](composition-and-shells.md)). The composition root
constructs it, adopts it on its `StoreHost` with `host.adopt(…)`, and passes each node the narrowest port that
node calls (`URLOpening`, `PasteboardWriting`), so the node's test double has only the members the node uses.

```swift
let diagnostics = DiagnosticsWorker()          // os.Logger subsystem: the bundle identifier
host.adopt(diagnostics)
diagnostics.setHooks(DiagnosticsHooks(record: { error, userInfo in /* the crash reporter's call */ }))
let inboundAppServices = InboundAppServicesWorker()
let outboundAppServices = OutboundAppServicesWorker()
host.adopt(inboundAppServices)
host.adopt(outboundAppServices)
rootView.environment(\.hapticFeedback, outboundAppServices)
```

- Each `DiagnosticsHooks` closure defaults to `nil` (a no-op). Set the hooks in the one file that imports the
  crash-reporter SDK, after configuring it.
- `InboundAppServicesWorker` buffers inbound URLs and the APNS device token until `handlersDidRegister()`
  runs, then dispatches them in arrival order against the priority-ordered registry. The app's ingress worker
  takes `AppServicesRegistering`, registers the handlers from its `run()`, and calls `handlersDidRegister()`
  once, after the last one; without the call, a universal link tapped at cold launch stays in the buffer.
- `registerURLHandler(_:priority:)` returns an `AnyCancellable` that unregisters on release; hold it in
  main-actor code for the registering worker's lifetime.
- `\.hapticFeedback` defaults to `nil`; assign the adopted outbound worker on the root view. A view calls
  `hapticFeedback?.impactLight()`, which does nothing in a preview.
- `AppServicesRegistering` and `AppServicesAPNSHandlerRegistering` are declared under `#if canImport(UIKit)`
  and carry no `CreateMock`: hand-write their doubles in the test target.

## Theming

`DuetTheming` resolves `Themeable` and `ThemeDefaulting` by cast at the first lookup, so an app that declares
neither compiles and traps at its first themed render. Declare both in one file. The duet-services README
puts it in the app target; Tutorial 7 puts it in the package's `Theming` target, which every themed view's
target links:

```swift
import DuetTheming   // the whole file sits inside #if os(iOS)
extension Theme: @retroactive Themeable {
  public static let mainTheme = Theme(key: "mainTheme")
  public func themed() -> Themed {
    switch self {
    case .mainTheme: return MainTheme()
    default: fatalError("no theme is registered under the key \(key)")
    }
  }
}
extension ThemeDefaults: @retroactive ThemeDefaulting {
  public func defaultTheme() -> Theme { .mainTheme }   // Xcode previews and unhosted trees
}
```

`MainTheme` is a `Themed, Assetable` class; an asset family with no keys is `typealias _ImageAsset = EmptyAsset`.
A SwiftUI environment value does not cross a UIKit boundary, so each hosting root publishes one provider,
`ThemeProvider(persistentStorage: ThemePersistentStorage(), defaultTheme: .mainTheme, defaultPreferredAppearance: .system)`:

- one tree: `UIHostingController(rootView: ThemeScope(provider) { RootView() })`;
- several hosting roots: subclass `ThemedHostingController`, call `super.init(theme:rootView:)`, restate
  `required init?(coder:)`, and set content through `themedRootView` (assigning `rootView` does not compile).

A view reads `@Environment(\.theme)`; no view or view model takes a theme parameter. `ThemeProvider` runs on
the main actor and is not observable: after `setTheme(with:)`, re-publish the provider or invalidate the views.
`ThemePersistentStorage` writes JSON to `UserDefaults.standard`; conform another type to
`ThemeProviderPersisting` for an app group or a test. `DuetTheming` compiles for iOS only: in a package that
also builds for macOS, wrap each file that imports it, views included, in a whole-file `#if os(iOS)`.

The Kotlin `theming` artifact holds values and no Compose: `ColorToken.auto(light =, dark =)` in `0xAARRGGBB`,
`FontToken(family, weight, sizeSp, lineHeightSp, …)`. Tutorial 7 binds them through two composition locals,
its own `Theme` interface and the resolved appearance; `DuetThemeSpec` binds every Material `ColorScheme` and
`Typography` slot through `DuetColorRole` and `DuetFontRole`. In the newest release `FontFamilyToken` is an
interface, `DuetFontFamily.Serif`, `.Sans` and `.Mono` are the engine's families, and a resolver switches on
`token.family as DuetFontFamily` or on the app's own family enum; earlier releases declare it as an enum.

## Design tokens

`parity/design-tokens.yaml` declares the targets and the tokens. `tools/duet design-tokens` writes the
generated sources; `tools/duet design-tokens --check` regenerates in memory and names each **stale** file
(differs from the config) and **orphaned** file (a vocabulary the config dropped). The grammar is
[contracts/design-tokens.md](https://github.com/modaal-agent/duet-tools/blob/main/contracts/design-tokens.md).

```yaml
version: 1
swift:
  output: src-ios/Libraries/FoyerKit/Sources/Theming/Generated
  engine: DuetTheming
  theme: MainTheme
kotlin:
  output: src-kmp/theming/src/commonMain/kotlin/dev/modaal/foyer/theming/Generated
  package: dev.modaal.foyer.theming
  engine: dev.modaal.duet.services.theming
  palette: MainPalette
colors:
  - group: Labels
    tokens:
      - name: labelPrimary          # named for its meaning; becomes an enum case in both languages
        light: "#1A1A1A"
        dark: "#EDEDED"
```

- A font token (`fonts:`) states `family` (`serif`, `sans`, `mono`), `weight`, `size`, `lineHeight` and, while
  a `swift:` target is declared, `swift: { textStyle: … }`.
- Version 1 holds the tokens here. Version 2 names a W3C Design Tokens resolver (`tokens:
  design-tokens.resolver.json`); `tools/duet design-tokens migrate` rewrites version 1 as version 2. A CLI pin
  that does not read a config's version refuses it by name. The tutorial trees use version 1.
- Generated per language, and committed: `SemanticColor`, `SemanticFont` (plus `SemanticGradient`,
  `SemanticSpacing`, `SemanticRadius`, Kotlin's `SemanticFontFamily`, when declared) and the value table,
  `<theme>Palette.swift` (`MainThemePalette.swift`) and `<palette>.kt` (`MainPalette.kt`).
- Hand-written: the theme class and Swift's `fontSet(for:)`, the two registrations above, the accessors a
  view calls (`theme.color(.cardSurface)`, `SemanticColor.cardSurface.color()`), the Material and Apple
  role bindings, and the font resolvers.
- A second theme maps each token to an entry of the generated table (Tutorial 7's `HighContrastTheme`) and
  holds no values; its exhaustive `switch` and `when` stop compiling until a new token is mapped.
- Binding views to tokens changes no fixture. It edits shell sources, so run `tools/duet mocks` to re-record
  the fingerprints `tools/duet mocks --check` reads. `tools/duet verify` skips the theme module; CI runs:

```bash
tools/duet design-tokens --check
cd src-kmp && ./gradlew :theming:jvmTest
```

## Localization

[Tutorial 8](https://docs.modaal.dev/tutorials/duet-08-localization): shared state holds semantic values, and the
views hold every display string.

- A message the logic produces is a sealed value with one case per reason, coded with a
  `CanonicalSumSerializer` like the tree's other sums: `NameValidation.Empty`, `SignInFailure.NoAccount`; a
  port answers `SignInOutcome.Failed(reason: SignInFailure)`. Re-record each feature whose field changed type;
  from then on a translation changes no fixture.
- The view maps the case to a catalog key or a resource name (`switch onEnum(of: self)` in Swift). A view
  shell never resolves a string: the shells lane builds with SwiftPM on macOS, which copies
  `Localizable.xcstrings` uncompiled, so a lookup there returns the key.
- iOS: one `Localizable.xcstrings` per shell target (`resources: [.process("Localizable.xcstrings")]`),
  `defaultLocalization: "en"`, the xcstrings-tool plugin generating each target's `String.Localizable`, and
  `-skipPackagePluginValidation` on CI's `xcodebuild`. The app's `CFBundleLocalizations` lists every language.
- Android: `values/strings.xml`, one `values-<lang>/` per language, and `res/xml/locales_config.xml` named
  by the manifest's `android:localeConfig`.
- Neither build fails on a missing translation. Add a test per platform that holds each language's keys,
  plural categories and placeholders to the source language's, and one that fails when a fixture carries a
  string the resources hold (`RecordingsHoldNoDisplayTextTest` in `tutorial8-complete`).

## Analytics

[Tutorial 9](https://docs.modaal.dev/tutorials/duet-09-analytics): an event is a subject, a `TrackedVerb` and a
list of primitive `TrackedParam`s; `encodedName()` is `"<subject> <verb>"`, the name a vendor receives.

- The starter verbs are `Viewed`, `Opened`, `Started`, `Completed`, `Failed`, `Created`, `Edited`,
  `Deleted`, `Toggled` and `Signed Out`. Mint a verb only for an act they lack, spelled as a dashboard reads
  it: `val SignedIn = TrackedVerb("Signed In")` in Kotlin, a `static let` in a Swift extension.
- Parameters describe behavior, never content (the provider kind, not the address). Declare
  `object <Feature>Events` beside each emitting reducer, one builder per event.
- An event is an effect: a `Track(val event: TrackedEvent)` payload case, its serializer case,
  `fun track(event: TrackedEvent)` on the environment, and a fire-and-forget Runtime arm. The reducer that
  decides the transition emits it. List the event before a delegate event in the same effect list, because
  the delegate can end the mount and cancel the effects after it.
- Assert each `Track` in the scenario's `thenEffects` and in every chain that crosses the step, then
  re-record the features and the chains ([scenarios-and-fixtures.md](scenarios-and-fixtures.md)).
- Reducers never read consent. The app persists the user's choice, seeds `AnalyticsTrackingWorker(sinks:isEnabled:)`
  with it, and forwards each change to `setEnabled`, which reaches every sink. `sinks: []` drops every call.
- A vendor sink is one file conforming to `AnalyticsTrackingWorking`, the only file that imports the SDK.
  It pushes `setEnabled` to the SDK's opt-out switch and reads it back in `isEnabled`; with no readable
  switch, hold the flag in a `@Volatile` field (Kotlin) or behind a lock (Swift).
- The root adopts each sink, then the fan-out (which adopts none), before it builds its child slot. An event
  no reducer decides (a screen appearing) is a shell's direct `analytics.track` call.

Kotlin: an app grammar module (`:telemetry`) re-exports the artifact with `api(…)`, each emitting feature module
takes `api(project(":telemetry"))`, and each level's Dependency extends `AnalyticsProviding`. iOS: the fan-out
exists only in the JVM half, and a Kotlin `Track` effect carries the framework's bridged `TrackedEvent`. Export
the grammar module and the artifact from the umbrella ([kotlin-on-apple.md](kotlin-on-apple.md)), and write one
converter worker in the bridge target (Tutorial 9's `BridgedAnalyticsWorker`) that conforms to the bridged
`AnalyticsTracking`, holds `DuetTelemetry.AnalyticsTrackingWorker`, and converts each event: subject copied, verb
token verbatim, `Int32` widened to `Int`. duet-services' `contracts/telemetry-twin/` fixtures pin that the two
grammars encode identically.
