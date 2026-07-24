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

subprojects {
  // The framework's own-corpus regen (kernel-test's lamp scenarios): -PregenFixtures=1
  // must reach every test JVM. A gradle PROPERTY mapped to a system property is the
  // only channel that survives the daemon boundary (exported env vars are read from
  // the daemon's environment, not the invoking shell's). Same mapping as an adopter
  // repo's — the CI template ships it.
  val regenFixtures = providers.gradleProperty("regenFixtures")
  tasks.withType<Test>().configureEach {
    systemProperty("duet.regenFixtures", regenFixtures.getOrElse(""))
  }
}
