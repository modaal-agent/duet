// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.kernel.serialization

import kotlin.reflect.KClass
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * FC2-a arm (b) — the DERIVED canonical sum-type serializer: one generic base replaces
 * every hand-written per-case `{"case": …, "value": …}` coder (contracts/serialization.md §4).
 *
 * How it works: each sealed subclass is plainly `@Serializable` (+ `@SerialName` when a
 * PascalCase type must encode a camelCase Swift case name), so the compiler PLUGIN owns
 * the field-level coding; this base maps the plugin's output into the canonical envelope:
 *
 * - data object / empty encoding        → `{"case": name}`            (value omitted)
 * - labeled payload (property names ARE the Swift labels)
 *                                       → `{"case": name, "value": {props…}}`
 * - `inline = true` (the Swift case has ONE UNLABELED payload)
 *                                       → `{"case": name, "value": <the single prop's value>}`
 *
 * The dialect's omit-nil rule falls out for free: with the pinned config
 * (`explicitNulls = false`), a subclass whose only property is nil encodes to `{}`,
 * which this base emits as the bare `{"case": name}` — exactly the hand-written
 * "Swift omits `value` entirely when X is nil" arms.
 *
 * The declaration cost per sealed root is the `@Serializable(with = …)` on the ROOT plus
 * one registry line per case — after which every USE of the type (fields, `List<T>`,
 * nullable fields, nested payloads) resolves the serializer from the declaration:
 * the doc-10 §3 per-use-site attachment multiplication is gone by construction.
 *
 * Public kotlinx API only: no class discriminators, no SealedClassSerializer internals.
 * Inline decode rebuilds `{prop: value}` from the subclass descriptor's single element
 * name; labeled decode passes the `value` object through unchanged.
 */
abstract class CanonicalSumSerializer<T : Any>(
  serialName: String,
  cases: List<Case<out T>>,
) : KSerializer<T> {

  class Case<S : Any>(
    val kclass: KClass<S>,
    val serializer: KSerializer<S>,
    val inline: Boolean,
  ) {
    /** The wire case name: the subclass's serial name (set `@SerialName` for camelCase). */
    val caseName: String = serializer.descriptor.serialName
  }

  companion object {
    /** Registry entry: `case(Sub::class, Sub.serializer())`, `inline = true` for unlabeled payloads. */
    fun <S : Any> case(
      kclass: KClass<S>,
      serializer: KSerializer<S>,
      inline: Boolean = false,
    ): Case<S> = Case(kclass, serializer, inline)
  }

  private val byClass: Map<KClass<out T>, Case<out T>> = cases.associateBy { it.kclass }
  private val byName: Map<String, Case<out T>> = cases.associateBy { it.caseName }

  @OptIn(ExperimentalSerializationApi::class)
  override val descriptor: SerialDescriptor =
    SerialDescriptor(serialName, JsonObject.serializer().descriptor)

  override fun serialize(encoder: Encoder, value: T) {
    val e = encoder as JsonEncoder
    val case = byClass[value::class]
      ?: throw SerializationException("Unregistered ${descriptor.serialName} subclass ${value::class}")
    @Suppress("UNCHECKED_CAST")
    val encoded = e.json.encodeToJsonElement(case.serializer as KSerializer<T>, value).jsonObject
    e.encodeJsonElement(
      buildJsonObject {
        put("case", case.caseName)
        if (encoded.isNotEmpty()) {
          if (case.inline) {
            put("value", encoded.values.single())
          } else {
            put("value", encoded)
          }
        }
      })
  }

  @OptIn(ExperimentalSerializationApi::class)
  override fun deserialize(decoder: Decoder): T {
    val d = decoder as JsonDecoder
    val element = d.decodeJsonElement().jsonObject
    val caseName = element.getValue("case").jsonPrimitive.content
    val case = byName[caseName]
      ?: throw SerializationException("Unknown ${descriptor.serialName} case '$caseName'")
    val value = element["value"]
    val payload: JsonObject =
      when {
        value == null -> JsonObject(emptyMap())
        case.inline ->
          JsonObject(mapOf(case.serializer.descriptor.getElementName(0) to value))
        else -> value.jsonObject
      }
    @Suppress("UNCHECKED_CAST")
    return d.json.decodeFromJsonElement(case.serializer as KSerializer<T>, payload)
  }
}
