// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

// dev.modaal.duet:shells-compose — the shell half's Kotlin twins (the mirror
// rule): StoreHost (+ the worker seam's `Working`/`adopt`), the ChildStores/
// ChildSlot reconcilers, ProjectionJoin, StateTransitions, Relay, the
// PresentationRegistry, and the handle vocabulary. Every named primitive exists
// on both platforms with the same duties; realizations are thin where the
// platform absorbs mechanics (see each type's thinness note).
//
// Deliberately Compose-free: every twin is headless (coroutines/Flow only) — a
// Compose app binds them from its composition roots; composition lifetimes
// already do view-side mount/teardown. Config-change stance: hosts live in the
// RETAINED/logical scope — Essenty's InstanceKeeper is
// the substrate under Decompose's retained tree. PROMOTED from substrate to
// API on the graduation review (2026-07-30): `RetainedRoot` wraps the
// receipt shape (the teardown ORDER — component before scope — is now a
// framework guarantee), so instance-keeper is an `api` dependency.
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
  // RetainedRoot implements InstanceKeeper.Instance — the supertype is public
  // API, so the dependency is `api`, not `implementation`.
  api(libs.essenty.instance.keeper)

  testImplementation(kotlin("test"))
  testImplementation(libs.kotlinx.coroutines.test)
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
