// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

// Extracted from the reference adopter’s navigation shells: breaks the
// child-environment ↔ parent-store construction cycle without IUO closures. The
// composition root creates the relay, hands `send` to the child environment it is
// building, and assigns `sink` once the parent store exists.
//
// `Relay` is the late-binding cell of the `AnyActionHandler` idiom: hand a
// handler forward where the receiver exists at hand-off, and create a relay
// where construction order prevents that. `bindSink` builds an
// `AnyActionHandler`, so the weak-owner capture is written once in this module.

/// A settable event funnel: `send` forwards to whatever `sink` holds at that moment.
/// Events before wiring are dropped by design — composition-root construction is
/// synchronous, so nothing real can fire in the gap.
public final class Relay<Event> {
  public var sink: ((Event) -> Void)?

  public init() {}

  public func send(_ event: Event) {
    sink?(event)
  }

  /// Sets `sink` to a closure that holds `owner` weakly and passes it back to
  /// `handler`. Events sent after `owner` deallocates are dropped, the same way
  /// events sent before wiring are.
  ///
  /// This is the sink form for the case where the capture IS an owner object —
  /// the store, shell, or worker whose mount the wiring belongs to. The weak hold
  /// keeps the mount free of an ARC cycle: the owner holds the relay it wired, and
  /// the relay does not hold the owner back. (The Kotlin twin's weak hold buys a
  /// different thing — there it keeps a torn-down shell collectible rather than
  /// reachable from a live relay.)
  ///
  /// ```swift
  /// routeRelay.bindSink(self) { root, route in root.store.send(.routed(route)) }
  /// ```
  ///
  /// Assign `sink` directly when the capture is not an owner object — a closure
  /// over values, or a strong capture the wiring deliberately wants.
  public func bindSink<Owner: AnyObject>(
    _ owner: Owner,
    _ handler: @escaping (Owner, Event) -> Void
  ) {
    let forwarder = AnyActionHandler<Event>(owner, closure: handler)
    sink = { event in forwarder.invoke(event) }
  }
}
