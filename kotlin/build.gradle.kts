// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

// Root of the KMP flavor. Plugin versions are hoisted here (`apply false`) so the
// single Kotlin/Native-bearing module (:kernel) and the JVM modules share one
// plugin classpath — the K5a lesson from the FC2 spike (two sibling KMP modules
// collide on the shared KotlinNativeBundleBuildService; hoisting is the fix).
plugins {
  alias(libs.plugins.kotlin.multiplatform) apply false
  alias(libs.plugins.kotlin.jvm) apply false
  alias(libs.plugins.kotlin.serialization) apply false
  alias(libs.plugins.skie) apply false
}

allprojects {
  group = "dev.modaal.duet"
  // -SNAPSHOT so mavenLocal consumers (the playground, pre-publication) always
  // re-resolve after `publishToMavenLocal`. The real (non-snapshot) Maven
  // publication — and the dev.modaal.duet namespace verification — stay
  // decision-gated with the public flip (doc 18 F0).
  version = "0.1.0-SNAPSHOT"
}
