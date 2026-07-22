// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Combine

// MT4 fork glue — THE Combine→AsyncStream adapter (doc 08 §3.4: the single audited
// bridge between the app's Combine repository layer and the kernel's AsyncStream
// handler seam). R6's concurrency addendum bans bridging continuations inline in
// feature or app code; environments call `.kernelStream()` instead, and this file is
// the only place the continuation lives.

extension Publisher where Failure == Never, Output: Sendable {
  /// Bridges a Combine publisher into the kernel's effect-stream currency. The
  /// subscription starts when the stream is created and is cancelled when the
  /// consuming effect terminates (`onTermination` → `cancel()`), so effect
  /// cancellation (kernel contract R2) propagates all the way to the upstream
  /// publisher.
  ///
  /// `Output: Sendable` is the seam's contract made explicit: values crossing the
  /// bridge leave the publisher's context for the effect task — actions and
  /// repository rows are value types, so the conformance is a declaration, not work.
  public func kernelStream() -> AsyncStream<Output> {
    AsyncStream { continuation in
      // The box is sound: `AnyCancellable.cancel()` is thread-safe, and the
      // termination closure is the only reader.
      let box = UncheckedSendableBox(self.sink { continuation.yield($0) })
      continuation.onTermination = { _ in box.value.cancel() }
    }
  }
}

extension AsyncStream {
  /// An immediately-finished stream — the return value for downward command bridges
  /// (composition-root handlers that forward parent effects into child stores
  /// synchronously and emit no actions back).
  public static var finished: AsyncStream<Element> {
    AsyncStream { $0.finish() }
  }
}


private struct UncheckedSendableBox<Value>: @unchecked Sendable {
  let value: Value

  init(_ value: Value) {
    self.value = value
  }
}
