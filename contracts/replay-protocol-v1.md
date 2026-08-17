# The replay protocol — v1 (the flavor seam)

**Status: v1 — NORMATIVE. Formalized from the v0 spike shape,
which replayed the full reference corpus — chains included — faster than the
in-process lane. Changes to this contract require a protocol-version bump;
the wire shape below is frozen for v1.**

The versioned contract between any **core flavor** and the **toolchain**. A
flavor implements one small replay adapter (~100 LOC); the CLI owns fixture
reading, step driving, byte comparison, the §6 pretty writer, `--check`, diff,
and reporting — once, flavor-neutrally. Conformance gets its operational
definition here: *speaks the replay protocol, passes the corpus.* Any future
flavor joins by implementing this page.

## 1. Transport

JSON-lines over stdio: the toolchain spawns the app's **replay-runner**
executable, reads one handshake line, then writes one request per line and
reads one response per line. The runner is **stateless per request** — the CLI
threads each step's actual state forward. The runner must not write anything
else to stdout; diagnostics go to stderr.

## 2. Handshake (runner → CLI, on start)

```json
{"protocol":"duet-replay","version":1,"platform":"swift","features":["counter","mainnav"]}
```

- `protocol` — always `"duet-replay"`.
- `version` — the protocol version the runner speaks (this page: `1`).
- `platform` — the flavor: `"swift"` (Swift flavor) or `"kotlin"` (KMP flavor
  host lane). Informational; the CLI records it in reports.
- `features` — the feature names the runner's registry advertises, sorted.

## 3. Requests (CLI → runner) and responses

### 3.1 `reduce` — the ONE semantic op

```json
{"op":"reduce","feature":"counter","state":<tree>,"action":<tree>}
```

`state` and `action` are raw JSON **trees** (the CLI holds the fixture; the
runner never touches disk). The runner decodes both with the flavor's pinned
canonical configuration, runs the feature's **pure reducer**, and responds:

```json
{"state":"<canonical>","effects":"<canonical>"}
```

Both values are **canonical compact strings** (serialization.md §1–§2; effects
per §4) produced by the flavor's own writer — these are the byte-gate objects.
Errors respond `{"error":"<message>"}` and the CLI fails that fixture without
killing the session.

### 3.2 `exit`

`{"op":"exit"}` — the runner terminates cleanly. EOF on stdin is equivalent.

## 4. What the CLI builds on the one op

- **Leaf fixtures**: seed with the fixture's `initialState`, drive each step's
  recorded `action`, byte-compare canonical state + effects against the
  recorded expectations (canonicalized through the same writer), thread the
  actual state forward. Stop at first divergence.
- **Chain fixtures need NO extra op**: steps carry their `node` key, per-node
  states seed from `initialStates`, and the hop-DERIVED action is recorded in
  the fixture — the CLI drives one state slot per node and byte-gates
  `expectedEffects` (and `expectedState` where recorded). The `linkToNext`
  seam invariant is a CLI-side canonical-string equality.
- **`record` / `--check`**: regeneration drives the same op and writes through
  the CLI-side §6 pretty writer — the corpus's sole writer for the lane.

## 5. What deliberately does NOT cross the protocol

Pure replay only. Hop-derivation **authoring** checks (typed delegate→action
mapping), scenario `Then`/`ThenEffects` closures, structure/drift checks
against scenario sources, and every runtime-kernel rule (those are the
kernel-trace fixtures' domain — kernel-trace-v0.md) stay **in-process** in the
flavor's own test lane. TestStore-style runtime assertions never ride the
protocol.

## 6. Flavor adapters (the per-flavor ~100 LOC)

- **Swift flavor**: `DuetReplay` — `ReplayFeature.entry` (typed registry
  entry), `ReplayRegistry`, `ReplayServer.serve(registry:)`; an app's
  replay-runner executable is three lines.
- **KMP flavor**: `dev.modaal.duet.replay` — `ReplayFeature.entry`,
  `ReplayRegistry`, `ReplayServer.serve(registry)`; an app's runner `main` is
  three lines on the JVM host lane. The same registry powers the
  `BoundaryReplay` session surface consumed across the SKIE/XCFramework
  boundary — one registry, two transports.

## 7. Versioning

The version is carried in the handshake. Additive, wire-compatible evolution
(new optional request fields, new ops) bumps the minor understanding on this
page without breaking v1 runners — the CLI must ignore fields it does not
know and treat unknown-op errors as per-fixture failures. Any change to the
`reduce` semantics or the canonical-string contract is a new major protocol
version and a new contract page.
