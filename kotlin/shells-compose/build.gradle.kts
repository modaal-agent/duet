// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

// dev.modaal.duet:shells-compose — the shell half's Kotlin twins (C6, the mirror
// rule): StoreHost (+ the worker seam's `Working`/`adopt`), the ChildStores/
// ChildSlot reconcilers, ProjectionJoin, StateTransitions, Relay, the
// PresentationRegistry, and the handle vocabulary. Every named primitive exists
// on both platforms with the same duties; realizations are thin where the
// platform absorbs mechanics (see each type's thinness note).
//
// Deliberately Compose-free: every twin is headless (coroutines/Flow only) — a
// Compose app binds them from its composition roots; composition lifetimes
// already do view-side mount/teardown (S4-Q4). Config-change stance (doc 20
// Q2): hosts live in the RETAINED/logical scope — Essenty's InstanceKeeper is
// the substrate under Decompose's retained tree, adopted as substrate rather
// than as API (test-scope dependency only; the receipt test confirms the
// mechanics).
plugins {
  alias(libs.plugins.kotlin.jvm)
  `maven-publish`
}

kotlin {
  jvmToolchain(21)
}

dependencies {
  api(project(":kernel"))
  api(libs.kotlinx.coroutines.core)

  testImplementation(kotlin("test"))
  testImplementation(libs.kotlinx.coroutines.test)
  testImplementation(libs.essenty.instance.keeper)
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
