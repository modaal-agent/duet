// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetShells
import SwiftUI
import XCTest

// Receipts for the Layer-3 registry seam (contracts/presentation-contract.md §5):
// kinds resolve through their registered renderer, unregistered kind types resolve
// nil (host falls back), and a renderer may decline per-value (child not
// reconciled yet).

@MainActor
final class PresentationRegistryTests: XCTestCase {

  private enum PushKind: Hashable {
    case detail(id: Int)
  }

  private enum SheetKind: Hashable {
    case picker
    case invite
  }

  func testResolvesRegisteredKindAndPassesThePayloadValue() {
    let registry = PresentationRegistry()
    var seen: [PushKind] = []
    registry.register(PushKind.self) { kind in
      seen.append(kind)
      return AnyView(EmptyView())
    }

    XCTAssertNotNil(registry.view(for: PushKind.detail(id: 7)))
    XCTAssertEqual(seen, [.detail(id: 7)])
  }

  func testUnregisteredKindTypeResolvesNil() {
    let registry = PresentationRegistry()
    registry.register(PushKind.self) { _ in AnyView(EmptyView()) }

    XCTAssertNil(registry.view(for: SheetKind.picker))
  }

  func testRendererMayDeclinePerValue() {
    let registry = PresentationRegistry()
    registry.register(SheetKind.self) { kind in
      kind == .picker ? AnyView(EmptyView()) : nil
    }

    XCTAssertNotNil(registry.view(for: SheetKind.picker))
    XCTAssertNil(registry.view(for: SheetKind.invite))
  }

  func testReRegisteringReplacesTheRenderer() {
    let registry = PresentationRegistry()
    registry.register(SheetKind.self) { _ in nil }
    registry.register(SheetKind.self) { _ in AnyView(EmptyView()) }

    XCTAssertNotNil(registry.view(for: SheetKind.invite))
  }
}
