---
description: duet doctor reports a worker stamped @unchecked Sendable.
tags: [diagnosis, workers]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 8
expected_outcome: |
  The stamp turns off the isolation checking the worker rule relies on, and doctor has no waiver.
  Remove @unchecked Sendable and the lock; make SessionWorker an actor, or a @MainActor class when it
  is main-bound, or give it only Sendable stored state, so the checked conformance compiles.
---

`tools/duet doctor` fails in CI:

```
✗ [workers] src-ios/Libraries/AppKit/Sources/RootShell/SessionWorker.swift:12: 'SessionWorker' conforms to Working and is declared '@unchecked Sendable' — the stamp silences the isolation checking the worker rule relies on (see docs/workers.md in the duet framework); isolate the worker (@MainActor, or prove Sendable) instead.
duet doctor: 1 finding(s)
```

```swift
final class SessionWorker: Working, @unchecked Sendable {
  private let lock = NSLock()
  private var lastSession: Session?
  private let sessions: AsyncStream<Session>
  private let relay: Relay<RootAction>

  func run() async {
    for await session in sessions {
      lock.lock(); lastSession = session; lock.unlock()
      relay.send(.authChanged(session))
    }
  }
}
```

The worker works and the lock protects the state. Can I keep it and silence the finding? The repository's files are not available in this session; answer from what is described here.
