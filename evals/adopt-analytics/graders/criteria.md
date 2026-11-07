---
type: llm
---
The answer must give all of:

1. Events are emitted by reducers as effects (a `Track` effect payload carrying a
   `TrackedEvent` from duet-services' telemetry grammar), not called from views or reducers
   directly; an event no reducer decides, such as a screen appearing, may be a shell's call.
2. The vendor SDK is imported in one sink that conforms to `AnalyticsTrackingWorking`, and
   `AnalyticsTrackingWorker` fans events out to the sinks; both are adopted at the composition
   root.
3. The user's choice reaches the sinks through `setEnabled`; reducers do not read consent.
4. The tests assert the `Track` effects in scenarios (and chains), and the fixtures are
   re-recorded.

An answer fails this criterion if it calls the vendor SDK from a reducer or from feature
logic in `commonMain`, or has a reducer read a consent flag to decide whether to emit a `Track`
effect. A settings feature that holds the toggle's value in its state and forwards a change to
`setEnabled` through an effect does not fail it.
