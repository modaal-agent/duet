// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

// The SKIE-route packaging RECEIPT — not a published artifact. Mirrors the
// real KMP-flavor app shape: the app's commonMain features + the kernel
// compile into ONE framework a Swift consumer links. The receipt feature is
// the lamp (the kotlin corpus's scripted feature); the Swift consumer
// (swift-consumer/) replays the committed lamp fixtures through
// BoundaryReplay across the boundary — canonical bytes produced entirely by
// core-owned machinery, byte-compared against the same files the JVM host
// lane records and verifies. macOS-only: the host-gate slice (the FC-spike
// lane); the shipped kernel's iOS slices are covered by the
// :kernel:assembleDuetKernelXCFramework packaging receipt.
plugins {
  alias(libs.plugins.kotlin.multiplatform)
  alias(libs.plugins.kotlin.serialization)
  alias(libs.plugins.skie)
}

kotlin {
  jvmToolchain(25)

  val xcf = XCFramework("DuetReceipt")

  listOf(macosArm64()).forEach { target ->
    target.binaries.framework {
      baseName = "DuetReceipt"
      isStatic = true
      // Surface the kernel's replay types through the receipt framework.
      // Write `dependencies.project(…)`, not `project(…)`: inside
      // `framework { }` no `DependencyHandler` is in scope, so the bare form
      // resolves to `Project.project(String)` and hands `export` a `Project`,
      // which Gradle 10 rejects as a dependency notation.
      export(dependencies.project(":kernel"))
      xcf.add(this)
    }
  }

  sourceSets {
    commonMain.dependencies {
      api(project(":kernel"))
    }
  }
}

skie {
  analytics {
    enabled.set(false)
    disableUpload.set(true)
  }
}
