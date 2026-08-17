# Canonical serialization (v0)

The single JSON dialect both platforms encode to when comparing against golden fixtures.
Swift implements it with a configured `JSONEncoder` + canonical `Codable` coders; Kotlin
with `kotlinx.serialization` + a canonical serializer. If the two encoders disagree on any
value, the fixture turns red — that is a feature: serialization is parity surface;
specify it or it bites.

## 1. Canonical form

- UTF-8, no BOM.
- Object keys sorted **lexicographically by Unicode scalar value** at every nesting level.
- Comparison is done on the canonical *string*: both the fixture's expected sub-tree and the
  actual encoded value are re-serialized canonically (sorted keys, no insignificant
  whitespace) and compared as strings — so fixtures on disk may be pretty-printed for
  humans; canonicalization normalizes them before compare.
- String escaping (both canonical writers are hand-rolled, so this is pinned): escape only
  `"` → `\"`, `\` → `\\`, and control chars < 0x20 — `\n`, `\r`, `\t` by shorthand, all
  other control chars as `\u00xx` (lowercase hex, 4 digits). Everything else, including
  non-ASCII, is raw UTF-8 (never `\uXXXX`-escaped).

## 2. Scalar rules

| Type | Rule | Example |
| --- | --- | --- |
| String | JSON string, standard escaping | `"hello"` |
| Bool | JSON bool | `true` |
| Int (Swift `Int` ↔ Kotlin `Int`/`Long`) | JSON number, no fraction, no exponent | `42` |
| Double / Float | **FORBIDDEN in fixture-visible types (v0)** — no cross-platform repr rule chosen yet | — |
| Date (`Date` ↔ `java.time.Instant`) | ISO-8601 UTC, exactly 3 fractional digits, `Z` suffix | `"2026-07-02T09:30:00.000Z"` |
| UUID | lowercase 8-4-4-4-12 string. Enforced by the canonical **writers**: any string that is *exactly* a UUID shape is lowercased during canonicalization (Swift's `UUID` encodes uppercase — the timeline golden caught this; per-property custom coding would forfeit Codable synthesis) | `"6ba7b810-9dad-11d1-80b4-00c04fd430c8"` |
| Optional / nullable | key **omitted entirely** when nil/null — never encoded as JSON `null`. (v0→v1 flip: Swift's synthesized Codable omits nils via `encodeIfPresent`; forcing explicit nulls would mean hand-writing every struct's coding. kotlinx must set `explicitNulls = false`.) | *(key absent)* |

## 3. Composite rules

- **Struct / data class** → JSON object; keys are the property names verbatim (camelCase;
  the names must match across platforms — the lockstep lint). **Every non-nil property is
  always encoded**, including ones equal to their declared default — the pinned kotlinx
  configuration is `Json { encodeDefaults = true; explicitNulls = false }`
  (`encodeDefaults` because kotlinx otherwise omits default-valued fields — the counter
  golden caught that divergence on its first cross-platform run; `explicitNulls = false`
  to match Swift's omit-nil rule in §2).
- **Array / List** → JSON array, order-significant.
- **Dictionary / Map** → only string keys allowed in fixture-visible types; JSON object with
  the same sorted-key rule.
- **Raw-value enums** (Swift `enum X: String` ↔ Kotlin enum with `@SerialName`) → the raw
  value as a bare scalar.

## 4. Sum types (associated-value enums / sealed hierarchies)

The explicit `case`/`value` encoding — never platform defaults:

```json
{"case": "increment"}
{"case": "memorySelected", "value": {"memoryId": "6ba7b810-..."}}
```

- `case` — the Swift case name verbatim (camelCase). Kotlin sealed subclasses carry it via
  `@SerialName("increment")` on `data object Increment` etc.
- `value` — **omitted entirely** for payload-less cases. For cases with labeled associated
  values, an object keyed by the labels. A single unlabeled payload encodes as
  `"value": <encoded payload>` directly.

Kernel `Effect<Payload>` serializes as a sum type with `kind` instead of `case` (so
feature-level `case` never collides with the kernel wrapper):

```json
{"kind": "run", "id": "counter.ticker", "payload": {"case": "startTicker"}}
{"kind": "run", "payload": {"case": "logEvent", "value": {"name": "x"}}}
{"kind": "cancel", "id": "counter.ticker"}
```

`id` is omitted on an anonymous `run` (the §2 omit-nil rule, uniformly applied); `payload`
is absent on `cancel`.

## 5. Fixture schema

`parity/fixtures/<feature>[.<scenario>].fixture.json`:

```json
{
  "feature": "counter",
  "description": "human-readable intent",
  "initialState": { …canonical State… },
  "steps": [
    {
      "action": { …canonical Action… },
      "expectedState": { …full canonical State after this action… },
      "expectedEffects": [ …canonical Effect array, order-significant… ]
    }
  ]
}
```

### Dialect 2 (scenario-compiled fixtures)

Fixtures compiled from scenarios add **metadata that is NOT part of the byte gate**:

```json
{
  "dialect": 2,
  "feature": "sharepicker",
  "description": "…",
  "scenario": { "source": "…/SharePickerScenarioTests.swift" },
  "initialState": { … },
  "steps": [
    { "label": "filtering › the query narrows to 'a'", "line": 45,
      "action": { … }, "expectedState": { … }, "expectedEffects": [ … ] }
  ]
}
```

(An earlier draft also recorded `scenario.authoredOn`. Dropped: with record modes on
both platforms (§6) it is pure churn — re-recording on the other platform would flip a
byte that verifies nothing. Which platform last wrote a fixture is git's job.)

Scenarios may fork into **branches** (static alternates — every branch always runs;
see the DSL): each root→leaf path compiles to its own fixture named
`<fixture>.<branch-slug>[.<nested-slug>…].fixture.json`, and the scenario block gains
`"branch": "<slug path>"`. Each leaf file is an ordinary linear dialect-2 fixture —
replay tooling needs no tree awareness.

The comparable projection stays exactly `initialState` + each step's
`action`/`expectedState`/`expectedEffects`; dialect-1 files remain replayable (metadata
is simply absent). Fixtures are **build products**: the only writer is the
scenario runner's record mode (`duet record`); hand-edits are review defects.

Runner semantics (identical both platforms):

1. Decode `initialState`.
2. For each step in order: decode `action`, run the **pure reducer**, then
   - canonicalize(actual state) must equal canonicalize(`expectedState`) — **full state**,
     not a diff, so fixtures are self-describing and mutation-drill-proof;
   - canonicalize(actual effects) must equal canonicalize(`expectedEffects`) — order matters.
3. On divergence (dialect 2): stop at the first divergent step (later steps replay
   against poisoned state) and report fixture name, step index, step label, action, the
   **first divergent JSON path** with both canonical fragments at that path
   (FixtureDiff), and the scenario `source:line`; also write a machine report to
   `parity/.runs/<platform>/<fixture>.json` (pass runs write one too) for
   `duet explain` / `--json` consumers.
4. Scenario-executed verifies additionally gate **drift**: the scenario's action at each
   step must canonical-match the fixture's recorded action (else `structure` failure
   with a regen hint), and step counts/initial state must agree.
5. Scenario-executed verifies run a step's trailing local `Then`s BEFORE that step's
   byte gate (the gate flushes just before the next step, and at walk end): a failing
   Then reports the author's *intent* at the Then's own source line, with the step's
   byte divergence (path + fragments) attached as detail. Gate-first would win the
   race and bury the intent.

Determinism precondition: fixtures may only contain values a pure reducer can produce —
which is guaranteed by contract D1 (reducer takes no Environment; fresh UUIDs/timestamps
enter as action payloads recorded in the fixture).

### Chain fixtures, dialect 2

`chain-*.fixture.json` pin composition SEAMS: per-step `node` + `action` +
`expectedEffects` (never `expectedState` — state evolution belongs to leaf fixtures),
`linkToNext: true` asserting the step's final `notifyListener` payload is byte-identical
to the next step's embedded action value. Dialect 2 adds the same metadata as feature
fixtures (`dialect`, `scenario.source`, per-step `label`/`line`) and makes
`initialStates` **always explicit** (one entry per node; dialect 1 allowed omission =
platform defaults, which made the replayed baseline invisible in review). Chain
scenarios are authored with the chain DSL (`ChainScenario`; hops between nodes carry
the delegate→parent-action mapping) and recorded like feature fixtures.

## 6. On-disk pretty form (fixture files)

Verification never reads bytes off disk directly — both gates compare re-serialized
canonical strings (§1) — but fixture *files* are committed and reviewed, so their
formatting is pinned too. One format, byte-identical from both platforms' record modes,
so re-recording anywhere yields clean git diffs and CI can enforce the build-product rule with
`duet record --check` (regenerate + fail-if-changed):

- 2-space indent; key/value separator `": "` (no space before the colon).
- Object keys in canonical order (§1 — sorted by Unicode scalar value).
- Empty composites inline: `{}` and `[]` (never spread across lines).
- Strings escaped exactly as §1 (notably: `/` is never escaped — `JSONSerialization`'s
  `\/` habit is banned); scalars in canonical form (§2 — lowercased UUIDs, integer
  numbers, pinned date strings).
- Exactly one trailing newline at EOF.

Implementations: `CanonicalJSON.prettyCanonicalString` (Swift) /
`CanonicalJson.prettyCanonicalString` (Kotlin). The lockstep proof is corpus-wide and
permanent: a test on each platform re-emits every committed fixture through its own
writer and asserts byte-identity with the file (`PrettyWriterParityTests[.kt]`) — any
writer drift turns the suite red on the platform that drifted.
