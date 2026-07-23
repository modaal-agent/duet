// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.replay

import dev.modaal.duet.kernel.serialization.CanonicalJson
import dev.modaal.duet.kernel.serialization.CanonicalSerializers
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException

/**
 * The spine-persistence path through the core (FC2-b, productized): process-death
 * capture/restore as core-owned String functions over the app's spine type, so NO
 * platform-side spine codec exists — the app boundary is string-only.
 *
 * The persisted form IS the canonical dialect (sorted keys, canonical scalars) —
 * one writer, both platforms; an app pins byte-compatibility with a spine golden
 * fixture. This strictly improves on per-platform envelope codecs, which are only
 * same-platform round-trip safe.
 *
 * [decode] is deliberately tolerant: "a stale or foreign payload restores
 * nothing" — any malformed, foreign-shaped, or partially-valid payload yields
 * null and the app boots fresh.
 */
object SpineBoundary {
  /** Canonical bytes for the state-restoration payload (SceneDelegate userInfo / Bundle). */
  fun <T> encode(serializer: KSerializer<T>, spine: T): String =
    CanonicalJson.canonicalString(
      CanonicalSerializers.json.encodeToJsonElement(serializer, spine))

  /** Tolerant restore: null on anything that is not a well-formed spine payload. */
  fun <T> decode(serializer: KSerializer<T>, json: String): T? =
    try {
      CanonicalSerializers.json.decodeFromString(serializer, json)
    } catch (_: SerializationException) {
      null
    } catch (_: IllegalArgumentException) {
      null
    }
}
