// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import DuetShells
import XCTest

/// Relay receipts: `send` forwards to whatever `sink` holds at send time, and
/// `bindSink`'s owner hold is weak. The control for the weak hold is an owner
/// released mid-mount — the relay drops the event, and the owner deallocates
/// with the relay's sink still installed.
final class RelayTests: XCTestCase {

  private final class Owner {
    var received: [Int] = []
  }

  func testSendForwardsToTheSinkHeldAtSendTime() {
    let relay = Relay<Int>()
    var first: [Int] = []
    var second: [Int] = []

    // Before wiring: dropped by design.
    relay.send(1)

    relay.sink = { first.append($0) }
    relay.send(2)

    relay.sink = { second.append($0) }
    relay.send(3)

    XCTAssertEqual(first, [2])
    XCTAssertEqual(second, [3])
  }

  func testBindSinkPassesTheOwnerBackToTheHandler() {
    let relay = Relay<Int>()
    let owner = Owner()

    relay.bindSink(owner) { owner, event in owner.received.append(event) }
    relay.send(7)
    relay.send(8)

    XCTAssertEqual(owner.received, [7, 8])
  }

  func testBindSinkHoldsTheOwnerWeaklyAndDropsEventsAfterItDeallocates() {
    let relay = Relay<Int>()
    weak var tracked: Owner?
    var handlerCalls = 0

    // The owner is created and wired in a frame that returns, so the only
    // remaining candidate for a strong reference is the relay's own sink.
    func wire() {
      let owner = Owner()
      tracked = owner
      relay.bindSink(owner) { owner, event in
        handlerCalls += 1
        owner.received.append(event)
      }
      relay.send(1)
    }
    wire()

    XCTAssertEqual(handlerCalls, 1)
    XCTAssertNil(tracked, "bindSink kept the owner alive past its own scope")

    relay.send(2)
    XCTAssertEqual(handlerCalls, 1)
  }
}
