# Store kernel contract (v1 — FROZEN)

The API contract that **both** core flavors implement:

- Swift flavor: `Duet` (+ `DuetTesting`) — this repository, `swift/`
- KMP flavor: `dev.modaal.duet:kernel` (+ `:kernel-test`) — this repository,
  `kotlin/`

**v1 is declared FROZEN: the contract-observable runtime rules
are machine-verified — both flavors replay the kernel-trace fixtures
(kernel-trace-v0.md) byte-identically under virtual time. Changes to frozen
semantics happen only at a major version; a machine-verified, frozen twin has
~zero carrying cost.**

This document is normative and versioned with the code. When an implementation and this
document disagree, one of them is a bug — fix whichever is wrong *and record the
divergence*.

Bracketed stage tags (**[S0]**, **[S1]**, **[S4]**) are provenance — when an obligation
was derived on the reference corpus — not status. Every obligation below is in force.

---

## 1. The shapes

A *feature* is four declarations plus wiring:

| Piece | Swift | Kotlin | Requirements |
| --- | --- | --- | --- |
| `State` | `struct`, `Equatable + Codable` | `data class`, `@Serializable` | Pure value. Serializes to canonical JSON (see `serialization.md`). |
| `Action` | `enum` w/ associated values, `Equatable + Codable` | `sealed interface` + `data object`/`data class`, `@Serializable` | Sum type. One case per user intent / system event / delegate output. |
| `EffectPayload` | `enum`, `Equatable + Codable` | `sealed interface`, `@Serializable` | Sum type describing side-effect *requests* as **data**. No closures. |
| `Reducer` | `(inout State, Action) -> [Effect<EffectPayload>]` | `(State, Action) -> Reduced<State, EffectPayload>` | **Pure.** Same-input ⇒ same-output on both platforms — this is what golden fixtures assert. |
| `EffectHandler` | `(EffectPayload) -> AsyncStream<Action>` | `(EffectPayload) -> Flow<Action>` | The *only* impure piece. Built by closing over an `Environment`. |
| `Environment` | protocol(s) | interface(s) | All impurity: clocks, repositories, ID generators, session. Protocol-based with deterministic fakes (the mockability mandate). |

### Mapping rule: reducer signatures

Swift mutates `inout` (idiomatic, avoids full-copy churn); Kotlin returns a new value via
`copy(...)`. The **mechanical translation rule** is:

```swift
// Swift
state.count += 1
return []
```
```kotlin
// Kotlin
return Reduced(state.copy(count = state.count + 1))
```

Every Swift mutation sequence maps to one `copy(...)` (or a small chain for nested state —
an accepted ergonomics cost). `Reduced` is:

```kotlin
data class Reduced<S, P>(val state: S, val effects: List<Effect<P>> = emptyList())
```

### Decision D1 — the reducer takes NO Environment **[S0]**

Because effects are data, the reducer never needs a live dependency. Consequence: state
changes that need nondeterministic inputs (UUID, now()) must round-trip through an effect:

```
.run(.generateID)  →  handler yields  .idGenerated(uuid)  →  reducer stores it
```

This keeps goldens trivially deterministic (a fixture never contains a fresh UUID the
reducer invented) and is the `serialization.md` "injected determinism" rule made structural.
If the round-trip proves too noisy for a real feature, revisit — as a versioned
contract change, never a silent one.

## 2. `Effect` — the kernel-level wrapper **[S0]**

```swift
public typealias EffectID = String

public enum Effect<Payload: Equatable>: Equatable {
  case run(Payload, id: EffectID? = nil)
  case cancel(id: EffectID)
}
```
```kotlin
typealias EffectId = String

sealed interface Effect<out P> {
  data class Run<P>(val payload: P, val id: EffectId? = null) : Effect<P>
  data class Cancel(val id: EffectId) : Effect<Nothing>
}
```

Semantics (identical on both platforms):

- `run(payload, id: nil)` — execute via the handler; fire-and-forget w.r.t. cancellation
  (still cancelled by store teardown).
- `run(payload, id: someID)` — **cancel-in-flight**: any running effect with the same id is
  cancelled first, then this one starts. (This is TCA's `.cancellable(id:, cancelInFlight: true)`
  as the *only* mode — one semantic, not two.)
