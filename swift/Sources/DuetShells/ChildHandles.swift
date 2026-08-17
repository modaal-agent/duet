// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

// The generic handle vocabulary: what `attachChild`/`detachChild` actually did
// for a store-first node rides these value handles instead. UIKit-bound (the view half of a handle is a
// `UIViewController`), so absent from the macOS host test lane — the receipts
// are the consuming app's churn specs, which exercise the handles against real
// mounts.

#if canImport(UIKit)
import Duet
import UIKit

/// The router-less child handle: the builder CONSTRUCTS (store + environment +
/// shell + view in one call), the mount mechanics INSTALL `viewController` and
/// call `activate()` — view-first, the legacy attach order — and the owning
/// composition root HOLDS the handle, calling `teardown()` when route state
/// drops the child. Store lifetime = mount lifetime; the churn specs are the
/// lifecycle receipt.
@MainActor
public struct StoreChild<State: Equatable, Action, EffectPayload: Equatable> {
  public let viewController: UIViewController
  public let store: Store<State, Action, EffectPayload>
  private let shell: any Activatable

  public init(
    viewController: UIViewController,
    store: Store<State, Action, EffectPayload>,
    shell: any Activatable
  ) {
    self.viewController = viewController
    self.store = store
    self.shell = shell
  }

  /// The old `attachChild`'s one real job. Mount mechanics call it after the
  /// view is installed.
  public func activate() {
    shell.activate()
  }

  /// The owning composition root's drop: shell down first (presenter wiring +
  /// projection stop), then the store (in-flight effects cancel) — the order
  /// `detachChild` kept, as one unit.
  public func teardown() {
    shell.deactivate()
    store.teardown()
  }
}

/// The permanent-tab variant: a view shell around a store its OWNER already
/// holds (the composition root's host tears that store down; `StoreChild`
/// would wrongly re-own it). The handle carries view + shell lifecycle only —
/// `activate()` at mount, `deactivate()` when the owner dies.
@MainActor
public struct ViewShellChild {
  public let viewController: UIViewController
  private let shell: any Activatable

  public init(viewController: UIViewController, shell: any Activatable) {
    self.viewController = viewController
    self.shell = shell
  }

  public func activate() {
    shell.activate()
  }

  public func deactivate() {
    shell.deactivate()
  }
}
#endif
