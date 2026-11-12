package com.suishouhua.tv.server

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** 协议常量与 JSON 编解码（docs/protocol.md v1）。 */
object Protocol {
    const val PORT = 9723
    const val CANVAS_ASPECT = 1.7777

    private val json = Json { ignoreUnknownKeys = true }

    /** 解析收到的一帧文本。未知 type 或格式异常返回 null（静默忽略）。 */
    fun parse(text: String): InMessage? = try {
        val obj = json.parseToJsonElement(text).jsonObject
        val type = obj["type"]?.jsonPrimitive?.contentOrNull ?: return null
        when (type) {
            "hello" -> InMessage.Hello
            "stroke_start" -> InMessage.StrokeStart(
                id = str(obj, "id"),
                tool = str(obj, "tool").ifBlank { "pen" },
                color = str(obj, "color").ifBlank { "#2B2B2E" },
                width = obj["width"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 2,
            )
            "stroke_points" -> InMessage.StrokePoints(
                id = str(obj, "id"),
                points = obj["points"]?.jsonArray?.map { it.jsonArray.map { v -> v.jsonPrimitive.contentOrNull?.toDoubleOrNull() ?: 0.0 } } ?: emptyList(),
            )
            "stroke_end" -> InMessage.StrokeEnd(str(obj, "id"))
            "erase" -> InMessage.Erase(str(obj, "strokeId"))
            "undo" -> InMessage.Undo
            "redo" -> InMessage.Redo
            "clear" -> InMessage.Clear
            "ping" -> InMessage.Ping
            else -> null // 未知 type 静默忽略（含 bye/idle_kick 等历史遗留）
        }
    } catch (_: Exception) {
        null
    }

    private fun str(obj: JsonObject, key: String): String =
        obj[key]?.jsonPrimitive?.contentOrNull ?: ""

    fun paired(): String = buildJsonObject {
        put("type", "paired")
        put("canvasAspect", CANVAS_ASPECT)
    }.toString()

    fun rejected(reason: String): String = buildJsonObject {
        put("type", "rejected")
        put("reason", reason)
    }.toString()

    // ping 的应答 pong、rejected 的合法 reason 目前仅 in_use

    fun pong(): String = buildJsonObject {
        put("type", "pong")
    }.toString()

    fun history(strokes: List<com.suishouhua.tv.model.Stroke>): String = buildJsonObject {
        put("type", "history")
        put("strokes", buildJsonArray {
            strokes.forEach { s ->
                add(buildJsonObject {
                    put("id", s.id)
                    put("tool", s.tool)
                    put("color", s.color)
                    put("width", s.width)
                    put("points", buildJsonArray {
                        s.points.forEach { p ->
                            add(buildJsonArray {
                                add(JsonPrimitive(p[0])); add(JsonPrimitive(p[1]))
                            })
                        }
                    })
                })
            }
        })
    }.toString()

    sealed interface InMessage {
        /** 配对请求（无字段，电视只检查占用）。 */
        data object Hello : InMessage
        data class StrokeStart(val id: String, val tool: String, val color: String, val width: Int) : InMessage
        data class StrokePoints(val id: String, val points: List<List<Double>>) : InMessage
        data class StrokeEnd(val id: String) : InMessage
        data class Erase(val strokeId: String) : InMessage
        data object Undo : InMessage
        data object Redo : InMessage
        data object Clear : InMessage
        data object Ping : InMessage
    }
}
