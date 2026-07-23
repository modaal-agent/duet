// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import kotlinx.serialization.modules.SerializersModuleBuilder

/**
 * Apple `actual`: empty — deliberately. UUID support is common
 * ([CanonicalUuidSerializer], `kotlin.uuid.Uuid`); `Instant`'s canonical
 * serializer is built on `java.time.Instant` (absent on Kotlin/Native) and no
 * boundary-crossing feature carries an Instant yet. See the expect KDoc for
 * what is owed when one does.
 */
actual fun SerializersModuleBuilder.registerPlatformContextualSerializers() {
  // Intentionally empty: UUID is common; Instant is unused on Apple.
}
