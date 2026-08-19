# Mock dialect (v1 — NORMATIVE)

The cross-platform member vocabulary for **generated test doubles**: what a
mock class exposes for recording, seeding, and failure, identically on both
flavors. One dialect exists so a test author (human or agent) working on both
platforms carries ONE member API and sees identical failure strings — there
is no cross-platform mapping to learn, maintain, or forget.

Two engines emit it; this page is what binds them:

- **Swift** — the `Mocks.swifttemplate` bundle
  ([swift-sourcery-templates](https://github.com/modaal-agent/swift-sourcery-templates)),
  run by `duet mocks` over the manifest's `mocks:` rows; output is committed
  and drift-gated by `--check` (the template engine's first-use compile cost
  is why).
- **Kotlin** — the KSP processor `dev.modaal:mocks-processor`
  ([kotlin-ksp-mocks](https://github.com/modaal-agent/kotlin-ksp-mocks)),
  run by the consumer's own test compilation (`kspTest`/`kspJvmTest` +
  `kspMocksTargets`); output is a build product under `build/generated/ksp/`
  and never committed (generation is sub-second, so there is no drift class
  and no check lane).

Each engine's own test suite pins the vocabulary and the exact strings below.
Changing anything here is a versioned contract event: bump the version, land
both engines in the same change window, and state the migration in both
changelogs.

## 1. Methods

For an interface/protocol method `fn`:

| member | meaning |
| --- | --- |
| `fnCallCount` | calls made; incremented FIRST, before recording and dispatch |
| `fnArgs` | recorded arguments, appended before the handler runs (a throwing handler does not un-make the call) |
| `fnHandler` | nullable closure/lambda — the ONLY seeding mechanism |

Argument recording:

- one recordable parameter → stored directly (`[URL]`, `MutableList<String>`);
- several → a labeled record (Swift: a tuple `[(token:, isSignedIn:)]`;
  Kotlin: a nested `FnArgs` data class — the platform's closest
  labeled-record type);
- function-typed parameters are NEVER recorded (storing a closure keeps the
  caller's captures alive for the mock's lifetime); they still reach the
  handler.

Fallback when `fnHandler` is unset, in order:

1. `Void`/`Unit` return → nothing (the handler, when set, is invoked for its
   side effect);
2. optional/nullable return → `nil`/`null`;
3. a guessable default (`0`, `""`, `false`, empty collection) → returned;
4. a stream return (§3) → the mock's own subject/channel replays;
5. otherwise → fail with **exactly** `fnHandler expected to be set.`
   (Swift: `fatalError`; Kotlin: `error(...)` → `IllegalStateException`).

## 2. Properties

- **Mutable requirement** → stored value; every write counts in
  `propSetCount` (initialization does not count).
- **Read-only stream-typed property** (§3) → computed: `propGetCount` +
  `propGetHandler` + the subject/channel fallback.
- **Read-only with a guessable default** → re-seedable stored `var`.
- **Anything else** → a constructor parameter. A pure-property
  interface/protocol therefore generates a **constructor-seeded bag**: a
  member added to the interface breaks consumers at COMPILE time, not at
  run time.

## 3. Streams

A member producing a stream (Swift: `AnyPublisher`/Rx observable; Kotlin:
`Flow`) is seeded through its handler like any other member, and additionally
carries a mock-owned source the test can drive directly:

- Swift: `fnSubject` (`PassthroughSubject`, or `CurrentValueSubject` where
  the element has a default);
- Kotlin: `fnChannel` (`Channel(UNLIMITED)` + `receiveAsFlow()`).

The test ends the stream by completing the subject / closing the channel —
that is the teardown that satisfies a store kernel's no-effects-in-flight
check (store-kernel-contract.md, E5).

## 4. Determinism

Emitted members are name-sorted regardless of declaration order, and both
engines' output is byte-deterministic for unchanged inputs: rendering reads
no clocks, no unstable-ordered maps, no absolute paths. Overloads
disambiguate their bookkeeping members deterministically — the
fewest-parameter overload keeps the plain name, wider ones qualify with
their parameter names — so adding an overload later never renames existing
members.

## 5. Hand-written doubles follow the dialect

A double that stays hand-written (stateful, domain-seeded — e.g. an
auth-session fake whose value IS its scripted state machine) still names its
recording and seeding members in this vocabulary. The dialect is what a test
reads; whether a generator or a hand wrote the class underneath is not.
