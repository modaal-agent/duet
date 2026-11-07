---
description: Add analytics with a vendor SDK to a Duet app.
tags: [services, telemetry]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 8
expected_outcome: |
  Events are effects: reducers emit Track payloads with a TrackedEvent from the telemetry grammar,
  asserted in scenarios and chains, and the features re-recorded. The vendor SDK is one sink file
  conforming to AnalyticsTrackingWorking; AnalyticsTrackingWorker(sinks:) fans out and is adopted at
  the composition root. Consent goes through setEnabled; reducers never read it.
---

Our Duet app (Kotlin Multiplatform flavor, SwiftUI and Compose shells) needs product analytics
through a vendor SDK on both platforms, and the user must be able to turn analytics off in
settings. Where does the SDK go, how do events reach it, and how do we test that the right events
are sent? The repository's files are not available in this session; answer from what is described here.
