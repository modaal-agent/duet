// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The compact canonical JSON writer — contracts/serialization.md §1–§2, the
 * byte-gate currency. Core-owned and multiplatform: host and boundary emit
 * identical bytes because the same code runs on both. The Swift-flavor mirror
 * (DuetReplay/ReplayCanonical.swift) must produce byte-identical strings.
 *
 * The §6 pretty writer (the on-disk fixture form) is deliberately ABSENT from
 * this flavor (F4·S2, G1): fixture files are materialized by the `duet` CLI
 * through the framework's one pretty implementation — the record mode emits
 * compact artifacts only, so the on-disk form cannot drift per flavor.
 *
 * Two JVM idioms from the original corpus writer — `String.format("%04x", …)`
 * and `CharSequence.codePoints()` — are replaced with common-stdlib equivalents
 * ([codePointsOf] and the control-char escape) that are byte-for-byte identical.
 */
object CanonicalJson {
  private val integerPattern = Regex("-?\\d+")

  fun canonicalString(element: JsonElement): String =
    buildString { write(element, this) }

  private fun write(element: JsonElement, sb: StringBuilder) {
    when (element) {
      is JsonNull -> sb.append("null")
      is JsonPrimitive -> writePrimitive(element, sb)
      is JsonObject -> {
        sb.append('{')
        var first = true
        // Sorted by Unicode scalar (code point) value — matches Swift's UTF-8 byte order.
        for (key in element.keys.sortedWith(scalarOrder)) {
          if (!first) sb.append(',')
          first = false
          writeString(key, sb)
          sb.append(':')
          write(element.getValue(key), sb)
        }
        sb.append('}')
      }
      is JsonArray -> {
        sb.append('[')
        var first = true
        for (item in element) {
          if (!first) sb.append(',')
          first = false
          write(item, sb)
        }
        sb.append(']')
      }
    }
  }

  private fun writePrimitive(primitive: JsonPrimitive, sb: StringBuilder) {
    if (primitive.isString) {
      writeString(primitive.content, sb)
      return
    }
    when (val content = primitive.content) {
      "true", "false", "null" -> sb.append(content)
      else -> {
        require(integerPattern.matches(content)) {
          "Double/float values are forbidden in fixture-visible types (serialization.md §2): $content"
        }
        sb.append(content)
      }
    }
  }

  private val uuidShape =
    Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

  // Escaping rule from serialization.md §1: only `"`, `\`, and control chars < 0x20.
  // UUID-shaped strings are lowercased (§2 — Swift's UUID encodes uppercase).
  private fun writeString(rawValue: String, sb: StringBuilder) {
    val value = if (uuidShape.matches(rawValue)) rawValue.lowercase() else rawValue
    sb.append('"')
    for (ch in value) {
      when {
        ch == '"' -> sb.append("\\\"")
        ch == '\\' -> sb.append("\\\\")
        ch == '\n' -> sb.append("\\n")
        ch == '\r' -> sb.append("\\r")
        ch == '\t' -> sb.append("\\t")
        // Identical to JVM `"\\u%04x".format(ch.code)`: 4-digit zero-padded lowercase
        // hex — control chars are all < 0x20, so at most two hex digits, always
        // padded to four.
        ch.code < 0x20 -> sb.append("\\u").append(ch.code.toString(16).padStart(4, '0'))
        else -> sb.append(ch)
      }
    }
    sb.append('"')
  }

  // Public so the fixture differ (:kernel-test) walks keys in the same order the
  // canonical writer emits them.
  val scalarOrder = Comparator<String> { a, b ->
    // [codePointsOf] reconstructs the JVM `codePoints()` sequence in common code.
    val aPoints = codePointsOf(a)
    val bPoints = codePointsOf(b)
    val common = minOf(aPoints.size, bPoints.size)
    for (i in 0 until common) {
      val diff = aPoints[i].compareTo(bPoints[i])
      if (diff != 0) return@Comparator diff
    }
    aPoints.size.compareTo(bPoints.size)
  }

  // Common-stdlib replacement for JVM's `String.codePoints().toArray()`: folds UTF-16 surrogate
  // pairs into single supplementary code points so ordering matches Swift's UTF-8 byte
  // order (code-point order), identical to the JVM stream for every input.
  private fun codePointsOf(value: String): IntArray {
    val points = ArrayList<Int>(value.length)
    var i = 0
    while (i < value.length) {
      val ch = value[i]
      if (ch.isHighSurrogate() && i + 1 < value.length && value[i + 1].isLowSurrogate()) {
        points.add(0x10000 + ((ch.code - 0xD800) shl 10) + (value[i + 1].code - 0xDC00))
        i += 2
      } else {
        points.add(ch.code)
        i += 1
      }
    }
    return points.toIntArray()
  }
}
