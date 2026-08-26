// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// A helper type to avoid capturing `self` strongly when passing events from a SwiftUI view
/// to the hosting view controller.
///
/// Hand an `AnyActionHandler` forward when the receiver exists at hand-off; create a `Relay`
/// when construction order prevents that. The relay is the late-binding cell of this idiom:
/// its `bindSink` builds the same weak-owner handler and stores it until an event arrives.
///
/// Isolation: this type carries no `Sendable` conformance, so the compiler checks that a
/// handler stays in the isolation domain that formed it — which is what keeps
/// `ActionHandler`'s unsynchronized `weakOwner` read race-free. To pass a handler between
/// isolation domains, annotate this type `@MainActor`: a global-actor-isolated type is
/// implicitly `Sendable` and the check survives. `@unchecked Sendable` and a `@Sendable`
/// closure requirement both drop the check instead.
///
/// Kotlin flavor: the same duties are carried by a plain function type, `((A) -> Unit)?`, so
/// this type has no Kotlin twin by design. A Kotlin lambda that captures its receiver keeps
/// that receiver reachable rather than forming a leaked cycle; `Relay.kt`'s `bindSink` doc
/// comment records what a weak hold buys on each flavor.
///
/// Example:
/// ```
/// struct SomeView: View {
///   private var onTapHandler: AnyActionHandler<Void>?
///
///   var body: some View {
///     // ...
///     Button("") {
///       onTapHandler?.invoke(())
///     }
///   }
///
///   func onTap(_ handler: AnyActionHandler<Void>?) -> Self {
///     var copy = self
///     copy.onTapHandler = handler
///     return copy
///   }
/// }
///
/// // ...
///
/// class SomeHostingController: UIHostingController<SomeView> {
///   init() {
///     super.init(rootView: SomeView())
///   }
///
///   override func viewDidLoad() {
///     super.viewDidLoad()
///     self.rootView = SomeView()
///       .onTap(onTapHandler)
///   }
///
///   var onTapHandler: AnyActionHandler<Void> {
///     AnyActionHandler(self) { controller, _ in
///       // `controller` is a strong reference
///       // Do whatever
///     }
///   }
/// }
/// ```
public struct AnyActionHandler<A> {
  public typealias AnyEventHandler = (A) -> ()
  private let handler: AnyEventHandler

  public init<T: AnyObject>(_ weakOwner: T, closure: @escaping ActionHandler<T, A>.EventHandler) {
    self = ActionHandler(weakOwner, closure: closure).eraseToAny()
  }

  public init(_ handler: @escaping AnyEventHandler) {
    self.handler = handler
  }

  public func invoke(_ arg: A) {
    handler(arg)
  }
}

extension AnyActionHandler where A == Void {
  public init<T: AnyObject>(_ weakOwner: T, closure: @escaping (T) -> ()) {
    self.init(weakOwner) { owner, _ in
      closure(owner)
    }
  }

  public func invoke() {
    handler(())
  }
}

public struct ActionHandler<T: AnyObject, A> {
  public typealias EventHandler = (T, A) -> ()

  private weak var weakOwner: T?
  private let closure: EventHandler

  fileprivate init(_ weakOwner: T, closure: @escaping EventHandler) {
    self.weakOwner = weakOwner
    self.closure = closure
  }

  fileprivate func invoke(_ arg: A) {
    guard let strongOwner = weakOwner else {
      return
    }

    closure(strongOwner, arg)
  }

  fileprivate func eraseToAny() -> AnyActionHandler<A> {
    AnyActionHandler { arg in
      invoke(arg)
    }
  }
}

extension AnyActionHandler {
  public func mapHandler<U>(_ transform: @escaping (U) -> A) -> AnyActionHandler<U> {
    AnyActionHandler<U> { u in
      self.invoke(transform(u))
    }
  }
}
