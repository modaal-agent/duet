// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

pluginManagement {
  repositories {
    gradlePluginPortal()
    mavenCentral()
    google()
  }
}

dependencyResolutionManagement {
  repositories {
    mavenCentral()
    google()
  }
}

// The KMP flavor of the Duet core (spec: one repo, two platform halves, one
// contract). Maven coordinates: dev.modaal.duet:kernel / :kernel-test /
// :shells-compose. The Swift flavor lives in ../swift (SPM); the contracts in
// ../contracts bind both.
rootProject.name = "duet"

include(":kernel")
include(":kernel-test")
include(":shells-compose")
// The SKIE packaging receipt (not published; swift-consumer replays through it).
include(":consumer-receipt")