- `cancel(id)` — cancel the running effect with that id; no-op if none.
- Effect IDs are plain strings, namespaced by convention: `"<feature>.<purpose>"`
  (e.g. `"counter.ticker"`). Uniqueness scope is the single store instance.
- `Effect` is `Codable`/`@Serializable` when `Payload` is — fixtures assert emitted effects
  (shape in `serialization.md` §4).

## 3. `Store` **[S0]**

```swift
@MainActor final class Store<State: Equatable, Action, Payload: Equatable>: ObservableObject {
  @Published private(set) var state: State
  init(initialState: State,
       reducer: @escaping (inout State, Action) -> [Effect<Payload>],
       handler: @escaping (Payload) -> AsyncStream<Action>)
  func send(_ action: Action)
  func teardown()   // cancels ALL in-flight effects — the cancelOnDeactivate successor
}
```
```kotlin
class Store<S, A, P>(
  initialState: S,
  private val reducer: (S, A) -> Reduced<S, P>,
  private val handler: (P) -> Flow<A>,
  private val scope: CoroutineScope,          // host-owned; cancelling it == teardown()
) {
  val state: StateFlow<S>
  fun send(action: A)
}
```

Rules:

1. **`send` is main-thread-only** (Swift: `@MainActor`; Kotlin: store dispatches onto
   `scope`'s dispatcher, which hosts must give `Dispatchers.Main.immediate`; tests give a
   `TestDispatcher`).
2. `send` runs the reducer **synchronously**; the new state is observable before `send`
   returns. Effects returned by the reducer start *after* the state is published, in
   declaration order.
3. Actions yielded by effect handlers are fed back through `send` on the main dispatcher —
   effects never touch `State` directly.
4. Reentrancy: an action sent while a `send` is executing (possible via synchronous handler
   emission) is queued and processed after the current reduce completes. No recursive reduce.
5. **Teardown cancels every in-flight effect** (Swift `teardown()` + best-effort in `deinit`;
   Kotlin: host cancels the `CoroutineScope`). Hosts MUST call it when the screen/scope dies —
   this is the lifecycle guarantee `cancelOnDeactivate(interactor:)` used to give.
6. Effect handlers must be **cooperatively cancellable**: check `Task.isCancelled` /rely on
   coroutine cancellation at every suspension. The kernel guarantees delivery stops after
   cancel; it cannot stop a handler that never suspends.

## 4. Subtree composition **[S4 — RESOLVED: shells + conventions, zero kernel operators]**

An earlier draft of this section specified TCA-style `scope`/`ifLet`/stack operators. The
composition study resolved it differently: **composition lives in per-platform host
shells and cross-platform conventions; the kernel gains nothing.** Stores never touch
each other — every cross-store edge passes through a shell or an effect.

Conventions (all fixture-enforced):

1. **Routes as state.** An interior node's `State` owns its local navigation sliver
   (`path: [Route]`, `sheet: Sheet?`); route types are Codable/@Serializable and double
   as the process-death projection (the app-level `RouteSpine`, golden-pinned by
   `route-spine.golden.json`).
2. **Route values are child seeds.** Building a child store derives its initial state
   from the route's params (`startEditing`/`startSharing`-style flags); a child's
   reducer turns seeds into its own routes. Deep links FOLD down the tree this way —
   no post-attach commands, no imperative unwind.
3. **Delegate outputs as data.** A child declares its `Delegate` enum beside its
   `Action`; each parent embeds it as ONE action case (`.detail(…)`, `.sharePicker(…)`).
   Parent logic imports child logic (arrow parent→child, acyclic).
4. **Shell duties** (the Router analog, per platform, per interior node): observe the
   node's route state → build child stores+views on route appearance (env derived from
   the parent's; plugin children behind a contract-module builder) → forward child
   delegate outputs into the parent store → teardown on route disappearance (§3 rule 5).
   A shell that makes a decision is a review defect. iOS: `ChildStores`/`ChildSlot`
   reconcilers (`DuetShells`); Android: `remember(route)` + `DisposableEffect`.
5. **Downward commands are effects.** Parent-to-child coordination (deep-link forward,
   reveal choreography) leaves the parent as an effect payload the composition root
   bridges to `childStore.send(…)` — the mirror of delegates flowing up.
