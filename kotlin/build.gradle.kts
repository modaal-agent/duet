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
  // -SNAPSHOT so mavenLocal consumers (adopters, pre-publication) always
  // re-resolve after `publishToMavenLocal`. The real (non-snapshot) Maven
  // publication — and the dev.modaal.duet namespace verification — stay
  // decision-gated with the public flip (doc 18 F0).
  //
  // The NUMBER tracks the CURRENT release line — it matches the most recent
  // cut and stays there until the next one, which moves it in the commit it
  // tags (CONTRIBUTING, Development rules §7). It stayed at 0.1.0-SNAPSHOT
  // through the 0.1.1 cut, so tags 0.1.0 and 0.1.1 publish the SAME mutable
  // coordinate: a Maven consumer cannot tell them apart, and an adopter pinned
  // to one silently compiles against whatever the last `publishToMavenLocal`
  // left in ~/.m2. That is how an adopter hit `Unresolved reference` on symbols
  // 0.1.1 had graduated.
  //
  // Note what this does and does not fix. `main` now publishes 0.1.1-SNAPSHOT,
  // but building FROM tag 0.1.1 still yields 0.1.0-SNAPSHOT — the tagged commit
  // is unchanged, because re-pointing a pushed tag is worse than the defect.
  // The 0.1.0/0.1.1 pair is permanently indistinguishable; §7 is what keeps it
  // from recurring at 0.1.2.
  version = "0.2.0-SNAPSHOT"
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
