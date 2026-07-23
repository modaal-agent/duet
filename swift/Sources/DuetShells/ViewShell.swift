// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// The handles' lifecycle surface (spec 15 §3.3): what `StoreChild` /
/// `ViewShellChild` need from the node they carry — the framework's replacement
/// for the erased RIBs `Interactable`. Main-actor native: mount mechanics run
/// on the main actor by construction, so the bracket is isolated rather than
/// "main-thread by contract".
@MainActor
public protocol Activatable: AnyObject {
  func activate()
  func deactivate()
}

/// The node-lifecycle piece — a latch and two hooks, deliberately
/// `StoreHost`-sized (this is not a framework). Replaces the RIBs trio
/// `PresentableInteractor` / `Interactor` / `Presentable`: presenter references
/// become plain properties on the subclass, and the activate/deactivate bracket
/// becomes `bind()`/`unbind()` under an `isActive` latch.
///
/// Decision of record (F2's first, spec 15 §7): a CLASS, not a
/// protocol-with-default-implementation — the latch and the owned `StoreHost`
/// are stored state protocol extensions cannot hold, and a base class keeps the
/// adopter surface to two overrides.
///
/// The owned `host` is the shell's teardown registry: everything `bind()`
/// hosts/adopts dies at `deactivate()` — `unbind()` runs first (for the rare
/// manual cleanup that isn't host-registered), then the host unwinds in
/// reverse registration order. One bracket per mount is the norm (a remount
/// builds a fresh node — the Duet-native semantics, unlike the RIBs re-fired
/// bracket); re-activation is nonetheless legal and re-runs `bind()` against
/// the re-armed host.
@MainActor
open class ViewShell: Activatable {
  public private(set) var isActive = false
  /// The shell's teardown registry — everything `bind()` creates registers here.
  public let host = StoreHost()

  public init() {}

  /// Mount hook: wire presenter actions, adopt projections/workers into `host`.
  open func bind() {}
  /// Unmount hook, called BEFORE the host unwinds.
  open func unbind() {}

  public func activate() {
    guard !isActive else { return }
    isActive = true
    bind()
  }

  public func deactivate() {
    guard isActive else { return }
    isActive = false
    unbind()
    host.teardownAll()
  }
}
