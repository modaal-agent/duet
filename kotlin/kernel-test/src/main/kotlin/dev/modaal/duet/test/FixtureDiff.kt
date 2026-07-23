// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.serialization.CanonicalJson
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * The first point where two JSON trees disagree, as a JSON path plus the canonical
 * fragment on each side (`null` = the side has nothing at that path). Powers the
 * dialect-2 failure contract: a fixture divergence names the exact leaf, not the whole
 * document. Swift mirror: DuetTesting/FixtureDiff.swift.
 */
data class FixtureDivergence(
  /** Dotted/bracketed path relative to the compared root, e.g. `selected[1].displayName`. */
  val path: String,
  val expected: String?,
  val actual: String?,
)

object FixtureDiff {
  /**
   * Walks [expected] and [actual] in canonical key order and returns the first
   * divergence, or null when the trees canonicalize identically. Key order matches the
   * canonical writer so "first" is deterministic and identical on both platforms.
   */
  fun firstDivergence(
    expected: JsonElement,
    actual: JsonElement,
    path: String = "",
  ): FixtureDivergence? {
    return when {
      expected is JsonObject && actual is JsonObject -> {
        val keys = (expected.keys + actual.keys).sortedWith(CanonicalJson.scalarOrder)
        for (key in keys) {
          val childPath = if (path.isEmpty()) key else "$path.$key"
          val expectedChild = expected[key]
          val actualChild = actual[key]
          when {
            expectedChild == null && actualChild == null -> {}
            expectedChild != null && actualChild == null ->
              return FixtureDivergence(childPath, CanonicalJson.canonicalString(expectedChild), null)
            expectedChild == null && actualChild != null ->
              return FixtureDivergence(childPath, null, CanonicalJson.canonicalString(actualChild))
            else ->
              firstDivergence(expectedChild!!, actualChild!!, childPath)?.let {
                return it
              }
          }
        }
        null
      }
      expected is JsonArray && actual is JsonArray -> {
        for (index in 0 until maxOf(expected.size, actual.size)) {
          val childPath = "$path[$index]"
          when {
            index >= expected.size ->
              return FixtureDivergence(childPath, null, CanonicalJson.canonicalString(actual[index]))
            index >= actual.size ->
              return FixtureDivergence(childPath, CanonicalJson.canonicalString(expected[index]), null)
            else ->
              firstDivergence(expected[index], actual[index], childPath)?.let {
                return it
              }
          }
        }
        null
      }
      else -> {
        val expectedFragment = CanonicalJson.canonicalString(expected)
        val actualFragment = CanonicalJson.canonicalString(actual)
        if (expectedFragment == actualFragment) null
        else FixtureDivergence(path, expectedFragment, actualFragment)
      }
    }
  }
}
