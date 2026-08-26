// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetShells
import XCTest

/// `AnyActionHandler` receipts: the plain closure forwards, the weak-owner form
/// passes the owner back and drops events once it deallocates, the `Void`
/// specialization invokes without an argument, and `mapHandler` transforms on
/// the way in. The control for the weak hold is an owner released in a frame
/// that returns, leaving the handler as the only remaining candidate for a
/// strong reference.
final class AnyActionHandlerTests: XCTestCase {

  private final class Owner {
    var received: [Int] = []
  }

  func testTheClosureInitForwardsTheArgument() {
    var received: [Int] = []
    let handler = AnyActionHandler<Int> { received.append($0) }

    handler.invoke(1)
    handler.invoke(2)

    XCTAssertEqual(received, [1, 2])
  }

  func testTheWeakOwnerInitPassesTheOwnerBackToTheClosure() {
    let owner = Owner()
    let handler = AnyActionHandler(owner) { owner, event in owner.received.append(event) }

    handler.invoke(7)
    handler.invoke(8)

    XCTAssertEqual(owner.received, [7, 8])
  }

  func testTheWeakOwnerInitHoldsTheOwnerWeaklyAndDropsEventsAfterItDeallocates() {
    weak var tracked: Owner?
    var closureCalls = 0
    var handler: AnyActionHandler<Int>?

    // The owner is created and erased in a frame that returns, so the only
    // remaining candidate for a strong reference is the handler itself.
    func make() {
      let owner = Owner()
      tracked = owner
      handler = AnyActionHandler(owner) { owner, event in
        closureCalls += 1
        owner.received.append(event)
      }
      handler?.invoke(1)
    }
    make()

    XCTAssertEqual(closureCalls, 1)
    XCTAssertNil(tracked, "AnyActionHandler kept the owner alive past its own scope")

    handler?.invoke(2)
    XCTAssertEqual(closureCalls, 1)
  }

  func testTheVoidSpecializationInvokesWithoutAnArgument() {
    let owner = Owner()
    let handler = AnyActionHandler<Void>(owner) { owner in owner.received.append(0) }

    handler.invoke()

    XCTAssertEqual(owner.received, [0])
  }

  func testMapHandlerTransformsTheArgumentOnTheWayIn() {
    var received: [Int] = []
    let ints = AnyActionHandler<Int> { received.append($0) }

    let strings: AnyActionHandler<String> = ints.mapHandler { Int($0) ?? -1 }
    strings.invoke("42")
    strings.invoke("not a number")

    XCTAssertEqual(received, [42, -1])
  }

  func testMapHandlerCarriesTheWeakOwnerDrop() {
    weak var tracked: Owner?
    var mapped: AnyActionHandler<String>?

    func make() {
      let owner = Owner()
      tracked = owner
      let ints = AnyActionHandler(owner) { owner, event in owner.received.append(event) }
      mapped = ints.mapHandler { Int($0) ?? -1 }
      mapped?.invoke("3")
      XCTAssertEqual(owner.received, [3])
    }
    make()

    XCTAssertNil(tracked, "mapHandler kept the owner alive past its own scope")
    mapped?.invoke("4")
  }
}
