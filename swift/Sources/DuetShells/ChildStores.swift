// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

// S4 shell duty 2+4, factored once: build children on route appearance, tear them down
// on route disappearance. This is the whole "Router" brain — everything else in a shell
// is observation + forwarding one-liners. Unit-tested by the S4-Q6 churn drill.

/// Multi-child reconciler for stack routes. Keyed by the route VALUE: pushing the
/// byte-identical route twice shares one store (one source of truth per identity;
/// SwiftUI's value-keyed `navigationDestination` has the same semantics).
@MainActor
public final class ChildStores<Key: Hashable, Handle> {
  private var handles: [Key: Handle] = [:]
  private let build: (Key) -> Handle?
  private let teardown: (Handle) -> Void

  public init(build: @escaping (Key) -> Handle?, teardown: @escaping (Handle) -> Void) {
    self.build = build
    self.teardown = teardown
  }

  public var activeCount: Int { handles.count }

  /// Lazily builds on first access (navigationDestination pull); `reconcile` is the
  /// authoritative lifecycle driver.
  public func handle(for key: Key) -> Handle? {
    if let existing = handles[key] {
      return existing
    }
    guard let built = build(key) else { return nil }
    handles[key] = built
    return built
  }

  /// Tears down every child whose key left the route set, builds newcomers.
  public func reconcile(keys: Set<Key>) {
    for (key, handle) in handles where !keys.contains(key) {
      handles.removeValue(forKey: key)
      teardown(handle)
    }
    for key in keys where handles[key] == nil {
      handles[key] = build(key)
    }
  }

  public func teardownAll() {
    let all = handles.values
    handles.removeAll()
    for handle in all {
      teardown(handle)
    }
  }
}

/// Single-slot reconciler for modal routes (`sheet`/cover): at most one child, rebuilt
/// when the route value changes, torn down when it clears.
@MainActor
public final class ChildSlot<Key: Hashable, Handle> {
  private var current: (key: Key, handle: Handle)?
  private let build: (Key) -> Handle?
  private let teardown: (Handle) -> Void

  public init(build: @escaping (Key) -> Handle?, teardown: @escaping (Handle) -> Void) {
    self.build = build
    self.teardown = teardown
  }

  public var activeKey: Key? { current?.key }
  public var activeHandle: Handle? { current?.handle }

  public func reconcile(key: Key?) {
    if let current, current.key == key {
      return
    }
    if let current {
      self.current = nil
      teardown(current.handle)
    }
    if let key, let handle = build(key) {
      current = (key, handle)
    }
  }

  public func teardownAll() {
    if let current {
      self.current = nil
      teardown(current.handle)
    }
  }
}
