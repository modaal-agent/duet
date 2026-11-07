---
description: Add a feature to an Apple-only tree on the Swift flavor.
tags: [authoring, swift]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 8
expected_outcome: |
  The feature is a Swift package under src-ios/Subtrees/Onboarding/OnboardingFeature against the Duet
  product (State, Action and EffectPayload, Effect, a pure reducer; CanonicalSumCodable with
  tools/duet canonical-sum); the scenario uses DuetTesting's Scenario DSL with
  ScenarioRunner.verifyOrRecord; tools/duet record --feature onboarding records through Swift (the row
  has no kotlin: path); then tools/duet verify. No Kotlin.
---

Our app is Apple-only (iPhone and Mac Catalyst) on Duet's Swift flavor. Each feature is a Swift
package under `src-ios/Subtrees/<Name>/<Name>Feature/`, and every row in `parity/manifest.yaml` has a
`swift:` path and no `kotlin:` path. I need to add an onboarding feature. Which Duet products do the
feature's logic and its tests use, what goes in the scenario, and how are the fixtures recorded? The repository's files are not available in this session; answer from what is described here.
