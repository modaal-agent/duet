// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import SwiftUI

// W1 — Layer 3 of the presentation contract (parity/presentation-contract.md §5): the
// per-HOST kind→renderer registry. A feature ships its kind (an enum case, Layer 1);
// the platform's composition root binds how that kind renders — manner (detents,
// chrome, wrapping controllers) lives entirely inside the renderer closure, so
// reducers and fixtures never see it. One registry per interior host node; a node
// whose slot has a single kind may render directly (a one-entry registry is ceremony,
// not a seam) — the registry earns its keep where kinds accumulate.

/// Kind-indexed renderer table. Registration is composition-root work; resolution is
/// host-view work. Renderers may return nil (child not built yet — hosts fall back to
/// a placeholder and the reconciler catches up).
@MainActor
public final class PresentationRegistry {
  private var renderers: [ObjectIdentifier: (AnyHashable) -> AnyView?] = [:]

  public init() {}

  /// Bind the renderer for a kind type. Re-registering replaces (last write wins —
  /// composition roots register once at construction).
  public func register<Kind: Hashable>(
    _ kind: Kind.Type, renderer: @escaping (Kind) -> AnyView?
  ) {
    renderers[ObjectIdentifier(kind)] = { anyKind in
      guard let kind = anyKind.base as? Kind else { return nil }
      return renderer(kind)
    }
  }

  /// Resolve the platform surface for a kind value; nil when the kind type has no
  /// renderer or the renderer declined (child not reconciled yet).
  public func view<Kind: Hashable>(for kind: Kind) -> AnyView? {
    renderers[ObjectIdentifier(Kind.self)]?(AnyHashable(kind))
  }
}
