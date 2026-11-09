package com.example.gitpush.util

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/** kotlinx.serialization JsonElement üzerinde güvenli (null dönen) okuma yardımcıları. */
val JsonElement?.asObj: JsonObject? get() = this as? JsonObject
val JsonElement?.asArr: JsonArray? get() = this as? JsonArray
val JsonElement?.asStr: String?
    get() = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
val JsonElement?.asLong: Long?
    get() = (this as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull
val JsonElement?.asInt: Int? get() = asLong?.toInt()
val JsonElement?.asDouble: Double?
    get() = (this as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
val JsonElement?.asBool: Boolean?
    get() = (this as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull

fun parseJson(text: String): JsonElement? =
    try {
        Json.parseToJsonElement(text)
    } catch (_: Exception) {
        null
    }
