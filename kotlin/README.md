# The KMP flavor

The Kotlin Multiplatform realization of the Duet core (the Swift flavor lives
in `../swift`; the contracts in `../contracts` bind both). Three Maven
artifacts, group `dev.modaal.duet`:

| Artifact | What it is |
| --- | --- |
| `kernel` | The core: `Store` runtime, `Effect` as data, the `KernelClock` seam, canonical serialization (writer + `CanonicalSumSerializer` + the pinned configuration), and the boundary adapters (`dev.modaal.duet.replay` — the protocol registry/server + `SpineBoundary`). KMP: JVM + Apple slices (the `DuetKernel` XCFramework, SKIE route). |
| `kernel-test` | The host-lane test support (JVM): the scenario DSLs (feature + chain dialects) + record/verify runners (the corpus's sole writer), fixture replay + first-divergence reporting, `ChainRunner`, the exhaustive `TestStore`, `WorkerTester`, the deterministic-async toolkit, and the kernel-trace apparatus. |
| `shells-compose` | The shell half's twins: `StoreHost` + `Working`/`adopt`, `ChildStores`/`ChildSlot`, `ProjectionJoin`/`StateTransitions`, `Relay`, `PresentationRegistry`, and the handle vocabulary. Headless (coroutines/Flow only — no Compose dependency); hosts live in the retained/logical scope. |

## Lanes

```sh
./gradlew test                    # all module suites + this flavor's corpus (parity/fixtures)
./gradlew publishToMavenLocal     # dev.modaal.duet:* for local consumers
REGEN_FIXTURES=1 ./gradlew test   # re-record the kotlin corpus (the fixture diff is the review artifact)
./scripts/xcframework-receipt.sh  # the SKIE/XCFramework packaging receipt (on demand)
```

The kernel-trace fixtures and the formatter golden are SHARED with the Swift
flavor (`../swift/Tests/parity/fixtures/`) — the Swift side records, this side
replays byte-identically (the cross-flavor kernel gate behind the frozen kernel contract v1).
An app consumes the replay protocol (contracts/replay-protocol-v1.md) with a
three-line runner `main` over its `ReplayRegistry`.
