---
description: The iOS app terminates when a Kotlin boundary call fails.
tags: [diagnosis, kotlin-on-apple]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 8
expected_outcome: |
  Kotlin/Native terminates the process when an exception reaches Swift through a function without
  @Throws. Annotate the boundary function @Throws(SerializationException::class) (or a superclass),
  assemble the framework again, and call it from Swift with try inside do/catch.
---

Our Duet app is on the Kotlin Multiplatform flavor; the iPhone app links the Kotlin core as an
XCFramework. This boundary function is exported:

```kotlin
object SettingsBoundary {
  fun restore(json: String): SettingsState = CanonicalSerializers.json.decodeFromString(json)
}
```

When the saved JSON is malformed, the iOS app terminates instead of letting Swift handle it:

```
Uncaught Kotlin exception: kotlinx.serialization.SerializationException: Unexpected JSON token at offset 0
```

Swift calls `SettingsBoundary.shared.restore(json: saved)`. How do I let Swift catch this error? The repository's files are not available in this session; answer from what is described here.
