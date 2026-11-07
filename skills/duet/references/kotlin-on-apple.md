# The Kotlin core in the iPhone app

On the KMP flavor the iPhone app links the Kotlin core as one static XCFramework that Gradle builds,
and each Swift shell holds its Kotlin store through a mirror class. The Swift flavor and the twins
variant's iPhone app link no Kotlin; nothing here applies to them. Paths are the tutorial app's
([`tutorial2-complete`](https://github.com/modaal-agent/duet-tutorials/blob/main/tutorial2-complete)
and later trees); the framework there is `FoyerKit`.

| piece | path | role |
| --- | --- | --- |
| framework module | `src-kmp/apple-umbrella/build.gradle.kts` | one static framework over the kernel and every module Swift names |
| boundary file | `src-kmp/apple-umbrella/src/commonMain/kotlin/dev/modaal/foyer/kit/FoyerBoundary.kt` | the replay registry and the calls the Swift replay suite makes |
| assemble script | `scripts/assemble_kit.sh` | runs Gradle, copies the XCFramework to the consumed path |
| consumed path | `src-kmp/apple-umbrella/build/XCFrameworks/app/FoyerKit.xcframework` | the one path every Swift package links; not committed |
| boundary replay | `src-kmp/apple-umbrella/swift-consumer/` | replays every recording across the framework |
| consumer package | `src-ios/Libraries/FoyerKit/` | `FoyerBridge` (`BridgedStore`), one `<Feature>Shell` and one test target per feature |
| lane | `parity/scripts/apple-boundary-lane.sh` | assembles, then runs `swift test` in both packages |
| app spec | `src-ios/App/xcodegen.yml` | the scheme pre-action that assembles before each build |

## The framework module

- Build one framework per app. A static Kotlin/Native framework embeds the Kotlin runtime; two in
  one app carry it twice and can disagree about shared types.
- `export(...)` every module whose declarations Swift names and list it under `api(...)` in
  `commonMain`. A module that is linked but not exported compiles, and Swift cannot name a type from
  it. The tutorial exports each feature module, `:ports`, `:backend-local` and the kernel.
- Keep `isStatic = true` and the three arm64 targets: `iosArm64`, `iosSimulatorArm64`, and
  `macosArm64`, the slice a plain `swift test` on the Mac links.
- Give `commonMain` a source file; over an empty `commonMain` Gradle produces no XCFramework. The
  boundary file is that file.
- Apply SKIE (`co.touchlab.skie`) at the version the tree's catalog pins.

```kotlin
// src-kmp/apple-umbrella/build.gradle.kts
kotlin {
  val xcf = XCFramework("FoyerKit")
  listOf(macosArm64(), iosArm64(), iosSimulatorArm64()).forEach { target ->
    target.binaries.framework {
      baseName = "FoyerKit"
      isStatic = true
      export(dependencies.project(":subtrees:splash:logic")) // one line per module Swift names
      export(libs.duet.kernel)
      xcf.add(this)
    }
  }
  sourceSets {
    commonMain.dependencies {
      api(project(":subtrees:splash:logic"))
      api(libs.duet.kernel)
    }
  }
}
skie { analytics { enabled.set(false); disableUpload.set(true) } } // keeps the build hermetic
```

## What crosses as what

SKIE generates Swift wrappers over the Objective-C header Kotlin/Native exports
([Kotlin/Native GC and Swift ARC](https://docs.modaal.dev/articles/kotlin-native-gc-swift-arc)).

| Kotlin | Swift | in the trees |
| --- | --- | --- |
| sealed interface or class | a protocol or class per case, plus `onEnum(of:)` returning a Swift enum | `case .completed(let completed) = onEnum(of: event)` |
| `data object` case | a class named owner plus case, with `.shared` | `SplashActionCeremonyFinished.shared` |
| `data class` case | a class named owner plus case | `RootActionSplash(event: event)`, `SignInProviderEmail(address:)` |
| `StateFlow<T>` returned by a top-level function | `SkieSwiftStateFlow<T>`: `.value` and an `AsyncSequence` of `T` | `splashStateFlow(store:)`, `sessionsFlow(auth:)` |
| `StateFlow` declared on an interface | the raw `Kotlinx_coroutines_coreStateFlow`, which `for await` cannot iterate | `AuthPort.sessions` |
| interface | an Objective-C protocol, implemented by an `NSObject` subclass | `final class LiveSplashEnvironment: NSObject, SplashEnvironment` |
| `suspend` function | an `async` function to call; Swift cannot implement a `suspend` member | the ports below |
| `CoroutineScope` | `any Kotlinx_coroutines_coreCoroutineScope` | `RootComponent(dependency:scope:)` |

- Give each store a top-level function that returns `store.state` with concrete types
  (`splashStateFlow` in the splash module's `SplashRuntime.kt`), and each stream port member one
  too: `fun sessionsFlow(auth: AuthPort): StateFlow<Session> = auth.sessions`. Kotlin code reads the
  members directly.
- An exported interface carries no isolation, so a `@MainActor` class cannot conform to it. A
  main-bound worker that serves a port stores a non-isolated `NSObject` conforming to it, and its
  `run()` awaits `untilCancelled()` (`ReadinessSeam` in `tutorial5-complete`'s
  `OnboardingProgressWorker.swift`).
- Key a Swift `ChildSlot` on a Swift `Hashable` enum mapped with `onEnum(of:)`, as `RootViewShell`'s
  `PhaseKey`.

## `@Throws` on every boundary function that can throw

A Kotlin exception that reaches Swift through a function without `@Throws` terminates the process.
With `@Throws(SomeException::class)` Swift sees a `throws` function and catches an `Error` carrying
the Kotlin message.

```kotlin
// src-kmp/apple-umbrella/src/commonMain/kotlin/dev/modaal/foyer/kit/FoyerBoundary.kt
object FoyerBoundary {
  @Throws(IllegalArgumentException::class)
  fun canonicalize(rawJson: String): String = BoundaryReplay.canonicalize(rawJson)

  @Throws(IllegalArgumentException::class)
  fun makeSession(feature: String, initialStateJson: String): ReplaySession =
    BoundaryReplay.makeSession(registry, feature, initialStateJson)
}
```

The file's `registry` is a `ReplayRegistry` with one `ReplayFeature.entry(…)` per feature, naming
the feature, its state serializer, action and effect-payload serializers, and reducer. Swift calls
`FoyerBoundary.shared.makeSession(feature:initialStateJson:)`. The suite has a
`<Feature>BoundaryReplayTests.swift` with one method per recording, and
`BoundaryErrorChannelTests.swift`, which pins that an unregistered feature name arrives as a
catchable error.

## Ports are callback-shaped

A Swift class implements a Kotlin interface across the framework only when its members are plain
functions. Give every port operation a callback that fires once, and wrap it back into a suspending
call in the effect handler:

```kotlin
// tutorial3-complete/src-kmp/ports/src/commonMain/kotlin/dev/modaal/foyer/ports/Ports.kt
interface AuthPort {
  fun signIn(provider: SignInProvider, onOutcome: (SignInOutcome) -> Unit)
  fun signOut(onDone: () -> Unit)
}
// Callbacks.kt, in the same directory
suspend fun <T> awaitCallback(start: (onResult: (T) -> Unit) -> Unit): T =
  suspendCancellableCoroutine { continuation -> start { continuation.resume(it) } }
```

Swift implements it as `public final class MockAuth: NSObject, AuthPort` with
`onOutcome: @escaping (SignInOutcome) -> Void`. A void call whose result arrives on a stream
(`fun completeOnboarding(name: String, preferences: List<String>)`) takes no callback.

## Holding a Kotlin store: `BridgedStore`

`BridgedStore<State, Action>` (`src-ios/Libraries/FoyerKit/Sources/FoyerBridge/BridgedStore.swift`)
is a `@MainActor` `HostedObservation` with a `@Published` `state`, a synchronous `send` and
`cancel()`. Every shell uses the one copy in the `FoyerBridge` target through a typealias
(`public typealias SplashKitStore = BridgedStore<SplashState, any SplashAction>`).

```swift
// src-ios/Libraries/FoyerKit/Sources/SplashShell/SplashBuilder.swift
let scope = mainImmediateStoreScope()
let store = makeSplashStore(
  environment: LiveSplashEnvironment(onDelegate: onDelegate), scope: scope)
let bridged = SplashKitStore(
  state: splashStateFlow(store: store),
  send: { store.send(action: $0) },
  teardown: {
    store.teardown()
    cancelStoreScope(scope: scope)
  })
return SplashChild(shell: SplashViewShell(store: bridged))
```

- `send` forwards the action and re-reads `stateFlow.value` in the same call. The Kotlin store
  reduces on the calling thread (`mainImmediateStoreScope()` is
  `SupervisorJob() + Dispatchers.Main.immediate`), while a bridged `StateFlow` delivers in a later
  main-actor turn; the re-read lets a shell observe a reduce before `send` returns. Effect-fed
  actions reach the mirror one hop later, through its collector task.
- The collector task re-reads `value` on each delivery and ignores the delivered element, because
  the bridged sequence buffers and can deliver a state older than the mirror's.
- Releasing a Kotlin store does not stop it: a running effect keeps it reachable, so Kotlin/Native
  never frees it. `cancel()` stops the collector task, then runs `teardown`, which cancels the
  store's effects and then their scope.
- Adopt the mirror first in `bind()` (`host.adopt(store)`), so `deactivate()` stops the projection
  before the Kotlin runtime ([composition-and-shells.md](composition-and-shells.md)).
- Activate the root shell after `window.makeKeyAndVisible()`, and call the root's teardown from
  `sceneDidDisconnect`; dropping the reference cancels nothing on the Kotlin side.
- Hold a Kotlin store through a shell and a `BridgedStore`, never in SwiftUI `@State`: a store in
  `@State` is never stopped.

## Memory across the boundary

- A Kotlin object Swift holds is a collector root. After the last Swift release it is freed on a
  later collection: in a macOS test program, 0.30 s later while it allocated, 10.08 s later while
  idle, when the collector's timer fired.
- A Kotlin object holding a Swift object (an environment, a Swift port, their closures) releases it
  from the runtime's finalizer after the holder is collected, on the main thread for objects passed
  in on the main thread. That Swift object's `deinit` runs that late.
- A reference cycle through both Kotlin and Swift objects is never freed, and `leaks` reports
  `0 leaks` for it. Capture weakly in every closure handed to Kotlin:
  `LiveSplashEnvironment { [weak owner] event in owner?.handle(event) }`, `BridgedStore`'s
  `Task { [weak self] in … }`,
  `mounter.mountSignIn { [weak self] event in self?.store.send(RootActionSignIn(event: event)) }`.
- To find such a cycle, close the screen, wait 10 s, export the memory graph from Xcode and run
  `leaks --traceTree=<address> <file>.memgraph` on the instance that should be gone; a path through
  `Region Memory Tag 246` runs through the Kotlin heap.
- The collector pauses Kotlin-running threads twice per collection;
  [Kotlin/Native GC and Swift ARC](https://docs.modaal.dev/articles/kotlin-native-gc-swift-arc) has
  the measured pauses and why an Instruments recording changes them.

## Building and testing the Apple side

SwiftPM links the prebuilt binary and has no build-graph link to Gradle, so a bare `swift test` or
Xcode build links whatever was assembled last. After a Kotlin edit, run
`scripts/assemble_kit.sh debug` before `swift test`, or run `parity/scripts/apple-boundary-lane.sh`,
which assembles and then runs `swift test` in both packages. A green lane prints
`boundary replay: N test(s) executed`, `shells: N test(s) executed` and
`apple-boundary-lane: PASS in <n>s`.

- `scripts/assemble_kit.sh [debug|release]` runs `:apple-umbrella:assembleFoyerKitDebugXCFramework`
  (or the release task) and copies the result to the flavor-less consumed path; Debug and Release
  builds link the last assembly. It is the only writer of that path, and its last line is
  `assemble_kit: debug → src-kmp/apple-umbrella/build/XCFrameworks/app/FoyerKit.xcframework`.
- Xcode runs script phases with a minimal environment and no `JAVA_HOME`. The script sets it from
  `/usr/libexec/java_home` when unset, accepting only a JDK whose `release` file names the major the
  modules' `jvmToolchain` declares.
- The scheme's build pre-action in `xcodegen.yml` runs the script (`debug` for Debug, `release`
  otherwise) and exits 0 when the script is missing. After a fresh clone, assemble once before
  opening Xcode: package resolution reads the binary target before any pre-action runs.
- The first Kotlin/Native build downloads the toolchain and compiles three targets; allow ten
  minutes. Later assemblies take seconds.
- Pass `ARCHS=arm64` to a generic simulator build: it also compiles x86_64, where the framework has
  no slice and every exported declaration is out of scope. A concrete simulator destination is arm64
  already.
- Add `.linkedLibrary("c++")` and `.linkedFramework("Foundation")` to the target that links the
  binary target (`FoyerBridge`; `BoundaryTests` in the replay package): the Kotlin/Native runtime
  needs libc++ symbols Swift does not autolink. The shell targets depend on `FoyerBridge` and carry
  no linker settings.
- `swift test` exits 0 when it discovers no tests. The lane reads the larger of `Executed N tests`
  (XCTest) and `Test run with N tests` (swift-testing) per package and fails on zero.
- Swift shell tests run on real time: no test dispatcher crosses the boundary, so they poll in 20 ms
  slices against a ceiling. Pin timing on the Kotlin lane, on virtual time.
- Build every Swift target with `.enableExperimentalFeature("StrictConcurrency")` or the Swift 6
  language mode.

Generate and build the app from the command line:

```sh
cd src-ios/App
xcodegen generate --spec xcodegen.yml
xcodebuild build -project Foyer.xcodeproj -scheme Foyer -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO ARCHS=arm64
```

## Adding a feature module on the Apple side

1. `include(...)` it in `src-kmp/settings.gradle.kts`, and add its `export(...)` and `api(...)`
   lines to the framework module.
2. Add its `ReplayFeature.entry(...)` to the boundary file and to the Kotlin replay runner
   (`src-kmp/replay-runner/src/main/kotlin/dev/modaal/foyer/replayrunner/Main.kt`).
3. Add `<Feature>BoundaryReplayTests.swift` with one method per recording to
   `swift-consumer/Tests/BoundaryTests/`.
4. Add the feature's top-level `<feature>StateFlow(store:)` function, then a `<Feature>Shell` target
   and its test target to `src-ios/Libraries/FoyerKit/Package.swift`, with a `BridgedStore`
   typealias.
5. Run `scripts/assemble_kit.sh debug`, then `parity/scripts/apple-boundary-lane.sh`.
