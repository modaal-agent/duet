// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

// MT4 fork glue (extracted from MainNavShell / PlaygroundComposition): breaks the
// child-environment ↔ parent-store construction cycle without IUO closures. The
// composition root creates the relay, hands `send` to the child environment it is
// building, and assigns `sink` once the parent store exists.

/// A settable event funnel: `send` forwards to whatever `sink` holds at that moment.
/// Events before wiring are dropped by design — composition-root construction is
/// synchronous, so nothing real can fire in the gap.
public final class Relay<Event>: @unchecked Sendable {
  public var sink: ((Event) -> Void)?

  public init() {}

  public func send(_ event: Event) {
    sink?(event)
  }
}
