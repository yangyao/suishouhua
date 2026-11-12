package com.suishouhua.tv

import com.suishouhua.tv.model.Stroke
import com.suishouhua.tv.model.StrokeHistory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StrokeHistoryTest {

    private fun stroke(id: String, points: Int = 3): Stroke {
        val s = Stroke(id, "pen", "#FF0000", 1)
        repeat(points) { i -> s.addPoint(i / 10.0, i / 10.0) }
        return s
    }

    private fun StrokeHistory.draw(id: String, points: Int = 3) {
        begin(stroke(id))
        addPoints(id, (0 until points).map { listOf(it / 10.0, it / 10.0) })
        end(id)
    }

    private fun List<com.suishouhua.tv.model.Stroke>.ids() = map { it.id }

    @Test
    fun `新笔画入撤销栈并可见`() {
        val h = StrokeHistory()
        h.draw("a")
        h.draw("b")
        assertEquals(listOf("a", "b"), h.visibleStrokes().map { it.id })
        assertTrue(h.canUndo)
        assertFalse(h.canRedo)
    }

    @Test
    fun `undo 撤销最近一笔 redo 恢复`() {
        val h = StrokeHistory()
        h.draw("a")
        h.draw("b")
        h.undo()
        assertEquals(listOf("a"), h.visibleStrokes().map { it.id })
        assertTrue(h.canRedo)
        h.redo()
        assertEquals(listOf("a", "b"), h.visibleStrokes().map { it.id })
    }

    @Test
    fun `erase 删除整条且可撤销`() {
        val h = StrokeHistory()
        h.draw("a")
        h.draw("b")
        assertTrue(h.erase("a"))
        assertEquals(listOf("b"), h.visibleStrokes().ids())
        h.undo()
        assertEquals(setOf("a", "b"), h.visibleStrokes().ids().toSet())
        h.redo()
        assertEquals(listOf("b"), h.visibleStrokes().ids())
    }

    @Test
    fun `clear 入撤销栈且可恢复全部`() {
        val h = StrokeHistory()
        h.draw("a")
        h.draw("b")
        assertTrue(h.clearAll())
        assertEquals(0, h.visibleStrokes().size)
        h.undo()
        assertEquals(2, h.visibleStrokes().size)
        h.redo()
        assertEquals(0, h.visibleStrokes().size)
    }

    @Test
    fun `连续操作序列 undo redo 一致性`() {
        val h = StrokeHistory()
        h.draw("a")
        h.draw("b")
        h.erase("a")
        h.draw("c")
        h.clearAll()
        h.undo() // 恢复 clear
        assertEquals(listOf("b", "c"), h.visibleStrokes().map { it.id })
        h.undo() // 撤销 c
        assertEquals(listOf("b"), h.visibleStrokes().map { it.id })
        h.undo() // 恢复 a
        assertEquals(setOf("a", "b"), h.visibleStrokes().ids().toSet())
        h.undo() // 撤销 b
        assertEquals(listOf("a"), h.visibleStrokes().map { it.id })
        h.undo()
        assertEquals(0, h.visibleStrokes().size)
        assertFalse(h.undo()) // 空栈
        // 全部重做（共 5 个操作）
        repeat(5) { h.redo() }
        assertFalse(h.redo())
        assertEquals(0, h.visibleStrokes().size)
    }

    @Test
    fun `新操作后 redo 栈被清空`() {
        val h = StrokeHistory()
        h.draw("a")
        h.undo()
        assertTrue(h.canRedo)
        h.draw("b")
        assertFalse(h.canRedo)
        h.redo()
        assertEquals(listOf("b"), h.visibleStrokes().map { it.id })
    }

    @Test
    fun `进行中笔画未收笔不入撤销栈`() {
        val h = StrokeHistory()
        h.begin(stroke("x", points = 0))
        h.addPoints("x", listOf(listOf(0.1, 0.2), listOf(0.3, 0.4)))
        assertEquals(0, h.visibleStrokes().size)
        assertTrue(h.end("x"))
        assertEquals(1, h.visibleStrokes().size)
        assertEquals(2, h.strokeById("x")?.points?.size)
    }

    @Test
    fun `erase 不存在的笔画返回 false`() {
        val h = StrokeHistory()
        assertFalse(h.erase("nope"))
        assertNull(h.strokeById("nope"))
    }

    @Test
    fun `reset 清空一切`() {
        val h = StrokeHistory()
        h.draw("a")
        h.reset()
        assertEquals(0, h.visibleStrokes().size)
        assertFalse(h.canUndo)
    }
}
