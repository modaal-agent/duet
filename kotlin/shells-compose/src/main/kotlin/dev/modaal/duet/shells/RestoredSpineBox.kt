// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.shells

/**
 * One-shot holder for the process-death route spine — the entry decision's
 * bracket between "a spine was restored" and "some tree consumed or dropped
 * it". Twin of the Swift flavor's `RestoredSpineBox` (it rides in
 * `DuetShells/RouteSpineCodec.swift`); graduated from the adopter's app-side
 * copy on the 2026-07-30 graduation review — the scaffold-emitted Android app
 * tree is the second consumer.
 *
 * Semantics (the W4 rulings, verbatim from the Swift original):
 * - [take] drains — the first main-tree build consumes the spine, then the
 *   box is empty forever ("main-landing-consumes-the-spine").
 * - [discard] empties and settles — a FUNNEL mount breaks session
 *   continuity, so a main tree mounted after it boots virgin (a stale spine
 *   must never resurrect signed-in routes under a signed-out user).
 * - [place] is the LATE delivery path: platform restoration may hand the
 *   payload over only after the tree was built around this box. First
 *   placement wins; a settled box ignores it.
 */
class RestoredSpineBox<Spine : Any>(spine: Spine? = null) {
  private var spine: Spine? = spine
  /**
   * Once the entry decision has consumed ([take]) or dropped ([discard]) the
   * box, it stays empty forever — a late [place] must never reach a tree
   * that already decided (e.g. a virgin tree, or a funnel).
   */
  private var settled = false

  /** Drains the box: the first caller gets the spine, everyone after null. */
  fun take(): Spine? {
    settled = true
    val taken = spine
    spine = null
    return taken
  }

  /** The non-main entry decision's drop (see the type doc). */
  fun discard() {
    settled = true
    spine = null
  }

  /** The late delivery path: first placement wins; a settled box ignores it. */
  fun place(spine: Spine?) {
    if (settled || this.spine != null) return
    this.spine = spine
  }
}
