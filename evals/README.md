# Eval cases for the agent skill

Nine prompts an agent meets in a Duet tree, each with one correct course of action. Every case runs
twice, once with the `duet-ios-android` plugin loaded and once without it, and the two answers are
compared. That comparison is the measure of whether `skills/duet/` changes what an agent does. A
case whose with-plugin answer is wrong is a defect in the skill's text: edit the skill, then run
that case again in a fresh session.

| case | the prompt asks | correct |
| --- | --- | --- |
| `add-a-feature-kmp` | add a settings feature with one toggle to a Kotlin Multiplatform tree | manifest row and feature spec; a pure reducer in `commonMain` and an effect handler that performs the save; a scenario; `tools/duet record --feature settings`; the fixture diff reviewed; both shells; `verify`; `record --check` |
| `start-a-new-duet-app` | start a Duet app in an empty directory | `tutorial1-start` or `tutorial1-swift-start` from duet-tutorials, or the series by hand; no `duet` verb creates a project |
| `record-check-fails-in-ci` | `duet record --check: FAIL — behavioral drift` after a reducer change | `tools/duet record --feature settings`, review and commit the fixtures with the change; never hand-edit one |
| `verify-stops-at-meta-checks` | `verify` ran no lane after `fixture on disk but not in manifest` | the meta-checks stop the lanes; list the fixture in the row or delete the file; `tools/duet lint`, then `verify` |
| `kotlin-exception-crashes-ios` | the iOS app terminates when a Kotlin boundary call throws | `@Throws` on the Kotlin function, the framework assembled again, Swift `try` in `do`/`catch` |
| `two-duet-versions` | SwiftPM cannot resolve after duet-services was moved alone | move `duet` to the version duet-services pins, `exact:`, with the Gradle catalog; `family-pins.sh check` |
| `worker-unchecked-sendable` | `duet doctor`'s `[workers]` finding on a locked class | remove `@unchecked Sendable`; an `actor`, a `@MainActor` class or `Sendable` state |
| `adopt-analytics` | analytics through a vendor SDK, with an opt-out | `Track` effects asserted in scenarios; the SDK in one `AnalyticsTrackingWorking` sink behind `AnalyticsTrackingWorker`, adopted at the composition root; consent through `setEnabled` |
| `swift-flavor-feature` | a feature in an Apple-only tree on the Swift flavor | a Swift package on `Duet`; a `DuetTesting` scenario; `tools/duet record --feature onboarding`; no Kotlin |

`start-a-new-duet-app` checks the forbidden verbs (`duet init`, `duet new`, `duet scaffold`) in its
`criteria` grader and not with a `not_contains` regex: a regex reds an answer that states the verb
does not exist.

## Running them

From the repository root, which is the plugin root:

```bash
claude plugin eval ./ --ablation with-without --runs 1 --no-publish
```

`evals/` is the runner's default directory. Results land in `evals/results/`, which is not
committed. `--no-publish` keeps the HTML report local; without it the runner publishes the report
to claude.ai when the account supports it. A run outside a terminal also needs `--trust-plugin`.
`--case <glob>` selects one case; given twice, the last one wins.

Each prompt describes the tree in its text and says the files are not available, so an arm answers
from the prompt and, in the with-arm, from the skill.

## The round of 2026-11-07

Claude Code 2.1.285, `claude plugin eval` with `--model sonnet --runs 1`, the default judge (`haiku`,
three votes). Three runs: all nine cases ($1.0993), then `adopt-analytics` ($0.1542) and
`add-a-feature-kmp` ($0.1146) again after the changes below; $1.3681 in total. `skill-fired` reports
whether the skill was invoked and is not part of the score.

| case | without | with | with, rerun |
| --- | --- | --- | --- |
| `add-a-feature-kmp` | 0.00 | 0.67, `criteria` ✘ | 1.00 |
| `start-a-new-duet-app` | 0.50 | 1.00 | |
| `record-check-fails-in-ci` | 0.50 | 1.00 | |
| `verify-stops-at-meta-checks` | 0.00 | 1.00 | |
| `kotlin-exception-crashes-ios` | 1.00 | 1.00 | |
| `two-duet-versions` | 0.00 | 1.00 | |
| `worker-unchecked-sendable` | 1.00 | 1.00 | |
| `adopt-analytics` | 0.33 | 0.67, `criteria` ✘ | 1.00 |
| `swift-flavor-feature` | 0.00 | 1.00 | |

The skill fired in every with-arm. Without it, `kotlin-exception-crashes-ios` and
`worker-unchecked-sendable` pass too: `@Throws` is general Kotlin/Native knowledge, and the
`[workers]` finding states its own fix.

**What the round changed.**

- `add-a-feature-kmp`: the with-arm assigned saving the toggle to "a worker for persistence". The
  skill said the Runtime performs effects and did not say what is not a worker's job. `SKILL.md`
  now says the feature's effect handler performs each effect through the environment and that a
  worker is for lifecycle-bound work no single effect requests; the case's `criteria` checks it.
  The rerun's with-arm put the save in the effect handler.
- `adopt-analytics`: the judge failed the with-arm with no stated reason. The same grader text,
  given to the same model with a request for a verdict per criterion, passed every criterion; the
  answer kept the analytics toggle's value in a settings feature's state. The `criteria` grader now
  states that a settings feature holding the toggle's value, and forwarding a change to
  `setEnabled` through an effect, does not fail it. The rerun passed.
