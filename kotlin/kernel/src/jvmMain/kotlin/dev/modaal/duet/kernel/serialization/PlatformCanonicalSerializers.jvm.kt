// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import kotlinx.serialization.modules.SerializersModuleBuilder
import kotlinx.serialization.modules.contextual

/**
 * JVM `actual`: the java-backed canonical serializers — `java.time.Instant`
 * (millisecond ISO-8601 UTC) and `java.util.UUID` (lowercase 8-4-4-4-12), the
 * types JVM-authored feature code annotates `@Contextual`. This is the host
 * lane that runs the byte gate.
 */
actual fun SerializersModuleBuilder.registerPlatformContextualSerializers() {
  contextual(InstantMillisSerializer)
  contextual(UuidSerializer)
}
