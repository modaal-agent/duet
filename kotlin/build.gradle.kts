// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

// Root of the KMP flavor. Plugin versions are hoisted here (`apply false`) so the
// single Kotlin/Native-bearing module (:kernel) and the JVM modules share one
// plugin classpath: two sibling KMP modules collide on the shared
// KotlinNativeBundleBuildService, and hoisting is the fix.
plugins {
  alias(libs.plugins.kotlin.multiplatform) apply false
  alias(libs.plugins.kotlin.jvm) apply false
  alias(libs.plugins.kotlin.serialization) apply false
  alias(libs.plugins.skie) apply false
}

allprojects {
  group = "dev.modaal.duet"
  // Published versions are DERIVED FROM THE TAG: the publish workflow
  // (.github/workflows/publish.yml) passes `-PpublishVersion=<tag>`, so a
  // tagged publish is exact by construction and cannot lag the tag
  // (CONTRIBUTING, Development rules §7 — the 0.1.0/0.1.1 pair records what
  // a hand-moved literal costs).
  //
  // The `-SNAPSHOT` literal is the DEVELOPMENT default only, for
  // `publishToMavenLocal` while iterating: consumers opt into it explicitly
  // (the adopter repos gate mavenLocal behind a `duetMavenLocal=1` property).
  // It tracks the current release line — a cut moves it in the commit that
  // gets tagged, same rule as before, but nothing published depends on it.
  version = providers.gradleProperty("publishVersion").getOrElse("0.5.0-SNAPSHOT")
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

subprojects {
  // The publish workflow stages every publication here first
  // (kotlin/scripts/publish-maven.sh): the staged tree is asserted COMPLETE —
  // all coordinates present for the version — before anything reaches the
  // static Maven host, because `kernel`'s Gradle Module Metadata is what
  // routes consumers to the per-target coordinates and a partial upload is a
  // broken release, not a smaller one.
  plugins.withId("maven-publish") {
    configure<PublishingExtension> {
      repositories {
        maven {
          name = "staging"
          url = uri(rootProject.layout.projectDirectory.dir("build/staging-maven"))
        }
      }
    }
  }
}
