# Composition

Duet's dependency shape: a **`<X>Dependency` + `<X>Component` pair at every
composition level**, with a `<X>Builder` that constructs the Component once per
mount and resolves nothing itself. This page names the rule and its
obligations; the worker lifecycle it composes with lives in
[workers.md](workers.md).

A **composition level** is any node that mounts children: the root, each
subtree node, each leaf feature. Do not fold levels into a single app-wide hub
(one wide interface every screen reads): a hub gives every consumer every
member, so every test double implements all of them, and it gives level-scoped
objects no home, so their lifetimes are asserted by comments instead of
enforced by structure.

## The three parts

For a level named `X`:

| part | what it is | what it may not do |
| --- | --- | --- |
| `<X>Dependency` | a protocol naming **exactly** what this level consumes from its parent, member by member | name anything this level does not read |
| `<X>Component` | a class holding one `<X>Dependency`. Forwards what passes through; **owns what is scoped to this level**; conforms to each child's Dependency | reach outside its `dependency` for anything it does not own |
| `<X>Builder` | takes `dependency: <X>Dependency`, constructs the Component **once per mount**, builds the view and shell | resolve anything itself — everything it passes on comes off the Component |

The parent supplies each child's Dependency **by conforming its own Component
to it** — an empty extension when the members already line up:

```swift
extension MainComponent: TimelineDependency {}
extension MainComponent: CaptureDependency {}
```

A member reaching a leaf is either forwarded from the parent or instantiated
at this level, and which of the two is a **local** decision no other level can
observe.

## The scope-ownership contract

The Component is where a level's own objects live, and its lifetime is the
level's lifetime. Three obligations make it more than an accessor:

1. **One Component per level MOUNT.** Each `build()` constructs its level's
   Component, and every call serving that one mount uses that instance. Not
   per *call*: several calls can serve one mount, and a fresh Component per
   call has no scope — its `lazy` members reallocate mid-mount. Not *held on
   the Builder* either: a Builder outlives the mounts it makes (the parent
   constructs it once; `build()` runs again on every remount), so a
   Builder-held Component gives level-scoped objects the app's lifetime.
2. **Ownership is declared by `lazy var` on the Component; forwarding is
   declared by a computed `var` reading `dependency`.** The two forms are the
   level's answer to "instantiate here or take from the parent", and reading
   the Component tells you which without consulting the parent.
3. **A level-scoped object's lifetime is structural, not conventional.** It
   ends when the Component is released. Reusing an app-scoped instance and
   relying on a cancel bracket to reset it trades a lifetime the structure
   enforces for one a comment asserts.

## Environment factories are Component members

A feature's `<X>Environment` is the effect surface its reducer calls. It is
assembled from the repositories and services the level consumes — the members
of its `<X>Dependency` — and the Component is what holds those, so the factory
is **a method on the Component**, not on the Builder and not on a hub:

```swift
extension DetailComponent {
  func environment(
    itemId: UUID,
    onDelegate: @escaping (any DetailDelegateEvent) -> Void
  ) -> AppleDetailEnvironment {
    LiveDetailEnvironment(
      itemId: itemId, itemRepository: itemRepository, /* … */
      onDelegate: onDelegate)
  }
}
```

A Builder never names a repository. The lifetimes also fit: for a leaf,
Component lifetime **is** mount lifetime, which is what a
one-screen-one-subscription listener inside a `Live<X>Environment` requires.
Two carve-outs:

- **A factory may return the concrete `Live<X>Environment`** when the Builder
  must configure it further after the view exists (e.g. a presenting view
  controller, which has no place on the protocol).
- **A factory whose environment adopts a worker onto a caller's `StoreHost`
  belongs on the Component of the level that owns that host.** The
  environment closes over `host.adopt(…)`, so its home is where the host
  lives, not whichever level finds the factory convenient.

## The degenerate cases are kept, not optimized away

- **A level that owns nothing** has a Component that is pure forwarding. Keep
  it: it is the extension point for the first level-scoped object, and it is
  where the child conformances hang.
- **The root's Dependency is what the platform supplies**, which may be
  nothing: `public protocol RootDependency: AnyObject {}` with the app
  target's `SceneComponent` as its conformer. Two lines and an empty class are
  the honest statement that the composition root consumes nothing from
  outside.

## The two dialects

**Swift has no protocol delegation**, so a level that forwards N members
writes N one-line computed properties — and conformance is total, which is
exactly why a wide hub protocol is expensive (every double implements every
member) while a per-level Dependency stays as narrow as the level's reads.
The forwarders are mechanically derivable: `swift-sourcery-templates` ships a
`Component` template that generates them from `DuetComponent`-annotated
Dependency protocols, and hand-writing them is an accepted price at small
scale.

**Kotlin gives the forwarder for free:**

```kotlin
class MainComponent(private val dependency: MainDependency) :
  MainDependency by dependency,
  TimelineDependency,
  CaptureDependency {

  // owned at this level — the Kotlin twin of `lazy var`
  val audioPlayer: AudioPlaying by lazy { AudioPlayer(/* … */) }
}
```

`by dependency` discharges every inherited member in one clause, so the
Kotlin side costs the interface declarations plus the owned members.
Interfaces can also carry default implementations, so an optional member
costs the child nothing.
