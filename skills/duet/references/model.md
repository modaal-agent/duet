# The model: State, Action, Effect, Store

The normative text is the [kernel contract](https://github.com/modaal-agent/duet/blob/main/contracts/store-kernel-contract.md)
and the [serialization contract](https://github.com/modaal-agent/duet/blob/main/contracts/serialization.md).
Snippets are excerpts of the [duet-tutorials](https://github.com/modaal-agent/duet-tutorials/blob/main/README.md) trees
`tutorial1-complete` (Kotlin) and `tutorial1-swift-complete` (Swift), at the paths in their comments.

## The declarations

| Piece | Swift (`Duet`) | Kotlin (`dev.modaal.duet:kernel`) | Rule |
| --- | --- | --- | --- |
| State | `struct`, `Equatable, Codable` | `data class`, `@Serializable` | a value; every property encodes to canonical JSON |
| Action | `enum`, `Equatable, CanonicalSumCodable` | `sealed interface` of `data object` / `data class` | one case per user intent, system event or delegate output |
| EffectPayload | `enum`, `Equatable, CanonicalSumCodable` | `sealed interface` | a side-effect request as data, no closures |
| reducer | `(inout State, Action) -> [Effect<Payload>]` | `(S, A) -> Reduced<S, P>` | pure |
| effect handler | `(Payload) -> AsyncStream<Action>` | `(P) -> Flow<A>` | the only impure code; closes over the environment |
| environment | protocol | interface | every impure dependency: clock, ports, identity, storage |

State property names and Action and EffectPayload case names are the same camelCase words on both
flavors; a Kotlin subclass carries the Swift case name in `@SerialName` (`NotifyHost` is
`@SerialName("notifyListener")`). `tools/duet lint` compares them on a row with `swift:` and `kotlin:`.

## The reducer

```swift
// src-ios/Subtrees/Splash/SplashFeature/Sources/SplashFeature/SplashFeature.swift
public func splashReducer(state: inout SplashState, action: SplashAction) -> [Effect<SplashEffectPayload>] {
  switch action {
  case .appeared:
    guard !state.isArmed else { return [] }
    state.isArmed = true
    return [.run(.armSafetyNet(afterMillis: SplashConfig.safetyNetMillis), id: SplashEffectIds.safetyNet)]
  case .ceremonyFinished: return [.run(.notifyListener(.completed(path: .ceremony)))]
  case .safetyNetElapsed: return [.run(.notifyListener(.completed(path: .safetyNet)))]
  }
}
```

```kotlin
// src-kmp/subtrees/splash/logic/src/commonMain/kotlin/dev/modaal/foyer/splash/SplashFeature.kt
fun splashReducer(state: SplashState, action: SplashAction): Reduced<SplashState, SplashEffectPayload> =
  when (action) {
    SplashAction.Appeared ->
      if (state.isArmed) Reduced(state)
      else Reduced(
        state.copy(isArmed = true),
        listOf(Effect.Run(SplashEffectPayload.ArmSafetyNet(SplashConfig.SAFETY_NET_MILLIS), id = SplashEffectIds.SAFETY_NET)))
    // CeremonyFinished and SafetyNetElapsed each return Reduced(state, listOf(Effect.Run(NotifyHost(…))))
  }
```

- **The reducer takes no Environment.** A value it cannot compute (a fresh UUID, the current time)
  arrives as an action: the reducer returns `.run(.generateID)`, the handler yields
  `.idGenerated(uuid)`, the reducer stores it. A fixture then never holds a value the reducer invented.
- Every Swift mutation sequence is one Kotlin `copy(...)`; `Reduced(state)` is no change and no effects.
- Copy a constant the behavior depends on into the payload (`ArmSafetyNet(afterMillis)`), so a
  change to it shows up as a fixture diff.
- No `Double` or `Float` in fixture-visible types (the serialization contract); use an integer unit.

## Effect

| Swift: `enum Effect<Payload: Equatable>` | Kotlin: `sealed interface Effect<out P>` | Store behavior |
| --- | --- | --- |
| `.run(payload)` | `Effect.Run(payload)` | the handler runs it; only store teardown cancels it |
| `.run(payload, id: "splash.safetyNet")` | `Effect.Run(payload, id = "splash.safetyNet")` | cancel-in-flight: a running effect with the same id is cancelled first, then this one starts |
| `.cancel(id: "splash.safetyNet")` | `Effect.Cancel("splash.safetyNet")` | cancels the running effect with that id; a no-op when none runs |

Ids (`EffectID` / `EffectId`) are strings named `"<feature>.<purpose>"`, unique within one store. In
Kotlin, build expected lists with `effectsOf(...)` (`dev.modaal.duet.test`); `listOf(Effect.Cancel(id))` infers `Effect<Nothing>`.

## The environment and the runtime

```kotlin
// src-kmp/subtrees/splash/logic/src/commonMain/kotlin/dev/modaal/foyer/splash/SplashRuntime.kt
fun splashEffectHandler(environment: SplashEnvironment): (SplashEffectPayload) -> Flow<SplashAction> = { payload ->
  flow {
    when (payload) {
      is SplashEffectPayload.ArmSafetyNet -> {
        environment.clock.sleep(payload.afterMillis * NANOS_PER_MILLI)
        emit(SplashAction.SafetyNetElapsed)
      }
      is SplashEffectPayload.NotifyHost -> environment.notifyHost(payload.event)
    }
  }
}

fun makeSplashStore(environment: SplashEnvironment, scope: CoroutineScope) =
  Store(initialState = SplashState(), reducer = ::splashReducer, handler = splashEffectHandler(environment), scope = scope)
```

- The environment (`SplashEnvironment.kt` / `.swift`) exposes `clock: KernelClock` and the feature's
  other seams (`notifyHost`); only the handler reads it. A feature with no impure dependency has no environment.
- The Swift handler (`SplashRuntime.swift`) runs its body in a `Task` inside an `AsyncStream`, with
  `continuation.onTermination = { _ in task.cancel() }`, so a store cancel throws out of `clock.sleep`.
  Swift's `makeSplashStore(environment:)` is `@MainActor` and takes no scope.

## Store

| | Swift | Kotlin |
| --- | --- | --- |
| type | `@MainActor final class Store<State, Action, Payload>: ObservableObject` | `class Store<S, A, P>(initialState, reducer, handler, scope: CoroutineScope)` |
| state | `@Published private(set) var state: State` | `val state: StateFlow<S>` |
| send | `send(_:)`, main actor only | `send(action)`, on `scope`'s dispatcher only |
| teardown | `teardown()`, plus a best-effort cancel in `deinit` | `teardown()`, or cancel the host-owned `scope` |

1. `send` reduces synchronously, so the new state is observable before `send` returns; the returned
   effects then start in the order the reducer returned them.
2. An action a handler yields re-enters through `send`. An action sent during a reduce is queued and
   reduced after it; reduces never nest, and a handler never touches state.
3. The host calls `teardown()` when the screen or scope ends; it cancels every in-flight effect.

Production Kotlin hosts run the store on `Dispatchers.Main.immediate`: `mainImmediateStoreScope()` and
`cancelStoreScope(scope)` (`dev.modaal.duet.kernel.runtime`) build and end that scope. A Swift shell
over a Kotlin store needs a typed `commonMain` accessor (`fun splashStateFlow(store): StateFlow<SplashState>`);
[kotlin-on-apple.md](kotlin-on-apple.md) has the boundary, [composition-and-shells.md](composition-and-shells.md) the shells.

## The clock seam

| | Swift | Kotlin |
| --- | --- | --- |
| seam | `protocol KernelClock { func sleep(nanoseconds: UInt64) async throws }` | `fun interface KernelClock { suspend fun sleep(nanoseconds: Long) }` |
| production | `LiveClock()` | `LiveClock` (an `object` over `delay`) |
| tests | `TestClock()` from `DuetTesting`; `await clock.advance(byNanoseconds:)` | `LiveClock` under `runTest`: `advanceTimeBy(ms)`, then `runCurrent()` |

Handlers wait through `environment.clock`, never `Task.sleep` or `delay`; tests run on virtual time only.

## TestStore and finish()

`TestStore` (`DuetTesting`, `dev.modaal.duet:kernel-test`) runs the real reducer and the real handler
against a test environment and records everything. The Kotlin one takes `scope:`: pass the `TestScope`.

| Call | Swift | Kotlin |
| --- | --- | --- |
| send, assert the whole new state | `store.send(.appeared) { $0.isArmed = true }` | `store.send(SplashAction.Appeared) { it.copy(isArmed = true) }` |
| take a handler-emitted action | `await store.receive(.safetyNetElapsed)` | `store.receive(SplashAction.SafetyNetElapsed)` (suspend) |
| assert the effects since the last call | `store.expectEffects([...])` | `store.expectEffects(listOf(...))` |
| end the test | `await store.finish()` | `store.finish()` (suspend) |

| Failure | When |
| --- | --- |
| E1 | a `send` or `receive` closure does not produce exactly the post-reduce state |
| E2 | `finish()` finds an effect never asserted with `expectEffects` |
| E3 | `finish()` finds an action a handler delivered that the test never `receive`d |
| E4 | `receive` is called and no action arrives |
| E5 | `finish()` finds an effect still in flight; call `store.teardown()` first when one is long-lived |

```swift
// src-ios/Subtrees/Splash/SplashFeature/Tests/SplashFeatureTests/SplashTestStoreTests.swift
func testSafetyNetFiresAfterItsDuration() async {
  let clock = TestClock()
  let environment = SplashEnvironmentMock(clock: clock)
  let store = armedStore(environment)          // send(.appeared) { $0.isArmed = true } + expectEffects
  await clock.advance(byNanoseconds: nanos(SplashConfig.safetyNetMillis))
  await store.receive(.safetyNetElapsed)
  store.expectEffects([notifySafetyNet])
  await store.finish()
  XCTAssertEqual(environment.notifyHostArgs, [.completed(path: .safetyNet)])
}
```

```kotlin
// src-kmp/subtrees/splash/logic/src/jvmTest/kotlin/dev/modaal/foyer/splash/SplashTestStoreTest.kt
@Test
fun teardownCancelsTheArmedNet() = runTest {
  val environment = RecordingSplashEnvironment()   // clock = LiveClock; records each notifyHost event
  val store = armedStore(environment)              // TestStore(..., scope = this)
  store.teardown()
  advanceTimeBy(SplashConfig.SAFETY_NET_MILLIS * 3)
  runCurrent()
  store.finish()
  assertEquals(emptyList(), environment.notified)
}
```

## Canonical JSON

| Value | Encoding |
| --- | --- |
| object keys | sorted by Unicode scalar value at every level |
| nil / null | key omitted, never `null` (kotlinx: `explicitNulls = false`) |
| a property equal to its default | encoded (kotlinx: `encodeDefaults = true`) |
| Int / Long | integer, no fraction or exponent |
| Date / `Instant` | ISO-8601 UTC, three fractional digits, `Z` |
| UUID | lowercase 8-4-4-4-12 |
| map | string keys only |
| raw-value enum | the raw value as a bare scalar |
| sum type | `{"case": "increment"}`, `{"case": "armSafetyNet", "value": {"afterMillis": 3000}}`; one unlabeled payload encodes bare under `value` |
| Effect | `{"kind": "run", "id": "splash.safetyNet", "payload": {…}}`, `{"kind": "cancel", "id": "…"}`; `id` omitted on an anonymous run |

Kotlin: `CanonicalSerializers.json` is the pinned configuration (`kotlin.uuid.Uuid` and
`kotlin.time.Instant` registered). Each sealed root carries `@Serializable(with = …)` and one registry
line per case; `inline = true` marks a case whose Swift twin has one unlabeled payload:

```kotlin
// src-kmp/subtrees/splash/logic/src/commonMain/kotlin/dev/modaal/foyer/splash/SplashSerializers.kt
object SplashEffectPayloadSerializer : CanonicalSumSerializer<SplashEffectPayload>(
  "SplashEffectPayload",
  listOf(
    case(SplashEffectPayload.ArmSafetyNet::class, SplashEffectPayload.ArmSafetyNet.serializer()),
    case(SplashEffectPayload.NotifyHost::class, SplashEffectPayload.NotifyHost.serializer(), inline = true),
  ))
```

Swift: declare `CanonicalSumCodable` on the enum and run `tools/duet canonical-sum`, which writes one
committed file per source file (`SplashFeature.swift` gives `SplashSerialization.generated.swift`);
never edit it. Until it exists the build fails with `type 'X' does not conform to protocol
'CanonicalSumCodable'`. `tools/duet record` regenerates the coders first; `record --check` fails on
stale ones. The `@CanonicalSum` macro in duet-macros is the opt-in alternative ([duet README](https://github.com/modaal-agent/duet/blob/main/README.md)).

## Fixture dialects

| Dialect | File | Checked fields | Metadata (not gated) |
| --- | --- | --- | --- |
| feature fixture | `parity/fixtures/<fixture>.fixture.json`; a branch leaf is `<fixture>.<slug>` | `initialState`, each step's `action`, `expectedState` (the full state), `expectedEffects` (ordered) | `dialect: 2`, `feature`, `description`, `scenario.source`, `scenario.branch`, step `label` and `line` |
| chain fixture | `parity/fixtures/chain-<name>.fixture.json` | `initialStates` (one per node), each step's `node`, `action`, `expectedEffects`, `linkToNext` | the same metadata, plus `chain` |

- A chain fixture has no `expectedState`; leaf fixtures own state. `linkToNext: true` asserts that
  the step's last `notifyListener` payload is byte-identical to the value in the next step's action.
- A replay seeds the initial state, reduces each recorded action, compares canonical strings, and
  stops at the first divergent step, naming the fixture, the step, its label and the JSON path. Each
  run writes `parity/.runs/<platform>/<fixture>.json`, which `tools/duet explain` reads.
- On disk: 2-space indent, sorted keys, `{}` and `[]` inline, one trailing newline. The CLI and the
  Swift record mode share one writer. The DSLs that write fixtures are in
  [scenarios-and-fixtures.md](scenarios-and-fixtures.md).

## The three shapes

| | KMP flavor | Swift flavor | twins |
| --- | --- | --- | --- |
| feature logic | Kotlin `commonMain`, `src-kmp/subtrees/<f>/logic` | Swift package `src-ios/Subtrees/<Name>/<Name>Feature` | both: that Swift package, and a plain JVM module `src-android/subtrees/<f>/logic/src/main` |
| iPhone app runs | the Kotlin core, through one Kotlin/Native XCFramework | the Swift core | the Swift core |
| Android app runs | the Kotlin core | (no Android app) | the Kotlin core |
| manifest row | `kotlin:` only | `swift:` only | `swift:` and `kotlin:`, top-level `kotlinCore: jvm` |
| fixture writer | the Kotlin scenario | the Swift scenario | the scenario `scenario:` names; the other side's scenario calls `ScenarioRunner.verify` |
| lanes | Kotlin (`:<module>:jvmTest`), plus the Apple boundary script | Swift (`swift test` per package) | both, plus `tools/duet protocol-run --platform both` |

- **KMP flavor**: dual-platform apps with the logic written once; the iOS app links the Kotlin/Native runtime.
- **Swift flavor**: Apple-only apps, including Mac Catalyst and visionOS, which Kotlin/Native does not target.
- **Twins**: each platform's team owns its language, or the iPhone app must not link Kotlin/Native.
  Every behavior change edits both reducers ([Duet Twins](https://docs.modaal.dev/articles/duet-twins),
  [Twins Tutorial 2](https://docs.modaal.dev/tutorials/duet-twins-02-two-cores)).

Terms are defined in the [Duet glossary](https://docs.modaal.dev/articles/duet-glossary).
