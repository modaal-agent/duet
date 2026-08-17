# Presentation contract (v1.0 — NORMATIVE, graduated W5 2026-07-15)

The cross-platform contract for **state-driven presentation**: how "what is on
screen" exists as a value in feature state, how it changes, and how each platform
renders it. Companion to `store-kernel-contract.md` (which owns State/Action/
Effect shapes); this document owns the **presentation tree** — the part of state
that describes surfaces.

Design stance: a comprehensive presentation vocabulary is unsolvable by
premise, so the closed part is tiny and everything app-specific is open (five
layers, below). The contract is **derived from the reference app's measured
kinds** — it is explicitly NOT a taxonomy of everything iOS/Android can
present. v0 was the initial draft; v1.0 folds in every conversion wave's
verdicts (L0.1 `stage`, `overlay` struck, the closure check, the island sweep)
and is the document of record: changes to the closed layer are versioned
contract events per §2. The measured instances and per-node ledgers quoted
throughout are the reference app's — worked evidence, not framework surface.

Every obligation below is IN FORCE. Bracketed wave tags (**[W0]**, **[W1]**,
**[W4]**) are provenance — when the obligation landed — not status.

---

## 1. The five layers

| Layer | What | Open/closed | Owner |
| --- | --- | --- | --- |
| L0 | Structural algebra: `path` / modal `slot` / `tabs` / `stage` (`overlay` struck at W3 — see §2) | **Closed** at five (additions are versioned contract events; default answer no) | This doc |
| L1 | Kinds — what a surface *is* (`memoryDetail`, `capture`, …) | **Open** (app enums) | Feature dialects |
| L2 | Verbs — how structure *changes* (actions; no silent transitions) | **Open** (app actions) | Feature dialects |
| L3 | Manner — how a kind *renders* on a platform (detents, covers, ModalBottomSheet) | **Open** (per-platform plugins + waivers) | Hosts + manifest |
| L4 | Opaque islands — declared regions *outside* the tree | **Open** (ledgered escape hatch) | Manifest |

Parity gates **L0–L2 byte-for-byte** (fixtures). L3/L4 are per-platform and are
**ledgered, not gated** — the manifest's `presentation:` section is the ledger,
and the lockstep lint checks the ledger's shape and cross-references.

## 2. Layer 0 — the structural algebra [W0]

Five primitives, **closed** (v0 shipped four; `stage` landed as amendment L0.1
and the W3 closure check confirmed the set — see the amendments below). A
feature's state may embed any of them; composition of features (S4 subtree
shells) nests them into the app-wide **presentation tree**.

