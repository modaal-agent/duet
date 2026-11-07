---
type: llm
---
The answer must put the feature's State, Action, EffectPayload and a pure reducer in a Swift
package that depends on the `Duet` product, write the scenario with `DuetTesting`'s scenario DSL
(`Scenario`, `Given`, `When`, `Then` or `ThenEffects`, run through `ScenarioRunner`), add an
`onboarding` row with a `swift:` path to `parity/manifest.yaml`, record with
`tools/duet record --feature onboarding` (with or without `--platform swift`), and run
`tools/duet verify`.

An answer fails this criterion if it adds Kotlin or Kotlin Multiplatform to the tree, writes
fixture JSON by hand, or gives the reducer an environment parameter.
