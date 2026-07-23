# Kernel-trace fixtures — v0 (pre-freeze)

**Status: EXECUTED both flavors — the gate is MET and kernel contract v1 is
declared FROZEN (store-kernel-contract.md). Swift recorded the traces at F2;
the Kotlin kernel replayed all six BYTE-IDENTICALLY at F3 under coroutine
virtual time (repeat-stable; negative control trips). The Swift recorder is
the writer of record; the Kotlin side verifies only. One alignment fell out of
the gate, exactly as designed: the KMP kernel's handler invocation moved into
`execute` (synchronous with effect start, matching the Swift flavor) — the
restart interleaving in `cancel-in-flight` is unreachable otherwise.**

The corpus methodology, extended to the kernel itself: the contract-observable
runtime rules of the store kernel (store-kernel-contract.md) are recorded as
replayable canonical traces both kernel flavors must reproduce under virtual
time — machine-verifying what the twin TestStores otherwise pin per platform by
assertion.

## 1. Event vocabulary

A trace is an ordered list of events, one canonical JSON object per line
(jsonl; canonical form per serialization.md — sorted keys, no whitespace).
Feature values (`action`, `state`, `payload`) are embedded as canonical-JSON
strings of the scripted feature's types, so the trace bytes are
dialect-independent.

| Event | Fields | Meaning |
| --- | --- | --- |
| `send` | `action` | the script sent a stimulus (the boundary: everything until the next script event is the kernel's response) |
| `reduce` | `action`, `state` | the reducer ran; `state` is post-reduce (canonical) |
| `effectStart` | `payload`, `id` | the effect's task invoked the handler |
| `effectAction` | `action` | an effect's stream delivered an action into the store |
| `effectCancelled` | `payload` | the effect's stream ended by cancellation |
| `effectFinished` | `payload` | the effect's stream ran to completion |
| `advance` | `nanoseconds` | the script advanced the virtual clock |
| `teardown` | — | the script tore the store down |

## 2. The rules the fixtures pin

Recorded under `swift/Tests/parity/fixtures/kernel-trace/` (regenerate with
`REGEN_FIXTURES=1`; the fixture diff is the review artifact):

1. **send-reduce-sync** — every `send` is followed by its `reduce` before
   anything else lands: reduction is synchronous with `send`, and new state is
   observable when `send` returns.
2. **effect-start-order** — effects emitted by one reduce start in declaration
   order.
3. **effect-roundtrip** — a delivered action is a fresh, flat send→reduce
   cycle through the queue.
4. **cancel-in-flight** — `.cancel(id:)` terminates the running effect (its
   pending clocked yield never fires); a same-id `.run` restart cancels its
   predecessor BEFORE the successor starts.
5. **teardown-cancels** — teardown terminates the live effect; nothing is
   delivered afterwards (post-teardown clock advances are silence).
6. **reentrancy-queue** — multiple actions delivered by one effect reduce as
   flat, ordered cycles — queued, never nested (the trace has no nested
   `reduce` under any circumstance).

## 3. Determinism rules (what the trace does and does not pin)

Two recorder-level rules make traces canonical rather than scheduling-shaped:

- **Delivery order is reduce order (lockstep).** The recorder forwards an
  effect's yields in lockstep with the store's reduces — the trace's
  `effectAction`→`reduce` pairing IS the contract's meaningful ordering. A
  free-running forwarder would pin executor scheduling, not kernel behavior.
- **One ending per settle window.** Cross-effect ORDER of
  `effectCancelled`/`effectFinished` events landing in the same settle window
  is **contract-undefined** (two concurrently-ending tasks race the executor;
  neither kernel defines their order). Rule scenarios are authored so each
  ending lands in its own scripted window (separated by an `advance` or a
  `send`). Multi-effect teardown unwind order stays a per-platform TestStore
  assertion — the spec-18 §2.1 fallback applied at trace-design grain instead
  of surrendering byte-identity wholesale.

## 4. Cross-flavor verification (F3)

The Kotlin kernel replays the same scripted scenarios under coroutine virtual
time and must produce byte-identical traces. If a residual concurrency-idiom
mismatch surfaces that scenario discipline cannot absorb, the recorded fallback
is: this rule-spec stays normative and the affected rule is pinned by
per-platform assertion — i.e. today's state, no regression (spec 18 G3).
