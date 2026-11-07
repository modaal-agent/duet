# Composition, shells, workers and navigation

Swift symbols are in the `DuetShells` product of `duet`; Kotlin symbols are in
`dev.modaal.duet:shells-compose`, a JVM artifact on coroutines and Flow with no Compose dependency.
KMP-flavor iPhone shells hold a Kotlin store through `BridgedStore`
([kotlin-on-apple.md](kotlin-on-apple.md)). Comment paths are tutorial trees
([worked-examples.md](worked-examples.md)).

## The composition triple at every level

A composition level is any node that mounts children: the root, each subtree node, each leaf
([composition.md](https://github.com/modaal-agent/duet/blob/main/docs/composition.md)).

| part | holds | must not |
| --- | --- | --- |
| `<X>Dependency` | exactly the members this level reads from its parent | name a member the level does not read |
| `<X>Component` | one `<X>Dependency`; forwards what passes through, owns what is scoped to the level, conforms to each child's Dependency | reach outside `dependency` for anything it does not own |
| `<X>Builder` | `dependency: <X>Dependency`; constructs the Component once per mount, then the store, shell and view | resolve anything itself |

- Write one triple per level; an app-wide interface makes every double implement every member. Build
  the Component once per mount, in the build function; a Component stored on the Builder lives as
  long as the app.
- Owned members are `lazy var` (Swift) or `by lazy` (Kotlin); forwarded members are computed `var`s
  reading `dependency` (Swift) or come through `by dependency` (Kotlin).
- Supply a child's Dependency by conforming the parent's Component to it:
  `extension MainComponent: TimelineDependency {}` in Swift, the interface in the supertype list in
  Kotlin. Deleting a Dependency member then breaks the parent at compile time.
- Keep a Component that owns nothing; it carries the child conformances. The root's Dependency may
  be empty (`public protocol RootDependency: AnyObject {}`, conformed by `SceneComponent`).
- In Swift, annotate a Dependency `/// sourcery: DuetComponent` and `/// sourcery: CreateMock`, add
  `mocks:` rows to `parity/manifest.yaml` and run `tools/duet mocks` for its forwarding Component
  and its double ([cli.md](cli.md)). Write a Component that owns objects by hand.

```kotlin
// tutorial3-complete/src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/SignInBuilder.kt
interface SignInDependency { val auth: AuthPort }
class SignInComponent(dependency: SignInDependency) : SignInDependency by dependency {
  fun environment(onDelegate: (SignInDelegateEvent) -> Unit): SignInEnvironment =
    object : SignInEnvironment { /* signIn → auth.signIn; notifyHost → onDelegate */ }
}
class SignInBuilder(private val dependency: SignInDependency) {
  fun buildSignIn(onDelegate: (SignInDelegateEvent) -> Unit, scope: CoroutineScope): SignInStore {
    val component = SignInComponent(dependency)
    return makeSignInStore(environment = component.environment(onDelegate), scope = scope)
  }
}
```

### Environment factories and ports

- Put the factory that assembles `<X>Environment` on the Component, so no Builder names a
  repository; it may return the concrete `Live<X>Environment`. A factory whose environment adopts a
  worker onto a caller's `StoreHost` goes on the Component of the level that owns that host.
- A port is an interface the logic calls and each app implements, kept with its value types in one
  common module (`src-kmp/ports`). Dependencies carry ports; the root Component owns the
  implementations (`LocalBackend` in `tutorial4-complete`'s `RootBuilder.kt`). On the KMP flavor a
  port operation takes a one-shot callback, because Swift cannot implement a `suspend` member; a
  stream member is a sticky `StateFlow`.

## Events up the tree

- A child reports with a delegate event: its reducer emits an effect carrying it (Kotlin
  `NotifyHost`, serial name `notifyListener`), and `notifyHost` calls the parent's `onDelegate`.
- The parent receives it as its own action, one case per child
  (`data class Splash(val event: SplashDelegateEvent) : RootAction`):
  `onDelegate = { store.send(RootAction.SignIn(it)) }`, in Swift
  `{ [weak self] event in self?.store.send(RootActionSignIn(event: event)) }`.
- Guard late events in the parent's reducer: both splash paths notify, and a `Completed` after the
  splash phase returns the state unchanged.
- Record each seam as a chain; the chain runner finds the delegate at a hop by the serial name
  `notifyListener` ([scenarios-and-fixtures.md](scenarios-and-fixtures.md)).

## Events from a view: `AnyActionHandler` and `Relay`

| case | Swift | Kotlin |
| --- | --- | --- |
| the receiver exists when the view is built | `presenter.saveRequested = AnyActionHandler(self) { shell, _ in shell.store.send(.saveTapped) }`; the view calls `saveRequested?.invoke()` | a function type, `((Event) -> Unit)?`, or `onClick = { shell.store.send(DetailAction.SaveTapped) }` |
| the receiver is built after the sender | `let relay = Relay<Route>()`; hand `{ relay.send($0) }` to the child; later `relay.bindSink(self) { root, route in root.store.send(.routed(route)) }` | `Relay<Event>()`: the same `send`, `sink`, `bindSink(owner) { owner, event -> … }` |

- `AnyActionHandler(owner)` and `bindSink(owner)` hold the owner weakly: a call after the owner is
  gone does nothing, and an event sent before `sink` is set is dropped. Assign `sink` directly for a
  non-owner capture (`relay.sink = store::send`). `mapHandler { … }` adapts the argument type.
- Neither Swift type is `Sendable`, so a handler stays in the isolation domain that formed it. To
  pass one between domains, annotate it `@MainActor`; `@unchecked Sendable` removes the check.

## The shell symbols

| symbol | Swift (`DuetShells`) | Kotlin (`shells-compose`) | does |
| --- | --- | --- | --- |
| `StoreHost` | `@MainActor final class StoreHost()` | `StoreHost(scope: CoroutineScope)` | a mount's teardown registry; `teardownAll()` runs in reverse registration order, and a second call does nothing |
| `host(_:)` | `host(store)` | `host(store)` | registers `store.teardown()`, returns the store |
| `adopt(_:)` | `ChildStores`, `ChildSlot`, a `HostedObservation` (`Store` conforms on Swift only), a `Working` worker, `adopt(teardown:)` | the same; the closure form is `adoptTeardown { }` | registers and returns what it adopts |
| `liveWorkerCount` | on `StoreHost` | on `StoreHost` | adopted workers whose `run()` has not returned; zero shortly after `teardownAll()` |
| `ViewShell` | `open class ViewShell: Activatable`: `bind()`, `unbind()`, `activate()`, `deactivate()`, an owned `host` | no class; the composable is the shell, `Activatable` is in `ChildHandles.kt` | `activate()` runs `bind()`; `deactivate()` runs `unbind()`, then `host.teardownAll()` |
| `ChildSlot` | `reconcile(key:)`, `activeKey`, `activeHandle` | `reconcile(key)`, `activeKey`, `activeHandle` | one child: built when the key appears, rebuilt when it changes, torn down at nil |
| `ChildStores` | `handle(for:)`, `reconcile(keys:)`, `activeCount` | `handleFor(key)`, `reconcile(keys)`, `activeCount` | stack children keyed by route value; equal routes share one child |
| `StoreChild`, `ViewShellChild` | UIKit only; carry `viewController` | carry the shell only | handle for an owned store (`teardown()`: shell, then store) or a permanent tab |
| `StateTransitions` | `StateTransitions(state: store.$state) { old, new in … }` | `StateTransitions(scope, store.state) { old, new -> … }` | `(old, new)` pairs; first call `(current, current)`; duplicates filtered |
| `ProjectionJoin` | `ProjectionJoin(state:joining:initialAux:apply:)` | `ProjectionJoin(scope, state, joining, initialAux, apply)` | re-runs `apply` with the latest state and auxiliary value when either arrives |
| `PresentationRegistry` | `register(Kind.self) { kind in … }` returning `AnyView?`; `view(for:)` | `PresentationRegistry<Surface>`, `register(Kind::class) { … }`, `surfaceFor(kind)` | kind-to-renderer table for an interior host; a Kotlin sealed root covers every case |
| `RouteSpineCodec` | `encode(_:)` → `String?`; `decode(_:from:)` → nil when unreadable | `SpineBoundary.encode(serializer, spine)` / `decode` in `dev.modaal.duet:kernel` | the route spine's string codec |
| `RestoredSpineBox` | in `RouteSpineCodec.swift` | `RestoredSpineBox.kt` | one-shot holder for a restored spine: `take()`, `discard()`, `place(_:)` |
| `RetainedRoot` | no twin | `RetainedRoot(context, teardown, create)`, an Essenty `InstanceKeeper.Instance` | Android retained scope and root; `onDestroy` tears the component down, then cancels the scope |
| `kernelStream()` | `Publisher.kernelStream()` | no twin | the one Combine-to-`AsyncStream` bridge environments call |

### Adoption order in `bind()`

Register in creation order; teardown runs in reverse. The tutorial shells adopt, in order:

1. The store: `host.adopt(store)` for a `BridgedStore`, `host.host(store)` for a Swift `Store`.
2. The child reconciler, a `ChildSlot` whose teardown deactivates the child's shell.
3. The projection, a `StateTransitions`; its replay of the current value is the first projection.
4. The workers, so each sticky stream's first value reaches a bound projection; they stop first.

```swift
// tutorial3-complete/src-ios/Libraries/FoyerKit/Sources/RootShell/RootViewShell.swift
override public func bind() {
  host.adopt(store)
  child = host.adopt(
    ChildSlot<PhaseKey, RootChildMount>(
      build: { [weak self] key in self?.build(key) },
      teardown: { mount in /* deactivate the mounted child's shell */ }))
  host.adopt(StateTransitions(state: store.$state) { [weak self] _, state in self?.apply(state) })
}
```

- In a Swift projection read the state the callback receives: `@Published` publishes before it
  assigns, so `store.state` still holds the previous value.
- Activate permanent tabs in the level's `bind()` and register their deactivation with
  `host.adopt { … }` (`tutorial5-complete`'s `MainViewShell.swift`).
- Kotlin's `StateTransitions` and `ProjectionJoin` collect on the host scope
  (`Dispatchers.Main.immediate`): a reduce is observed after `send` returns, and `StateFlow` can
  conflate states. Reconcile from the latest state only.

## Workers

A worker owns a long-lived subscription, cache, timer or device bridge for one mount
([workers.md](https://github.com/modaal-agent/duet/blob/main/docs/workers.md)): Swift
`protocol Working: AnyObject, Sendable { func run() async }`, Kotlin
`fun interface Working { suspend fun run() }`. Its results reach feature state only through an
environment stream an effect handler consumes, or as actions on a shell-bound `Relay`. It never
touches a store or feature state; decisions go in a reducer.

- `host.adopt(worker)` starts `run()` in a task (Kotlin: a coroutine on the host's scope);
  `teardownAll()` cancels it. There is no `stop()`; a remount adopts a fresh instance. Return from
  `run()` on cancellation; a subscription-shaped worker sets up, then awaits `untilCancelled()`.
- Feed "pause when backgrounded" in as an input stream. Model per-entity work as effects canceled by
  effect id. On Android adopt workers on the retained scope, so rotation does not restart them.

Isolation on Swift:

- Make a stateful worker an `actor`, or a `@MainActor` class when main-bound; no lock, serial queue
  or unstructured `Task {}`. A `@MainActor` class conforms to `Working` unchanged, and its `run()`
  body runs on the main actor, so off-main routing inside it (`.subscribe(on:)`, a `DispatchQueue`)
  contradicts the annotation with no diagnostic.
- Never mark a `Working` conformer `@unchecked Sendable`: it compiles silently on a `@MainActor`
  class and turns checking off on any other. `tools/duet doctor`'s `[workers]` row reports one in
  non-test sources and exits 1.
- Isolation is checked only under strict concurrency:
  `.enableExperimentalFeature("StrictConcurrency")` or `swift-tools-version:6.0` with
  `.swiftLanguageMode(.v6)`. `.unsafeFlags(["-swift-version", "6"])` in a 5.9 manifest does nothing.

```kotlin
// tutorial4-complete/src-kmp/app/src/main/kotlin/dev/modaal/foyer/app/workers/SessionWorker.kt
class SessionWorker(private val auth: AuthPort, private val relay: Relay<RootAction>) : Working {
  override suspend fun run() {
    auth.sessions.collect { session -> relay.send(RootAction.AuthChanged(authSnapshot(session))) }
  }
}
// RootBuilder.kt, after the child slot and the projection
val relay = Relay<RootAction>()
relay.sink = store::send
host.adopt(SessionWorker(component.auth, relay))
```

Name each seam's shape in the feature spec's effect inventory: a tick stream whose failures arrive
as values; a fire-and-forget bridge whose completions return as stream events; a keyed per-entity
clock canceled per key; a sticky flag (`StateFlow`) or a one-shot event tick.

For a value one sibling produces and another reads, the lowest common ancestor's Component owns one
worker `lazy`, gives the producer a void update port and the consumer a sticky observation port, and
its level adopts the worker last (`tutorial5-complete`'s `OnboardingProgressWorker`).

### Testing workers

Test workers behaviorally with `WorkerTester`; workers have no recordings.

- Swift (`DuetTesting`): `WorkerTester(worker)`, `start()`, drive fakes, `await finish()`, which
  cancels, yields until `run()` returns and fails the test otherwise; synchronous suites poll
  `isFinished` after `cancel()`. Kotlin (`kernel-test`): `start(backgroundScope)`, `runCurrent()`,
  `finish()`.
- Extract the stream-value-to-action transform as a pure function in the logic module
  (`authSnapshot(session)`) and unit-test it once.
- Assert `host.liveWorkerCount`: `2` while the tutorial's root is up, zero shortly after teardown.

## Navigation as state

Every screen follows from a value in feature state; the shell mounts children from it with
`ChildSlot` or `ChildStores`. The primitives of the
[presentation contract](https://github.com/modaal-agent/duet/blob/main/contracts/presentation-contract.md):

| primitive | shape | rules |
| --- | --- | --- |
| `path` | `var path: [Route]` / `val path: List<Route>` | a stack; entries pop on back |
| `slot` | `var sheet: Sheet?` / `val sheet: Sheet?` | one modal child per node; a stacked modal is a presented child owning its own slot |
| `tabs` | `var activeTab: Tab` | user-switchable; every tab stays alive |
| `stage` | `var phase: Phase`, non-optional | one full-screen child; transitions are reducer edges; a child is destroyed on exit |

Toasts and error banners are plain reducer fields; there is no overlay primitive. Payloads are pure
values (ids, configs, flags), never live objects.

- Change structure only in a reducer arm answering a named action; a host never writes a route
  field. An interactive dismissal returns as the view's report action, guarded against stale
  reports. The `NavigationStack` pop gesture sends `.backPressed`; a canceled swipe sends nothing.
- Back is an action on the level that owns the page; the reducer reads it against the current step.
- On Android the last composed enabled `BackHandler(enabled = …)` wins: compose shallow to deep with
  the sheet last, and keep the predicates in one pure table with `winner(spine)` and a test
  (`tutorial5-complete`'s `BackPolicy.kt`). A gate installs none, so back there leaves the app. iOS
  screens send the same actions from their Back buttons.
- Mount a sheet from its slot through a `ChildSlot`. Render `.sheet(isPresented:)` on iOS, the
  binding's setter calling the flow's dismissal intent, and
  `ModalBottomSheet(onDismissRequest = { store.send(UpgradeAction.DismissTapped) })` on Android,
  which gets swipe and system back. The flow's reducer decides what a dismissal means per step.
- Deep links: parse with one common function (`parseDeepLink`), send `DeepLink(link)` to the root,
  forward it one level at a time as an effect once the target is mounted, and hold it in state
  (`pendingLink`) until then. Test with `xcrun simctl openurl booted <url>` and
  `adb shell am start -a android.intent.action.VIEW -d <url>`.
- Process death: gather each level's route field into one spine, encoded canonically and decoded
  tolerantly (null when stale), saved from `stateRestorationActivity(for:)` on iOS and
  `onSaveInstanceState` on Android. Apply each field as its store's initial state when its child
  mounts; the splash replays and the session decides the phase. Hold the decoded spine in a
  `RestoredSpineBox`. Test with `adb shell am kill <package>`.

### The presentation contract's layers

| layer | what | open or closed | cross-platform obligation |
| --- | --- | --- | --- |
| L0 | the primitives above | closed; an addition is a versioned contract change | identical fields and serialization, gated by fixtures |
| L1 | kinds: the cases of route, sheet and tab enums | open | identical kinds and payloads |
| L2 | verbs: the actions that change L0 fields | open | identical verbs and reductions, gated by fixtures |
| L3 | manner: detents, covers, `ModalBottomSheet`, chrome | open per platform | free; a divergent manner class gets a `presentation.waivers` entry in `parity/manifest.yaml` |
| L4 | islands: regions whose internal state lives outside the tree | open; listed in `presentation.islands` | declared identically, identical boundary summaries |

Keep manner in the renderer; a `detent` field in feature state breaks the contract. A
`PresentationRegistry` belongs on an interior host whose kinds accumulate; a node whose kinds render
inside its own view renders them directly.
