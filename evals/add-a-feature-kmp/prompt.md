---
description: Add a feature with one toggle to a Duet tree on the Kotlin Multiplatform flavor.
tags: [authoring, kmp]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 8
expected_outcome: |
  A row for settings in parity/manifest.yaml and parity/feature-specs/settings.md naming each fixture;
  State, Action and EffectPayload and a pure reducer in src-kmp/subtrees/settings/logic/src/commonMain
  that takes no environment; a scenario with a branch per path; tools/duet record --feature settings;
  the fixture diff reviewed; the store mounted in the SwiftUI shell and the Compose shell;
  tools/duet verify; tools/duet record --feature settings --check.
---

Our app is a Duet project on the Kotlin Multiplatform flavor. `parity/manifest.yaml` lists two features:

```yaml
features:
  splash:
    kotlin: src-kmp/subtrees/splash/logic/src/commonMain/kotlin/dev/example/splash/SplashFeature.kt
    state: SplashState
    action: SplashAction
    effectPayload: SplashEffectPayload
    scenario: src-kmp/subtrees/splash/logic/src/jvmTest/kotlin/dev/example/splash/SplashScenarioTest.kt
    fixtures:
      - splash.ceremony-completes
  home:
    kotlin: src-kmp/subtrees/home/logic/src/commonMain/kotlin/dev/example/home/HomeFeature.kt
    # …
```

The tree has `tools/duet`, `parity/duet-tools.ref` and `parity/feature-specs/`, an iOS app under
`src-ios/` and a Compose app under `src-kmp/app/`.

I need a settings screen with one toggle, "Notifications enabled", on iOS and Android. List the
files to add or change and the commands to run, in order. The repository's files are not available in this session; answer from what is described here.