| Primitive | Shape (Swift / Kotlin) | Measured instance today |
| --- | --- | --- |
| `path` | `var path: [Route]` / `val path: List<Route>` | `TimelineState.path: [TimelineRoute]` |
| `slot` (modal) | `var sheet: Sheet?` / `val sheet: Sheet?` | `MainNavState.sheet: MainSheet?`, `TimelineState.sheet: TimelineSheet?`, `CaptureState.sheet: CaptureSheet?` (W1 — ten kinds, one slot) |
| `tabs` | `var activeTab: Tab` / `val activeTab: Tab` | `MainNavState.activeTab: MainTab` |
| `stage` (L0.1) | `var phase: Phase` / `val phase: Phase` — non-optional enum; exactly one full-screen child owns the screen; transitions are reducer edges; children destroyed on exit | `RootNavState.phase: RootPhase` |
| `overlay` | `var overlay: Overlay?` (non-modal, above content, doesn't block) | none as a STRUCTURED primitive — **and by the W3 closure check's verdict, none should exist** (see the dated entry below). Overlay-class feedback is plain reducer fields (capture's clock-cleared dock `hint` + `blockingMessage`/`saveError`, memorydetail's `toastMessage`, the invitecode/profile flash clocks, shared's keyed dwell/error clocks, the funnel leaves' error-copy slots) — that dialect IS the resolution. The row stays as the recorded boundary: anything that WOULD need a structured overlay (host-mounted, back-participating, restorable) is really a `slot` child and should be modeled as one. |

Rules:

- **One modal slot per node.** Stacked presentation is **composition**: a
  presented child owning its *own* slot yields a chain (the app's
  `CaptureView` cover → picker-sheet chain is the exhibit — app-live since W1:
  MainNav's slot holds the cover, `CaptureState.sheet` holds the picker). Same-owner
  modal-over-modal is an encoded swap in that owner's single slot (the
  capture→invite handoff — `chain-capture-invite` pins it; source-dialog → picker
  is the same rule inside capture's own slot).
- Route/sheet/tab payloads are pure values (`Equatable + Codable` /
  `@Serializable`), serialized canonically per `serialization.md` — Layer 0 is
  what fixtures pin and what the spine persists.
- **Additions to this table are versioned contract changes**, recorded here with
  a dated entry and flagged in review. The W3 closure check (the closure-check procedure) measures
  whether these four primitives express the whole app; any growth found there
  lands as an explicit `L0.1`, `L0.2`, … amendment section below.

### L0 amendments

- **L0.1 — `stage` (exclusive full-screen child), 2026-07-14 (W3 slice 1, flagged
  for review).** `var phase: Phase` / `val phase: Phase` — a NON-optional enum of
  full-screen children where exactly one owns the screen and transitions are
  reducer edges, not user navigation. Measured instance: `RootNavState.phase:
  RootPhase` (splash → registration → introduceYourself → onboarding → main;
  accept as an interrupt). None of the four v0 primitives express it honestly:
  not `path` (no stack, no back), not `tabs` (not user-switchable, not
  persistent-all-alive), not `slot` (nothing is "over" anything; never nil).
  This is the first closure-check data point: the spine needed
  one growth, recorded here as the contract prescribes. Rules: one stage per
  node; payloads are pure values like every other kind carrier; a stage plus a
  sibling modal `slot`-analogue (Root's `isEnterCodePresented`) composes under
  the same one-modal-slot-per-node reading.

  **Alternative considered at review — a replace-top `path`** (`path:
  [RootRoute]`, every transition replaces the active leaf). The VALUE shape
  fits — path values already admit non-push mutations (Timeline's deep-link
  rebase) — but the semantics generic hosts attach to `path` don't, on three
  counts. (1) **Back.** Path entries are back-poppable by contract (§4: the pop
  gesture re-derives as `.backPressed`; Compose `BackHandler` runs
  deepest-first). Root would be the OUTERMOST non-empty path, so a
  settled system back on main would pop the funnel toward an empty stack
  instead of leaving the app. The funnel must be back-INERT — and a
  back-exempt path is a second path dialect, worse for the algebra than a
  well-fenced fifth primitive (`path` would then mean two things and a generic
  host could rely on neither). (2) **The accept interrupt is not a push.** Its
  exit routes by COMPUTED auth/gate state, never by returning to the covered
  screen: `rootnav.coldlink.signed-in` pins accept entered over SPLASH and
  exiting to MAIN — a pop would restore splash. Remembered-return vs computed
  re-entry is exactly the stack/stage distinction. (3) **The exactly-one law.**
  A list makes `[]` and depth ≥ 2 representable, so every reducer arm and the
  W4 spine-restore path must guard shapes that cannot legitimately occur; the
  non-optional enum makes them unrepresentable. Corollary the review surfaced:
  `stage` and `tabs` share the value SHAPE (non-optional enum of exclusive
  children) and differ only in semantics — user-switchable + siblings-stay-alive
  vs reducer-edge transitions + children destroyed on exit. The L0 table
  distinguishes primitives by transition/lifecycle/back semantics, not by what
  a data structure could encode; by encoding alone, `path` could express all
  four. Manner note: an Android host remains free to RENDER the stage via
  NavController replace ops (popUpTo-inclusive) — that is L3's business; the
  structural value stays exactly-one either way.

- **L0 is CLOSED at five (review stance, 2026-07-14).** No further generic
  navigation primitives should exist — five is already borderline for an
  algebra whose whole value is that a shell can host any node generically.
  A proposed L0.2 is a contract event, not a dated entry in passing: it
  requires a full review against the L0.1 bar (every existing primitive must
  be shown to fail on attached SEMANTICS — back, lifecycle, restore — not on
  value shape, and the overload alternative must be shown to fork an existing
  primitive's meaning for generic hosts), and the default answer is no.

- **W3 closure check — PASSED, L0 confirmed at five (2026-07-14, wave exit).**
  The scheduled closure-check measurement: with the FULL app converted (16 features,
  both route nodes, all five Root funnel leaves), sweep every reducer state for
  navigation-shaped fields and check the algebra covers them. Findings:
  `path` ×2 (Timeline, Shared), modal `slot` ×5 (MainNav, Timeline, Capture,
  MemoryDetail, Shared), `tabs` ×1 (MainNav), `stage` ×1 (RootNav's `phase`,
  L0.1) with its sibling modal flag (`isEnterCodePresented` — the
  one-slot-per-node reading recorded at L0.1). Nothing needed a sixth primitive;
  no L0.2 is proposed. Two boundary rulings the sweep surfaced, recorded so the
  next wave doesn't re-litigate them:
  1. **`OnboardingState.page` is NOT structural.** The value shape matches
     `stage`/`tabs` (non-optional enum, reducer-edge transitions), but no host
     derives child MOUNTS from it — the pages are one feature's view content
     (zero mounted subtrees, zero hoisted stores). A field is L0-structural
     only when a generic shell attaches lifecycle to its transitions; plain
     enums that drive copy/layout inside one view are feature data. (Same
     ruling as the slice-4 "carousels are manner" call, now stated as the
     general rule.)
  2. **`overlay` — the parked W1 decision — is DECLINED as structure.** After
     the full conversion there are zero structured-overlay candidates: every
     overlay-class instance is feature-local transient feedback (toasts, hints,
     error banners, flash clocks) carrying at most one verb, several
     clock-cleared. No generic host semantics attach — no back participation,
     no child lifecycle, no restore (a restored toast would be a bug), and
     several instances legitimately CO-EXIST (capture can show `saveError` and
     the dock `hint` at once), which a single `Overlay?` slot would falsely
     serialize. Plain reducer fields remain the dialect; the row above records
     the boundary test for anything heavier. Accept — the wave's last convert —
     is the confirming data point: an L2 network funnel with terminal states
     landed with ZERO structural fields, its interrupt semantics riding the
     Root stage's phase payload exactly as the L0.1 entry predicted.

## 3. Layer 1 — kinds [W0, grows per wave]

A *kind* is a case of an app-defined route/sheet/tab/overlay enum. The contract
does not enumerate kinds; it constrains their shape:

- Payloads are seed values (ids, configs, flags) — never live objects.
- A new kind = a new enum case + a host rendering arm (W1+: a registry entry).
  Nothing else in the contract changes.

Kinds in force today:

| Node | Primitive | Kind | Payload |
| --- | --- | --- | --- |
| timeline | path | `memoryDetail` | `memoryId, context, startEditing, startSharing` |
| timeline | slot | `sharePicker` | `memoryId, config` |
| memorydetail | slot | `sharePicker` | `config` (app-live since W1 — the nested slot on a composed node: one slot per node, chained) |
| capture | slot | `photoSource / photoLibrary / camera / videoSource / videoRecorder / videoLibrary / voiceRecorder / location / friends / date` | — (all payload-free; app-live since W1). ONE slot spans what iOS renders through three channels — confirmation dialogs, sheets, full-screen covers — the channel split is manner (§5). The legacy `activeSheet` + `activeFullScreen` view-state pair collapsed into it. |
| shared | path | `memoryDetail` | `memoryId, context, startEditing` (route kind #2 — W2; no `startSharing`: memory deep links rebase the my-lane spine only) |
| shared | slot | `sharePicker` | `memoryId, config` (the third mount) |
| mainnav | slot | `capture` | — |
| mainnav | slot | `inviteCode` | `prefilledCode: String?` |
| mainnav | slot | `notificationPriming` | — |
| mainnav | tabs | `myLane / shared / profile` | — |

## 4. Layer 2 — verbs and the no-silent-transitions rule [W0]

A *verb* is any action whose reduction mutates Layer-0 fields. Verbs are ordinary
actions — user-defined verbs cost nothing and are fixture-covered for free.

**The rule: no silent transitions.** Every Layer-0 mutation happens in a reducer
arm in response to a named action. Hosts never write structure directly:

- Interactive dismissals re-enter as actions (the sheet `onDismiss` →
  `captureFinished(didSave: false)` path, with the reducer's stale-dismissal
  guard making double reports harmless).
- The `NavigationStack` pop gesture re-derives as a semantic `.backPressed`; a
  cancelled mid-swipe must not send one (device-pass judgment 1).
- System-initiated changes (deep links, push taps) enter as `deepLink`-class
  actions and fold through reducers (`MainNavAction.deepLink` →
  `memoryDeepLinked` middle hop).

Verbs in force today (receipts = the recorded fixtures): `tabSelected`,
`captureRequested/captureFinished`, `inviteCodeRequested/inviteSheetDismissed`,
`notificationPrimingRequested/notificationPrimingDismissed`, `backPressed`,
`deepLink/memoryDeepLinked`, `memorySelected`, `editRequested`,
`shareRequested/shareSheetDismissed`; memorydetail (app-live since W1):
`shareEditTapped/shareSheetDismissed`, `backTapped`; capture (app-live since W1):
`dockTapped`, `photoSourceChosen/videoSourceChosen` (the same-owner slot swap),
`dateChipTapped/audienceChipTapped`, `modalDismissed(kind)` (ONE dismissal verb for
all ten kinds — the kind-equality guard keeps channel-racing reports inert);
mainnav: `capture(event)` (the second embedded child seam — completed/cancelled
close the cover, inviteCodeRequested swaps cover→invite), `inviteCode(event)`
(the third embedded seam, W1's closer — `finished` clears the slot;
`inviteSheetDismissed` stays the VIEW's interactive-dismiss report, the same split
as capture), `profile(event)` (the fourth embedded seam, W2's opener —
`inviteCodeRequested` opens the invite sheet; `enterCodeRequested`/`accountClosed`
are HOST-BOUNDARY events: no transition at this node, the shell's interactor hooks
forward them to Root until its W3 conversion — the seam still pins them as data).
invitecode itself owns NO slot — its intents (`copyLinkTapped`,
`regenerateConfirmed`, `photoPicked`, …) mutate banner/photo state, never
structure; its confirm dialog and picker chrome are precedent-class manner (§6).
profile likewise owns NO slot (a permanent tab child, timeline-precedent hoist):
its intents (`friendToggleTapped`, `friendRenameSubmitted`, `deleteAccountTapped`,
…) mutate list/card/danger state — the delete-arm two-tap is STATE on a reducer
clock, not a modal kind; the remove/rename alerts are precedent-class manner (§6).
shared (app-live since W2 — the second subtree root):
`memorySelected` (recipient/author context from the row, read-on-tap folded in),
`editRequested` (author route, was a delegate), `shareRequested/shareSheetDismissed`
(the third picker mount), `backPressed`, `detail(event)`/`sharePicker(event)` (its
embedded child seams — the M4 stale-delegate guard re-armed on route kind #2);
its read dwell (`incomingCardAppeared/Disappeared` → keyed clock) and reactions
(`reactionSet/reactionCleared` + failure reverts) mutate row state, never
structure — the app's first PER-ENTITY keyed clock families; mainnav:
`shared(event)` (the fifth embedded seam — `inviteCodeRequested` opens the invite
sheet; `enterCodeRequested` is HOST-BOUNDARY, forwarded by the shell's hook until
Root's W3 conversion).
priming (app-live since W2's closer — the LAST proxy listener retired): two verbs
only, `enableTapped/notNowTapped`, over a one-field outcome latch (the first verb
wins; enable fires the permission prompt as the FEATURE's own effect); it owns NO
slot and no clock; mainnav: `priming(event)` (the sixth embedded seam — either
event closes the soft-ask slot, kind-guarded; `notificationPrimingDismissed` stays
the VIEW's interactive-dismiss report, the same split as capture/invite).

Audit procedure (the per-wave "presentation ledger" receipt): grep the
wave's host/shell diffs for writes to Layer-0 fields outside `store.send` — any
hit is a violation or a missing verb.

## 5. Layer 3 — manner: plugins and waivers [W1 seam, W0 schema]

*Manner* is everything the reducer must NOT know: detents vs `ModalBottomSheet`,
push animation curves, corner radii, drag indicators. The semantic/manner
firewall keeps fixtures byte-identical across platforms.

**Plugin registry seam [W1 — landed for the my-lane host].**
`DuetShells.PresentationRegistry` is the helper; the reference adopter's main
navigation shell is the first instance, carrying `TimelineRoute` (detail push), `TimelineSheet`
(share picker + detents), and — since the Capture conversion — `MainSheet` (the
capture cover's chrome: single `.large` detent, corner radius; the invite arm's
feature converted with W1's closer; priming's with W2's closer — every `MainSheet`
arm now wraps a converted store child). W2 added `SharedRoute` (the second stack's
detail push) and `SharedSheet` (picker mount #3) — every tab-level kind now
resolves through the registry.
Scoping note: the registry is per interior HOST; a node whose slot kinds all
render inside its own view (MemoryDetail's picker sheet; Capture's ten kinds
across three iOS channels) renders directly — a same-node registry is ceremony,
not a seam (standing rule; W3 closed without adding one). The shape:

```
registry.register(TimelineRoute.self)  { route  in /* build/reuse RIB child, wrap, style */ }
registry.register(MainSheet.self)      { sheet  in /* sheet chrome: detents, indicators */ }
```

- A renderer receives the kind's **payload value** and returns the platform
  surface (view controller / composable) plus its manner styling.
- Renderers may wrap ANY native API — including tricks and workarounds; the
  registry is where creativity lives without touching the contract.
- Registration is composition-root work (the shell), not feature work: a feature
  ships its kind; each platform's composition root binds the renderer.

**Authoring guide — adding a kind (the whole recipe).** The registry helper is
`DuetShells.PresentationRegistry` (it lives beside the shell glue —
`StoreHost`/`ProjectionJoin`/`StateTransitions`/`Relay` — one library, one
import). To add a presentable surface:

1. **Feature ships the kind**: a new case on the owning node's route/sheet enum
   with a pure-value payload (§3). The fixture lane pins it byte-for-byte on
   both platforms before any rendering exists — record the scenario first
   (golden-first rule).
2. **The verb(s)**: reducer arms that set/clear the kind, named for intent
   (§4 — no silent transitions; interactive dismissals re-enter as the VIEW's
   report action with a stale-dismissal guard).
3. **Each platform's composition root binds the renderer**: an interior host
   adds a registry arm (`registry.register(Kind.self) { payload in … }`);
   a same-node kind renders directly in the owning view. Manner lives ONLY
   here — detents, covers, animation, chrome.
4. **Divergence in manner CLASS** (not styling) between platforms → a
   `manifest.yaml → presentation.waivers` entry (shape below). Divergence in
   styling needs nothing.
5. **What must never happen**: the reducer learning manner (a `detent` field in
   feature state is a firewall breach); a host writing Layer-0 fields outside
   `store.send` (the per-wave ledger audit greps for exactly this, §4).

**Manner waivers [W0 schema].** When one platform deliberately renders a kind in
a different manner *class* than the other (not just styling — e.g. a full-screen
dialog where the twin uses a half-height sheet), the divergence is recorded in
`manifest.yaml → presentation.waivers` with kind, platform, manner, reason, and
date. the lockstep lint validates entry shape and that the kind's feature exists.
Waivers are reviewed, not gated: the ledger exists so divergence is a decision,
never an accident.

## 6. Layer 4 — opaque islands [W0 schema, W1 first entries]

An *island* is a declared region whose internal presentation state lives outside
the tree (gesture-driven chrome, media viewers, platform components with
uncontrollable internals). The escape hatch is first-class but **ledgered**:

- Declared in `manifest.yaml → presentation.islands`: id, owning feature,
  boundary summary (the serializable value the spine persists **instead of** the
  island's internal state), reason, date.
- An island has **no tree children** — nothing inside an island may host Layer-0
  structure. If it needs to, it isn't an island.
- **[W4]** Persistence encodes Layer 0 + island boundary summaries; an island
  restores to its summary, never its internal gesture state (restore drill
  includes one island case: kill mid-carousel → restore to the carousel's
  summary).
- **Third-verb heuristic:** the first two actions an island wants are usually
  incidental; the third means it has structure — promote it to a kind. The W5
  island-ledger sweep applies this retroactively. (the lockstep lint cannot count
  verbs yet; the sweep is a review procedure, not a lint.)

Declared (W1): `memorydetail.photo-carousel`, `memorydetail.video-player`
(MemoryDetail conversion) and `capture.media-capture-chrome` (Capture conversion —
the recorder KINDS are tree state; the AVCapture/AVAudioRecorder session internals
are the island, boundary "none": recorders return only `(url, durationMs)`) — see
`manifest.yaml → presentation.islands`. W2's candidate — the reaction picker —
was DECIDED by the third-verb heuristic: its chrome (long-press picker, the
a later flight overlay with its `activeFlight` view state) writes exactly two
verbs (`reactionSet`, `reactionCleared`) and hosts no structure, so it is
island-precedent-class, NOT an island — no ledger entry.
Island-precedent-class, deliberately NOT ledgered (pure-manner sub-surfaces whose
only writes are existing verbs): MemoryDetail's date/location edit sheets and its
delete/remove confirm dialogs; InviteCode's regenerate destructive-confirm (only
write: `regenerateConfirmed`) and the shared `PhotoStepView`'s internal
source-dialog/pickers (only write: `photoPicked`); Profile's remove-friend confirm
(only write: `friendRemoveConfirmed`) and rename alert (only write:
`friendRenameSubmitted` — it submits RAW input; trimming is a reducer transition,
so the alert stays pure chrome); Shared's reaction picker + flight overlay (writes:
`reactionSet`/`reactionCleared`) and its delete confirm (only write:
`deleteRequested`) — the sweep below revisits if they grow verbs.

- **W5 island-ledger sweep (2026-07-15) — no promotions; the ledger is
  unchanged.** Measured verb counts: all three declared islands still write
  ZERO verbs (`MemoryDetailAction` has no viewer-adjacent case;
  `CaptureAction` none for recorder internals). Every precedent-class surface
  above is unchanged since its declaration; Shared's reaction chrome still
  writes its same two intents — **ruling recorded**: the
  `reactionSetFailed`/`reactionClearFailed` twins are effect COMPLETIONS
  (repo-failure reverts), not chrome intents, and failure/revert twins of an
  existing verb never count toward the third-verb bar (they are that verb's
  plumbing). W3's funnel leaves brought no island candidates (error-copy slots
  are plain fields; the onboarding pager was ruled feature data at the closure
  check; splash's Lottie is view content with no boundary to summarize). One
  W4 data point on file: a warm deep link dismisses an open photo viewer
  before navigating — consistent with the island stance (the viewer lives
  outside the tree, so tree navigation closes over it); the W5 device pass
  re-judges the UX. **Convention going forward: the sweep re-runs at any wave
  exit that added manner surfaces.**

## 7. What parity means per layer (reconciliation stance)

| Layer | Cross-platform obligation | Enforcement |
| --- | --- | --- |
| L0 | identical fields, identical serialization | fixtures (`duet verify`, `duet record --check`) |
| L1 | identical kinds + payloads per feature | lockstep-lint declaration checks |
| L2 | identical verbs, identical reductions | fixtures; ledger audit per wave |
| L3 | free per platform; divergent manner *classes* waived in the ledger | lockstep-lint shape check; review |
| L4 | islands declared identically; internals free; boundary summaries identical | lockstep-lint shape check; W4 restore drill; W5 sweep |
