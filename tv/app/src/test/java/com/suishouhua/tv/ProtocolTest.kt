package com.suishouhua.tv

import com.suishouhua.tv.model.Stroke
import com.suishouhua.tv.model.StrokeHistory
import com.suishouhua.tv.server.Protocol
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ProtocolTest {

    @Test
    fun `bye 属于未知消息静默忽略`() {
        assertNull(Protocol.parse("""{"type":"bye"}"""))
        assertNull(Protocol.parse("""{"type":"idle_kick"}"""))
    }

    @Test
    fun `hello 无字段解析`() {
        assertEquals(Protocol.InMessage.Hello, Protocol.parse("""{"type":"hello"}"""))
        // 带多余字段的 hello 也接受
        assertEquals(Protocol.InMessage.Hello, Protocol.parse("""{"type":"hello","code":"999999"}"""))
    }

    @Test
    fun `未知 type 静默忽略`() {
        assertNull(Protocol.parse("""{"type":"future_thing","x":1}"""))
        assertNull(Protocol.parse("""{"other":"no type"}"""))
    }

    @Test
    fun `坏帧静默忽略`() {
        assertNull(Protocol.parse("not json at all"))
        assertNull(Protocol.parse("""{"type":123}"""))
    }

    @Test
    fun `stroke 消息解析`() {
        val msg = Protocol.parse(
            """{"type":"stroke_start","id":"a1","tool":"marker","color":"#F28C28","width":2}""",
        ) as Protocol.InMessage.StrokeStart
        assertEquals("a1", msg.id)
        assertEquals("marker", msg.tool)
        assertEquals(2, msg.width)

        val pts = Protocol.parse(
            """{"type":"stroke_points","id":"a1","points":[[0.1,0.2],[0.3,0.4]]}""",
        ) as Protocol.InMessage.StrokePoints
        assertEquals(2, pts.points.size)
        assertEquals(0.3, pts.points[1][0])

        assertEquals(Protocol.InMessage.StrokeEnd("a1"), Protocol.parse("""{"type":"stroke_end","id":"a1"}"""))
        assertEquals(Protocol.InMessage.Erase("a1"), Protocol.parse("""{"type":"erase","strokeId":"a1"}"""))
        assertEquals(Protocol.InMessage.Undo, Protocol.parse("""{"type":"undo"}"""))
        assertEquals(Protocol.InMessage.Redo, Protocol.parse("""{"type":"redo"}"""))
        assertEquals(Protocol.InMessage.Clear, Protocol.parse("""{"type":"clear"}"""))
    }

    @Test
    fun `outgoing 消息格式正确`() {
        assertEquals("""{"type":"paired","canvasAspect":1.7777}""", Protocol.paired())
        assertEquals("""{"type":"rejected","reason":"in_use"}""", Protocol.rejected("in_use"))
        assertEquals("""{"type":"pong"}""", Protocol.pong())

        val h = StrokeHistory()
        val s = Stroke("s1", "pen", "#3577F2", 2)
        s.addPoint(0.5, 0.25)
        h.begin(s); h.end("s1")
        val json = Protocol.history(h.visibleStrokes())
        assertTrue(json.contains("\"type\":\"history\""))
        assertTrue(json.contains("[[0.5,0.25]]"))
    }
}
