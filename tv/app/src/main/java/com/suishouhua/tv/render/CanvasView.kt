package com.suishouhua.tv.render

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import com.suishouhua.tv.model.Stroke
import com.suishouhua.tv.model.StrokeHistory

/**
 * 同步画板：16:9 画布 letterbox 居中，0–1 归一化坐标映射。
 * 离屏 Bitmap：stroke_points 增量绘制当前笔画；undo/redo/erase/clear 全量重绘。
 */
class CanvasView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    private var history: StrokeHistory? = null

    private var buffer: Bitmap? = null
    private var bufferCanvas: Canvas? = null
    private val canvasRect = RectF()

    /** 进行中笔画的平滑状态。 */
    private class SmoothState {
        var lastX = 0f
        var lastY = 0f
        var prevMidX = 0f
        var prevMidY = 0f
        var hasLast = false
        var hasPrevMid = false
        var hasDirty = false
        var dirtyMinX = 0f
        var dirtyMinY = 0f
        var dirtyMaxX = 0f
        var dirtyMaxY = 0f
    }

    private val states = HashMap<String, SmoothState>()
    private val drawnCounts = HashMap<String, Int>()
    private val paintCache = HashMap<String, Paint>()

    override fun onDraw(canvas: Canvas) {
        buffer?.let { canvas.drawBitmap(it, 0f, 0f, null) }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w <= 0 || h <= 0) return
        // 16:9 画布 letterbox 居中
        val aspect = 16f / 9f
        val viewAspect = w.toFloat() / h.toFloat()
        var cw = w.toFloat()
        var ch = h.toFloat()
        if (viewAspect > aspect) {
            cw = ch * aspect
        } else {
            ch = cw / aspect
        }
        canvasRect.set((w - cw) / 2f, (h - ch) / 2f, (w + cw) / 2f, (h + ch) / 2f)

        buffer = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also {
            bufferCanvas = Canvas(it)
        }
        fullRedraw()
    }

    fun attach(history: StrokeHistory) {
        this.history = history
        fullRedraw()
    }

    /** 清空显示（断开连接时），不影响 history 数据（5 分钟保留）。 */
    fun reset() {
        states.clear()
        drawnCounts.clear()
        fullRedraw()
    }

    // ---- 增量 ----

    fun onStrokeStarted(stroke: Stroke) {
        states[stroke.id] = SmoothState()
    }

    /** 增量：只绘制 id 对应笔画中尚未绘制的新点。 */
    fun onPoints(id: String, history: StrokeHistory) {
        val bc = bufferCanvas ?: return
        val state = states[id] ?: return
        val stroke = history.strokeById(id) ?: return
        val from = drawnCounts[id] ?: 0
        if (from >= stroke.points.size) return
        var dirty: RectF? = null
        for (i in from until stroke.points.size) {
            val p = stroke.points[i]
            if (p.size < 2) continue
            val r = appendPoint(bc, id, p[0], p[1])
            if (dirty == null) dirty = RectF(r) else dirty.union(r)
        }
        drawnCounts[id] = stroke.points.size
        dirty?.let {
            invalidate(
                it.left.toInt() - 1,
                it.top.toInt() - 1,
                it.right.toInt() + 2,
                it.bottom.toInt() + 2,
            )
        }
    }

    fun onStrokeEnded(id: String) {
        states.remove(id)
        drawnCounts.remove(id)
    }

    // ---- 全量重绘 ----

    fun fullRedraw() {
        val bc = bufferCanvas ?: return
        bc.drawColor(Color.WHITE)
        history?.visibleStrokes()?.forEach { stroke ->
            val path = smoothedPath(stroke) ?: return@forEach
            bc.drawPath(path, paintFor(stroke))
        }
        invalidate()
    }

    // ---- 内部 ----

    private fun appendPoint(bc: Canvas, id: String, nx: Double, ny: Double): RectF {
        val state = states[id] ?: return RectF()
        val x = px(nx)
        val y = py(ny)
        val seg = Path()
        val dirty = RectF()

        if (!state.hasLast) {
            state.lastX = x
            state.lastY = y
            state.hasLast = true
            // 单点也要可见：画一个圆点
            seg.addCircle(x, y, 1f, Path.Direction.CW)
            state.dirtyMinX = x; state.dirtyMinY = y; state.dirtyMaxX = x; state.dirtyMaxY = y
            state.hasDirty = true
        } else {
            val midX = (state.lastX + x) / 2f
            val midY = (state.lastY + y) / 2f
            if (!state.hasPrevMid) {
                seg.moveTo(state.lastX, state.lastY)
                seg.lineTo(midX, midY)
            } else {
                seg.moveTo(state.prevMidX, state.prevMidY)
                seg.quadTo(state.lastX, state.lastY, midX, midY)
            }
            state.prevMidX = midX
            state.prevMidY = midY
            state.hasPrevMid = true
            state.dirtyMinX = minOf(state.dirtyMinX, midX, x)
            state.dirtyMinY = minOf(state.dirtyMinY, midY, y)
            state.dirtyMaxX = maxOf(state.dirtyMaxX, midX, x)
            state.dirtyMaxY = maxOf(state.dirtyMaxY, midY, y)
            state.hasDirty = true
            state.lastX = x
            state.lastY = y
        }

        if (!state.hasDirty) return RectF()
        val stroke = history?.strokeById(id) ?: return RectF()
        val paint = paintFor(stroke)
        bc.drawPath(seg, paint)

        val pad = paint.strokeWidth
        dirty.set(
            state.dirtyMinX - pad,
            state.dirtyMinY - pad,
            state.dirtyMaxX + pad,
            state.dirtyMaxY + pad,
        )
        return dirty
    }

    private fun smoothedPath(stroke: Stroke): Path? {
        if (stroke.points.isEmpty()) return null
        val path = Path()
        var lastX = 0f
        var lastY = 0f
        var prevMidX = 0f
        var prevMidY = 0f
        var hasPrevMid = false
        stroke.points.forEachIndexed { i, p ->
            val x = px(p[0])
            val y = py(p[1])
            if (i == 0) {
                path.moveTo(x, y)
            } else {
                val midX = (lastX + x) / 2f
                val midY = (lastY + y) / 2f
                if (!hasPrevMid) {
                    path.quadTo(lastX, lastY, midX, midY)
                } else {
                    path.quadTo(lastX, lastY, midX, midY)
                }
                prevMidX = midX
                prevMidY = midY
                hasPrevMid = true
            }
            lastX = x
            lastY = y
        }
        if (stroke.points.size >= 2) {
            path.lineTo(lastX, lastY)
        }
        return path
    }

    private fun paintFor(stroke: Stroke): Paint {
        val key = "${stroke.id}|${stroke.tool}|${stroke.color}|${stroke.width}"
        paintCache[key]?.let { return it }
        val isMarker = stroke.tool == "marker"
        val base = canvasRect.width() / 120f * stroke.width
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeJoin = Paint.Join.ROUND
            strokeCap = Paint.Cap.ROUND
            color = parseColor(stroke.color)
            strokeWidth = if (isMarker) base * 1.8f else base
            alpha = if (isMarker) 128 else 255 // 荧光笔半透明
        }
        if (paintCache.size > 64) paintCache.clear()
        paintCache[key] = paint
        return paint
    }

    private fun parseColor(color: String): Int = try {
        Color.parseColor(color)
    } catch (_: Exception) {
        Color.parseColor("#2B2B2E")
    }

    private fun px(nx: Double): Float = canvasRect.left + nx.toFloat() * canvasRect.width()
    private fun py(ny: Double): Float = canvasRect.top + ny.toFloat() * canvasRect.height()
}
