# Workers

The worker is Duet's home for **lifecycle-bound stateful processing**: the
environment-side objects that own long-lived subscriptions, caches, timers, or
device bridges — the layer between the platform's services and a feature's pure
reducer. This page names the pattern and its rules; the API lives in
`DuetShells/Working.swift` ↔ `shells-compose`'s `Working.kt` and the harness in
`DuetTesting`/`kernel-test`'s `WorkerTester`.

## The contract

**Workers process, reducers decide.** A worker may fetch, listen, aggregate,
retry, and cache — but every result enters feature state ONLY through the
existing seams: environment streams consumed by effect handlers, or actions
sent through a shell-bound `Relay`. Workers never touch stores or feature
state directly ("no silent ingress"), and a worker that grows decision logic
is asking to have that logic moved into a reducer.

```
platform service ──▶ worker ──▶ environment stream ──▶ effect handler ──▶ action
                        └─────▶ Relay.send(action)  (shell-bound ingress)
```

## One bracket, one life

```swift
public protocol Working: AnyObject, Sendable {
  func run() async     // the worker's whole life
}
```

```kotlin
fun interface Working {
  suspend fun run()    // the worker's whole life
}
```

A host adopts a worker at mount (`StoreHost.adopt(worker)`); `run()` is started
in a structured task, and **cancellation of that task IS stop** — there is no
separate `stop()` to forget. A remount adopts a fresh instance. "Pause when
backgrounded" is consumed as an input stream (scene phase is data), never a
lifecycle callback. Subscription-shaped workers (callback registries, Combine
pipelines) set up in `run()` and then `await untilCancelled()` — teardown stays
structured without a `stop()` hook.

Isolation replaces hand-rolled locks: stateful workers are Swift `actor`s (or
`@MainActor` classes when main-bound); on Kotlin they confine state to the
host's scope. Spawning unstructured tasks inside a worker is the same review
defect it would be in feature code.

**Mount-bracket is the default.** Conditional or per-entity processing is
normally an effect-level concern (cancel-in-flight by effect id), not a worker
set. On Android, workers live in the retained/logical component scope — the
tree that survives configuration changes — so "one bracket per mount" means
logical mount on both platforms.

The host keeps a ledger: `StoreHost.liveWorkerCount` must be zero after
teardown. Shell churn tests extend their teardown assertions to it.

## Ingress shapes

The recurring seams a worker emits, named so specs and reviews can point at
them:

- **Tick-stream with failure seam** — a periodic pipeline whose errors surface
  as values on the stream, never as silent stalls.
- **Fire-and-forget bridge, results via streams** — imperative platform calls
  (upload, sync) whose completions re-enter as stream events, not callbacks.
- **Keyed per-entity clock** — a timer family keyed by entity id (dwell,
  error-retry), cancelled per key.
- **Sticky flag vs event tick** — state that must be re-observable on
  subscription (a flag) vs a one-shot occurrence (a tick); pick deliberately,
  the difference is visible in replay.

A feature spec's effect inventory records which worker backs each seam.

## Testing: logical tests only

Workers carry **behavioral tests through `WorkerTester`, never fixtures** —
parity is never gated at the worker. A worker that exists on both platforms is
two native implementations (Combine/AsyncStream vs Flow/coroutines) sharing
extracted **pure transforms** — and the transforms, being pure functions, are
where cross-platform testing concentrates.

```
let tester = WorkerTester(worker)   // built with fakes + a virtual clock
tester.start()                      // the adopt bracket, test-side
… drive fakes, assert emitted values / recorded calls …
await tester.finish()               // cancels, settles, and FAILS on a leak
```

The harness's guarantee: **a worker whose `run()` has not returned after
cancellation fails the test at `finish()`** — the leak class that
stop-by-convention cannot catch. Synchronous spec DSLs use `cancel()` +
eventually-`isFinished`; async tests use `finish()`, which is wall-clock-free
(settling is a bounded yield loop, not a timeout).
