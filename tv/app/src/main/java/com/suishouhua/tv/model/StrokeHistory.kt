package com.suishouhua.tv.model

/**
 * 单条笔画（协议 Stroke：id/tool/color/width/points）。
 * 纯 Kotlin，坐标为 0–1 归一化，无 Android 依赖，便于单元测试。
 */
class Stroke(
    val id: String,
    val tool: String, // "pen" | "marker"
    val color: String, // "#RRGGBB"
    val width: Int, // 1/2/3
) {
    val points = mutableListOf<List<Double>>() // [x, y]

    fun addPoint(x: Double, y: Double) {
        points.add(listOf(x, y))
    }
}

/** 撤销栈中的一个操作（画 / 擦 / 清空均可入栈，见 protocol.md）。 */
sealed interface CanvasOp {
    data class StrokeOp(val stroke: Stroke) : CanvasOp
    data class EraseOp(val id: String, val stroke: Stroke) : CanvasOp
    data class ClearOp(val cleared: List<Stroke>) : CanvasOp
}

/**
 * 笔画序列与撤销/重做，纯 Kotlin。
 * 与手机端通过应用相同消息序列保持一致。
 */
class StrokeHistory {

    private val visible = LinkedHashMap<String, Stroke>()
    private val current = LinkedHashMap<String, Stroke>() // 进行中的笔画（stroke_end 前不计入撤销栈）
    private val undoStack = ArrayDeque<CanvasOp>()
    private val redoStack = ArrayDeque<CanvasOp>()

    val canUndo: Boolean get() = undoStack.isNotEmpty()
    val canRedo: Boolean get() = redoStack.isNotEmpty()

    /** stroke_start：开始一条新笔画。未知 id 之外的重复开始会被忽略。 */
    fun begin(stroke: Stroke) {
        current[stroke.id] = stroke
    }

    /** stroke_points：增量点。 */
    fun addPoints(id: String, pts: List<List<Double>>) {
        val s = current[id] ?: return
        pts.forEach { p ->
            if (p.size >= 2) s.addPoint(p[0], p[1])
        }
    }

    /** stroke_end：该笔画定型，入撤销栈。 */
    fun end(id: String): Boolean {
        val s = current.remove(id) ?: return false
        visible[s.id] = s
        undoStack.addLast(CanvasOp.StrokeOp(s))
        redoStack.clear()
        return true
    }

    /** erase：按笔画擦除（删除整条），入撤销栈。 */
    fun erase(id: String): Boolean {
        val s = visible.remove(id) ?: return false
        undoStack.addLast(CanvasOp.EraseOp(id, s))
        redoStack.clear()
        return true
    }

    /** clear：清空画板，入撤销栈。 */
    fun clearAll(): Boolean {
        if (visible.isEmpty()) return false
        undoStack.addLast(CanvasOp.ClearOp(visible.values.toList()))
        visible.clear()
        redoStack.clear()
        return true
    }

    fun undo(): Boolean {
        val op = undoStack.removeLastOrNull() ?: return false
        when (op) {
            is CanvasOp.StrokeOp -> visible.remove(op.stroke.id)
            is CanvasOp.EraseOp -> visible[op.id] = op.stroke
            is CanvasOp.ClearOp -> op.cleared.forEach { visible[it.id] = it }
        }
        redoStack.addLast(op)
        return true
    }

    fun redo(): Boolean {
        val op = redoStack.removeLastOrNull() ?: return false
        when (op) {
            is CanvasOp.StrokeOp -> visible[op.stroke.id] = op.stroke
            is CanvasOp.EraseOp -> visible.remove(op.id)
            is CanvasOp.ClearOp -> visible.clear()
        }
        undoStack.addLast(op)
        return true
    }

    /** 当前可见笔画（撤销栈回放后的状态），时间顺序。 */
    fun visibleStrokes(): List<Stroke> = visible.values.toList()

    /** 按 id 查找（含进行中的笔画），供渲染取样式。 */
    fun strokeById(id: String): Stroke? = current[id] ?: visible[id]

    /** 完全重置（丢弃撤销栈），用于 5 分钟后丢弃画布内容。 */
    fun reset() {
        visible.clear()
        current.clear()
        undoStack.clear()
        redoStack.clear()
    }
}
