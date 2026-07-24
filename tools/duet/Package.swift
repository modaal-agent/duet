// swift-tools-version:6.0

// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import PackageDescription

// The open `duet` CLI (F4 — doc-15 §6.1's tools/ half). Its own package, NOT a
// product of the root manifest: consumers of the library never resolve the
// toolchain, and the toolchain can grow without touching the library's zero-dep
// consumer graph. Zero third-party dependencies on purpose — it orchestrates
// `swift test` / `gradlew` as subprocesses and reads the machine artifacts the
// runners write (parity/.runs/*). The one dependency is the framework's own
// DuetReplay: the compact canonical writer the CLI byte-gates with IS the writer
// the replay servers use (G1 — no CLI/flavor drift by construction).
let package = Package(
  name: "duet-tools",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "duet",
      dependencies: [
        .product(name: "DuetReplay", package: "modaal-agent-duet")
      ],
      path: "Sources/duet"
    )
  ]
)
