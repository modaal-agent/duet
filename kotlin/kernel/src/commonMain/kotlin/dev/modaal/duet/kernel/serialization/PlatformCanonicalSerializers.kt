// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import kotlinx.serialization.modules.SerializersModuleBuilder

/**
 * Platform hook for [CanonicalSerializers.module]'s platform-specific contextual
 * registrations — the types whose canonical serializers are built on
 * platform-only APIs:
 *
 *  - JVM `actual`: `java.time.Instant` (millisecond ISO-8601 UTC form) and
 *    `java.util.UUID` (lowercase 8-4-4-4-12) — both carried by JVM-authored
 *    feature code; the java-backed serializers are byte-identical to the
 *    common [CanonicalUuidSerializer] form where the types overlap.
 *  - Apple `actual`: empty. `kotlin.uuid.Uuid` is already common; no
 *    boundary-crossing feature carries an Instant yet. OWED when one does: a
 *    multiplatform canonical Instant (ISO-8601 UTC, exactly three fractional
 *    digits + `Z`), byte-validated by that feature's fixtures — do NOT
 *    approximate blind.
 */
expect fun SerializersModuleBuilder.registerPlatformContextualSerializers()
