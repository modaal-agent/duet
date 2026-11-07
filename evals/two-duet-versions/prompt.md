---
description: SwiftPM cannot resolve after duet-services was moved alone.
tags: [diagnosis, pins]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 8
expected_outcome: |
  duet-services pins duet exact:, so the tree's duet pin must equal the duet version the chosen
  duet-services release pins. Move duet to that version in the same change, exactly, in every Swift
  manifest and in the Gradle catalog's duet entry; check with family-pins.sh check --latest.
---

I moved `duet-services` to a newer release in `src-ios/App/Package.swift` and now package
resolution fails:

```swift
.package(url: "https://github.com/modaal-agent/duet.git", exact: "0.7.0"),
.package(url: "https://github.com/modaal-agent/duet-services.git", exact: "0.13.0"),
```

```
error: Dependencies could not be resolved because root depends on 'duet' 0.7.0 and 'duet-services' 0.13.0 depends on 'duet' 0.8.0.
```

The Kotlin side's `gradle/libs.versions.toml` has `duet = "0.7.0"` and `duetServices = "0.13.0"`.
How do I fix this, and how do I check the pins before pushing? The repository's files are not available in this session; answer from what is described here.
