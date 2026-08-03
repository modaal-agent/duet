// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import kotlinx.serialization.modules.SerializersModuleBuilder

/**
 * Apple `actual`: empty — deliberately. UUID and Instant support are both
 * common now ([CanonicalUuidSerializer] over `kotlin.uuid.Uuid`,
 * [CanonicalInstantSerializer] over `kotlin.time.Instant`); nothing is
 * platform-only on this side.
 */
actual fun SerializersModuleBuilder.registerPlatformContextualSerializers() {
  // Intentionally empty: UUID and Instant are common.
}
