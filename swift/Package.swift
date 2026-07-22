// swift-tools-version:6.0

// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import PackageDescription

// The Swift flavor of the Duet core (see README §"The core and its two flavors").
// Framework targets are born strict: Swift 6 language mode — strict concurrency
// complete — from the first extraction, per the framework's concurrency commitment.
//
// Target map:
//   Duet        — the kernel: Store runtime, Effect currency, the clock seam, and
//                 the CanonicalSumCodable marker protocol.
//   DuetShells  — app-agnostic composition glue: StoreHost, the child reconcilers,
//                 ProjectionJoin/StateTransitions, Relay, PresentationRegistry, the
//                 Combine→AsyncStream bridge, and the generic spine codec.
//   DuetReplay  — the replay-protocol half: the compact canonical writer/decoder,
//                 the per-feature replay entry, and the stdio protocol server. NO
//                 XCTest link — a plain executable must be able to host it (the CLI
//                 drives it; nothing shipping links it either, executables only).
//   DuetTesting — in-process test support: the scenario DSL (feature + chain
//                 dialects), record/verify runners, fixture replay, divergence
//                 reporting, TestClock, and the exhaustive TestStore. Links XCTest —
//                 depend on it from test targets only.
let package = Package(
  name: "Duet",
  platforms: [
    // iOS 16 for NavigationStack-era hosts in DuetShells.
    .iOS(.v16),
    // macOS so consumer test lanes run as plain host `swift test` — no simulator.
    .macOS(.v13),
  ],
  products: [
    .library(name: "Duet", targets: ["Duet"]),
    .library(name: "DuetShells", targets: ["DuetShells"]),
    .library(name: "DuetReplay", targets: ["DuetReplay"]),
    .library(name: "DuetTesting", targets: ["DuetTesting"]),
  ],
  targets: [
    .target(
      name: "Duet"
    ),
    .target(
      name: "DuetShells",
      dependencies: [
        .target(name: "Duet")
      ]
    ),
    .target(
      name: "DuetReplay",
      dependencies: [
        .target(name: "Duet")
      ]
    ),
    .target(
      name: "DuetTesting",
      dependencies: [
        .target(name: "Duet"),
        .target(name: "DuetReplay"),
        // WorkerTester brackets DuetShells' worker seam (`Working`).
        .target(name: "DuetShells"),
      ]
    ),
    .testTarget(
      name: "DuetTests",
      dependencies: [
        .target(name: "Duet"),
        .target(name: "DuetTesting"),
      ]
    ),
    .testTarget(
      name: "DuetShellsTests",
      dependencies: [
        .target(name: "Duet"),
        .target(name: "DuetShells"),
        .target(name: "DuetTesting"),
      ]
    ),
    .testTarget(
      name: "DuetTestingTests",
      dependencies: [
        .target(name: "Duet"),
        .target(name: "DuetTesting"),
      ]
    ),
    .testTarget(
      name: "DuetReplayTests",
      dependencies: [
        .target(name: "Duet"),
        .target(name: "DuetReplay"),
      ]
    ),
  ]
)
