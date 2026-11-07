---
type: llm
---
The answer must give all of:

1. A `settings` row in `parity/manifest.yaml` and a feature spec `parity/feature-specs/settings.md`
   that names the fixtures.
2. State, Action and EffectPayload types and a reducer in the feature's `commonMain` module
   (`src-kmp/subtrees/settings/logic/...`), with the reducer pure: it takes the state and the
   action only, and side effects (persisting the toggle, for example) leave it as effect values,
   which the feature's effect handler performs through its environment.
3. A scenario recorded into fixtures with `tools/duet record --feature settings`, and the
   fixture diff reviewed before committing.
4. The store mounted in a SwiftUI shell on iOS and a Compose shell on Android.
5. `tools/duet verify` and the `record --check` drift gate.

An answer fails this criterion if it proposes a shared Compose Multiplatform UI for iOS, writes
fixture JSON by hand, gives the reducer an environment, clock or storage parameter, assigns the
feature's own effect (saving the toggle) to a worker instead of the effect handler, or tells
the user to run a `duet` verb that does not exist (`duet new`, `duet generate`, `duet scaffold`,
`duet add-feature`).