6. **Seam fixtures.** Chain fixtures (`chain-*.fixture.json`, ChainRunner both
   platforms) pin the shell-forwarding invariant as data: a step's final
   `notifyListener` payload must byte-equal the next step's embedded action value
   (`linkToNext`). Leaf fixtures keep owning state evolution.

## 5. `TestStore` — the exhaustive test contract **[S0]**

Test-support targets only (`DuetTesting` / `:kernel-test`). Exhaustive in
the TCA sense:

```
testStore.send(action) { state in state.count = 1 }   // assert EVERY state change
testStore.expectEffects([.run(.startTicker, id: "counter.ticker")])
await clock.advance(by: .seconds(1))
await testStore.receive(.tick) { state in state.count = 2 }
testStore.finish()
```

Failure rules (each is a test failure, not a silent pass):

| # | Rule |
| --- | --- |
| E1 | `send`/`receive` state assertion mismatch — the closure must produce *exactly* the post-reduce state (whole-value equality, not per-field). |
| E2 | An effect emitted by the reducer that the test never asserted via `expectEffects` → fails at `finish()`. |
| E3 | An action delivered by an effect handler that the test never `receive`d → fails at `finish()`. |
| E4 | `receive` called when no action arrives (within virtual-time/timeout) → fails. |
| E5 | In-flight (non-cancelled, non-completed) effects at `finish()` → fails. Long-lived effects must be explicitly cancelled by the test (mirrors teardown). |

Determinism: `TestStore` runs handlers against the test `Environment` (fake clock, fixed
UUIDs). Swift uses `KernelClock` (kernel-owned protocol: `sleep(nanoseconds:)`) with
`TestClock.advance(by:)`; Kotlin uses `kotlinx.coroutines.test.runTest` virtual time +
`TestDispatcher`. **A wall-clock sleep in a reducer or effect test is a contract violation** — tests must
pass with virtual time only — this is what keeps the parity lane in the seconds range.

## 6. Golden fixture runner **[S0]**

Separate from `TestStore` on purpose:

- **FixtureRunner** replays `parity/fixtures/*.fixture.json` against the **pure reducer
  only** — no runtime, no handlers, no clocks. It compares canonical JSON of
  (state after each step, effects emitted by each step) against the fixture's expectations.
  Schema + comparison rule: `serialization.md` §5.
- `TestStore` covers what fixtures can't: effect *execution*, cancellation, virtual time.

Both platforms resolve the fixtures directory by walking up from the test's working
directory / source location to the repo root (`parity/fixtures`). The files are read from
the **same path by both platforms** — fixture drift is structurally impossible.

## 7. Naming lockstep

| Swift | Kotlin | Note |
| --- | --- | --- |
| `Store` / `send` / `state` | `Store` / `send` / `state` | |
| `Effect.run` / `.cancel` | `Effect.Run` / `Effect.Cancel` | serialized names are `"run"`/`"cancel"` |
| `TestStore.send/receive/expectEffects/finish` | same | |
| `AsyncStream<Action>` | `Flow<A>` | |
| `Task` cancellation | coroutine cancellation | |
| `@MainActor` | `Dispatchers.Main.immediate` | |
| `KernelClock` / `TestClock` | `TestDispatcher` virtual time | different mechanism, same contract (§5) |

Action case names, state property names, and effect-payload case names must match 1:1 across
platforms (camelCase; Kotlin sealed subclasses are PascalCase types carrying a camelCase
`@SerialName`). Enforced by the lockstep lint (toolchain).

## 8. Open items (tracked, not blocking)

- Hand-written `Codable`/custom serializers for the `{"case": …, "value": …}` shape are
  themselves parity surface. Direction fixed: derived/generated coders (the Kotlin flavor
  derives them from a canonical serializer; the Swift flavor generates them, gated by the
  `CanonicalSumCodable` marker protocol in the kernel). The generator verb ships with the
  toolchain.
- Double/float fields in fixture-visible state are **forbidden in v0** (`serialization.md`
  §2) until a decimal rule is chosen.
- ~~Scoping operators (§4) get contract text + tests when composition lands.~~ RESOLVED:
  §4 is now the subtree-composition convention set (no operators); tested by the chain
  fixtures, the spine golden, and the churn suites.
