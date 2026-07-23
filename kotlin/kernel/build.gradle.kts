// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import org.gradle.api.tasks.testing.Test
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

// dev.modaal.duet:kernel — the KMP flavor's core: the Store runtime, Effect as
// equatable data, the KernelClock seam, canonical serialization (writer +
// CanonicalSumSerializer + the pinned configuration), and the boundary adapters
// (registry-driven replay + spine persistence as String functions).
//
// Targets: JVM (the host lane — Android consumers resolve this variant) plus the
// Apple slices aggregated into the DuetKernel XCFramework (the SKIE consumption
// route, spec 16 §8: SKIE gives sealed → exhaustive Swift enums and the
// Flow/suspend runtime; Swift Export at Kotlin 2.3.21 traps on non-empty
// `Reduced.effects` and cannot bridge Flow).
plugins {
  alias(libs.plugins.kotlin.multiplatform)
  alias(libs.plugins.kotlin.serialization)
  alias(libs.plugins.skie)
  `maven-publish`
}

kotlin {
  jvmToolchain(21)

  // kotlin.uuid.Uuid is the canonical UUID type in common code (FC2 M6); it is
  // still experimental stdlib API at Kotlin 2.3.21, so opt in module-wide.
  compilerOptions {
    optIn.add("kotlin.uuid.ExperimentalUuidApi")
  }

  val xcf = XCFramework("DuetKernel")

  jvm()

  listOf(
    macosArm64(),
    iosArm64(),
    iosSimulatorArm64(),
  ).forEach { target ->
    target.binaries.framework {
      baseName = "DuetKernel"
      // Static: symbols link straight into the consumer binary, no runtime
      // dylib lookup — the FC2 spike's proven configuration.
      isStatic = true
      xcf.add(this)
    }
  }

  sourceSets {
    commonMain.dependencies {
      api(libs.kotlinx.coroutines.core)
      api(libs.kotlinx.serialization.json)
    }
    jvmTest.dependencies {
      implementation(kotlin("test"))
      implementation(libs.kotlinx.coroutines.test)
    }
  }
}

// Keep the framework build hermetic: no SKIE analytics collection or upload
// (a typed DSL in 0.10.13 — there are no `skie.analytics.*` Gradle properties).
skie {
  analytics {
    enabled.set(false)
    disableUpload.set(true)
  }
}

tasks.withType<Test>().configureEach {
  useJUnitPlatform()
}
