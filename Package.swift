// swift-tools-version:6.0

// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import PackageDescription

// The Swift flavor of the Duet core (see README §"The core and its two flavors").
// Framework targets are born strict: Swift 6 language mode — strict concurrency
// complete — from the first extraction, per the framework's concurrency commitment.
//
// The manifest lives at the REPO ROOT (sources stay under swift/) because SwiftPM
// resolves `.package(url:)` dependencies against the repository root only — the
// URL-consumable public shape. One URL-resolvable package per repo: the
// CombineRIBs coexistence helpers live in their own repo (duet-migration), so
// this package's dependency graph stays RIBs-free for every consumer.
//
// Target map:
//   Duet        — the kernel: Store runtime, Effect currency, the clock seam, and
//                 the CanonicalSumCodable marker protocol.
//   DuetShells  — app-agnostic composition glue: StoreHost (incl. the worker
//                 seam's adopt bracket), the child reconcilers, Working,
//                 ProjectionJoin/StateTransitions, Relay, PresentationRegistry,
//                 the Combine→AsyncStream bridge, and the generic spine codec.
//   DuetReplay  — the replay-protocol half: the compact canonical writer/decoder,
//                 the per-feature replay entry, and the stdio protocol server. NO
//                 XCTest link — a plain executable must be able to host it (the CLI
//                 drives it; nothing shipping links it either, executables only).
//   DuetTesting — in-process test support: the scenario DSL (feature + chain
//                 dialects), record/verify runners, fixture replay, divergence
//                 reporting, TestClock, the exhaustive TestStore, and WorkerTester.
//                 Links XCTest — depend on it from test targets only.
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
      name: "Duet",
      path: "swift/Sources/Duet"
    ),
    .target(
      name: "DuetShells",
      dependencies: [
        .target(name: "Duet")
      ],
      path: "swift/Sources/DuetShells"
    ),
    .target(
      name: "DuetReplay",
      dependencies: [
        .target(name: "Duet")
      ],
      path: "swift/Sources/DuetReplay"
    ),
    .target(
      name: "DuetTesting",
      dependencies: [
        .target(name: "Duet"),
        .target(name: "DuetReplay"),
        // WorkerTester brackets DuetShells' worker seam (`Working`).
        .target(name: "DuetShells"),
      ],
      path: "swift/Sources/DuetTesting"
    ),
    .testTarget(
      name: "DuetTests",
      dependencies: [
        .target(name: "Duet"),
        .target(name: "DuetTesting"),
      ],
      path: "swift/Tests/DuetTests"
    ),
    .testTarget(
      name: "DuetShellsTests",
      dependencies: [
        .target(name: "Duet"),
        .target(name: "DuetShells"),
        .target(name: "DuetTesting"),
      ],
      path: "swift/Tests/DuetShellsTests"
    ),
    .testTarget(
      name: "DuetTestingTests",
      dependencies: [
        .target(name: "Duet"),
        .target(name: "DuetTesting"),
      ],
      path: "swift/Tests/DuetTestingTests"
    ),
    .testTarget(
      name: "DuetReplayTests",
      dependencies: [
        .target(name: "Duet"),
        .target(name: "DuetReplay"),
      ],
      path: "swift/Tests/DuetReplayTests"
    ),
  ]
)
