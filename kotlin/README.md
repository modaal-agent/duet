# The KMP flavor

The Kotlin Multiplatform realization of the Duet core (the Swift flavor lives
in `../swift`; the contracts in `../contracts` bind both). Three Maven
artifacts, group `dev.modaal.duet`:

| Artifact | What it is |
| --- | --- |
| `kernel` | The core: `Store` runtime, `Effect` as data, the `KernelClock` seam, canonical serialization (writer + `CanonicalSumSerializer` + the pinned configuration), and the boundary adapters (`dev.modaal.duet.replay` — the protocol registry/server + `SpineBoundary`). KMP: JVM + Apple slices (the `DuetKernel` XCFramework, SKIE route). |
| `kernel-test` | The host-lane test support (JVM): the scenario DSLs (feature + chain dialects) + record/verify runners (the corpus's sole writer), fixture replay + first-divergence reporting, `ChainRunner`, the exhaustive `TestStore`, `WorkerTester`, the deterministic-async toolkit, and the kernel-trace apparatus. |
| `shells-compose` | The shell half's twins: `StoreHost` + `Working`/`adopt`, `ChildStores`/`ChildSlot`, `ProjectionJoin`/`StateTransitions`, `Relay`, `PresentationRegistry`, and the handle vocabulary. Headless (coroutines/Flow only — no Compose dependency); hosts live in the retained/logical scope. |

## Consuming

Releases are published to the family's static Maven repository. One
repository block (`settings.gradle.kts`), then pin an exact version — pre-1.0
minors are breaking by family convention:

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

The `content` filter keeps Gradle from probing the host for anything outside
`dev.modaal.*`. No authentication.

To iterate against a local framework checkout instead, `./gradlew
publishToMavenLocal` here publishes the `-SNAPSHOT` dev default; a consumer
adds `mavenLocal()` ahead of the block above (the adopter repos gate that
behind a `duetMavenLocal=1` Gradle property so default resolution stays on
released artifacts).

## Lanes

```sh
./gradlew test                    # all module suites + this flavor's corpus (parity/fixtures)
./gradlew publishToMavenLocal     # dev.modaal.duet:* snapshots for local iteration
REGEN_FIXTURES=1 ./gradlew test   # re-record the kotlin corpus (the fixture diff is the review artifact)
./scripts/xcframework-receipt.sh  # the SKIE/XCFramework packaging receipt (on demand)
./scripts/publish-maven.sh <ver> <host-checkout>  # release publish rehearsal (CI runs this on a tag push)
```

The kernel-trace fixtures and the formatter golden are SHARED with the Swift
flavor (`../swift/Tests/parity/fixtures/`) — the Swift side records, this side
replays byte-identically (the cross-flavor kernel gate behind the frozen kernel contract v1).
An app consumes the replay protocol (contracts/replay-protocol-v1.md) with a
three-line runner `main` over its `ReplayRegistry`.
