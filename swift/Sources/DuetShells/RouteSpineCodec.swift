// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// The app carrier for a route spine (scene state restoration + handoff — the
/// platform's saved-state string). Generic over the app's spine type: the spine
/// VALUE belongs to the app's route-node feature layer (one placement, both
/// platforms — the mirror rule); the codec and the restore box are framework.
/// Same-platform round-trip only; the CROSS-platform byte contract stays pinned
/// by the consumer's spine golden fixture in its test lanes (the Android carrier
/// is the canonical kotlinx config; this one is `JSONEncoder` with the dialect's
/// date form). Decode is tolerant — a stale or foreign payload restores nothing
/// (start fresh, the Android rule), never fails the boot.
public enum RouteSpineCodec {
  public static func encode<Spine: Encodable>(_ spine: Spine) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .formatted(makeISO8601Millis())
    guard let data = try? encoder.encode(spine) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public static func decode<Spine: Decodable>(
    _ type: Spine.Type = Spine.self, from json: String
  ) -> Spine? {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(makeISO8601Millis())
    return try? decoder.decode(Spine.self, from: Data(json.utf8))
  }

  /// The dialect's date form (contracts/serialization.md §2). Built per call: the
  /// codec runs a handful of times per scene lifecycle, and a fresh formatter keeps
  /// the type free of shared mutable state under strict concurrency.
  private static func makeISO8601Millis() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return formatter
  }
}

/// One-shot carrier for the restored spine: it applies to the FIRST mount of the
/// spine's owning subtree only — a later signout→signin in the same session must
/// boot a virgin tree — and the stage host DISCARDS it when the entry decision
/// lands anywhere other than that subtree (a funnel entry means the session's
/// continuity is broken; the subtree mounted after it starts fresh).
///
/// `@MainActor` — the final shape, declared rather than conventional: the box is
/// scene-lifecycle state (created at scene connect, placed by the restoration
/// callback, drained during tree construction), all main-actor by contract.
/// Adopter expectation: an UNANNOTATED legacy host (RIBs-era builder code) that
/// touches the box from a synchronous nonisolated context brackets the access
/// with `MainActor.assumeIsolated { … }` — the documented coexistence price at
/// the legacy boundary, retired as hosts adopt isolation. Fully-annotated
/// composition roots need nothing.
@MainActor
public final class RestoredSpineBox<Spine> {
  private var spine: Spine?
  /// Once the entry decision has consumed (`take`) or dropped (`discard`) the
  /// box, it stays empty forever — a late `place` must never reach a tree
  /// that already decided (e.g. a virgin tree, or a funnel).
  private var settled = false

  public init(_ spine: Spine?) {
    self.spine = spine
  }

  /// Drains the box: the first caller gets the spine, everyone after gets nil.
  public func take() -> Spine? {
    settled = true
    defer { spine = nil }
    return spine
  }

  /// The non-main entry decision's drop (see type doc).
  public func discard() {
    settled = true
    spine = nil
  }

  /// The LATE delivery path: on iOS 26 the restoration activity arrives via
  /// `scene(_:restoreInteractionStateWith:)` AFTER the scene connects — after
  /// the tree was built around this box (the legacy
  /// `session.stateRestorationActivity` read comes up empty at connect time).
  /// First placement wins; a settled box ignores it.
  public func place(_ spine: Spine?) {
    guard !settled, self.spine == nil else { return }
    self.spine = spine
  }
}
