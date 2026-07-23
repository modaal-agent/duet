// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

// dev.modaal.duet:kernel-test — the host-lane test support: the scenario DSL
// (feature dialect + branch expansion), the record/verify runners (the corpus's
// SOLE WRITER — fixtures are build products of `record`, both flavors' pretty
// writers byte-identical), fixture replay with first-divergence reporting, run
// reports, the chain replayer, the exhaustive TestStore, the deterministic-async
// toolkit's Kotlin half, and the WorkerTester harness.
//
// JVM-only by design: this artifact is the KMP flavor's HOST LANE (a
// `testImplementation` dependency of feature modules); nothing in it crosses the
// Apple boundary. Swift-flavor mirror: the DuetTesting SPM target.
plugins {
  alias(libs.plugins.kotlin.jvm)
  // For the module's OWN tests (scripted @Serializable features); the artifact
  // itself only consumes serializers its callers pass in.
  alias(libs.plugins.kotlin.serialization)
  `maven-publish`
}

kotlin {
  jvmToolchain(21)
}

dependencies {
  api(project(":kernel"))
  api(project(":shells-compose"))
  api(libs.kotlinx.serialization.json)
  api(libs.kotlinx.coroutines.test)
  // Assertion library in a main sourceSet (Quick/Nimble pattern) — this module is
  // only ever a testImplementation dependency of consumer modules.
  implementation(kotlin("test"))
}

tasks.test {
  useJUnitPlatform()
}

publishing {
  publications {
    create<MavenPublication>("maven") {
      from(components["java"])
    }
  }
}
