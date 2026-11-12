import Foundation
import CoreGraphics

/// 画布几何：归一化坐标（0–1，16:9 画布）与视图坐标互转、letterbox 布局。
enum CanvasGeometry {
    /// 视图坐标 → 归一化坐标，结果 clamp 到 0–1。
    static func normalize(_ point: CGPoint, in bounds: CGRect) -> [Double] {
        guard bounds.width > 0, bounds.height > 0 else { return [0, 0] }
        let x = min(1.0, max(0.0, (point.x - bounds.minX) / bounds.width))
        let y = min(1.0, max(0.0, (point.y - bounds.minY) / bounds.height))
        return [x, y]
    }

    /// 归一化坐标 → 视图坐标。
    static func denormalize(_ point: [Double], in bounds: CGRect) -> CGPoint {
        let x = bounds.minX + CGFloat(point.first ?? 0) * bounds.width
        let y = bounds.minY + CGFloat(point.count > 1 ? point[1] : 0) * bounds.height
        return CGPoint(x: x, y: y)
    }

    /// 在容器内按内容宽高比 letterbox 居中放置，不拉伸不裁切。
    static func letterboxFrame(contentAspect: CGFloat, in container: CGRect) -> CGRect {
        guard contentAspect > 0, container.width > 0, container.height > 0 else {
            return container
        }
        var size = container.size
        let containerAspect = container.width / container.height
        if containerAspect > contentAspect {
            size.width = size.height * contentAspect
        } else {
            size.height = size.width / contentAspect
        }
        return CGRect(x: container.midX - size.width / 2,
                      y: container.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

// MARK: - 撤销栈操作

/// 一次可撤销操作：新笔画 / 按笔画擦除 / 清空。
enum Operation: Equatable {
    case addStroke(Stroke)
    /// 记录被擦除笔画的原索引与内容，undo 时按原位置恢复。
    case eraseStrokes([(index: Int, stroke: Stroke)])
    /// 记录清空前的全部笔画。
    case clearCanvas([Stroke])
}

// MARK: - 绘图引擎

/// 笔画序列 + 撤销/重做栈 + 16ms 批量发送。所有画布操作的唯一数据源。
final class DrawingEngine: ObservableObject {
    /// 当前可见笔画（按时间顺序）。
    @Published private(set) var strokes: [Stroke] = []
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// 正在绘制中的笔画（收笔后进入 strokes）。
    @Published private(set) var activeStroke: Stroke?

    // 工具状态
    @Published var tool: Tool = .pen
    @Published var colorHex = "#3577F2"
    @Published var widthLevel = 2   // 1/2/3
    @Published var isEraser = false // 橡皮擦模式（与 pen/marker 互斥）

    /// 发送通道由外部注入（TVConnection / 测试桩）。
    var sendMessage: ((OutgoingMessage) -> Void)?

    private var undoStack: [Operation] = []
    private var redoStack: [Operation] = []

    // 16ms 批量发送
    private var pendingPoints: [[Double]] = []
    private var flushTimer: Timer?

    // MARK: 绘制

    func beginStroke() {
        guard activeStroke == nil else { return }
        let id = UUID().uuidString
        activeStroke = Stroke(id: id, tool: tool, color: colorHex,
                              width: widthLevel, points: [])
        sendMessage?(.strokeStart(id: id, tool: tool, color: colorHex, width: widthLevel))
        startFlush()
    }

    /// 追加一个归一化坐标点 [x, y]。
    func addPoint(_ point: [Double]) {
        guard activeStroke != nil else { return }
        activeStroke?.points.append(point)
        pendingPoints.append(point)
    }

    func endStroke() {
        guard let stroke = activeStroke else { return }
        flush()
        stopFlush()
        activeStroke = nil
        strokes.append(stroke)
        commit(.addStroke(stroke))
        sendMessage?(.strokeEnd(id: stroke.id))
    }

    // MARK: 擦除（按笔画）

    private var pendingErase: [(Int, Stroke)] = []

    func beginErase() {
        pendingErase = []
    }

    /// 擦除指定笔画（一次擦除手势内可多次调用，收手时作为单个撤销操作提交）。
    func eraseStroke(id: String) {
        guard !pendingErase.contains(where: { $0.1.id == id }),
              let idx = strokes.firstIndex(where: { $0.id == id }) else { return }
        pendingErase.append((idx, strokes[idx]))
        strokes.remove(at: idx)
        sendMessage?(.erase(strokeId: id))
    }

    func endErase() {
        guard !pendingErase.isEmpty else { return }
        let ops = pendingErase.map { (index: $0.0, stroke: $0.1) }
        pendingErase = []
        commit(.eraseStrokes(ops))
    }

    // MARK: 清空

    func clearAll() {
        guard !strokes.isEmpty else { return }
        let previous = strokes
        strokes = []
        commit(.clearCanvas(previous))
        sendMessage?(.clear)
    }

    // MARK: 撤销 / 重做

    func undo() {
        guard let op = undoStack.popLast() else { return }
        revert(op)
        redoStack.append(op)
        updateFlags()
        sendMessage?(.undo)
    }

    func redo() {
        guard let op = redoStack.popLast() else { return }
        apply(op)
        undoStack.append(op)
        updateFlags()
        sendMessage?(.redo)
    }

    /// 收到电视 history 时整体恢复（重连场景），撤销栈重置。
    func applyHistory(_ history: [Stroke]) {
        strokes = history
        activeStroke = nil
        undoStack = []
        redoStack = []
        pendingPoints = []
        pendingErase = []
        stopFlush()
        updateFlags()
    }

    /// 供测试与内部使用：直接构造栈内容。
    private func commit(_ op: Operation) {
        undoStack.append(op)
        redoStack.removeAll()
        updateFlags()
    }

    private func apply(_ op: Operation) {
        switch op {
        case .addStroke(let s):
            strokes.append(s)
        case .eraseStrokes(let removed):
            let ids = Set(removed.map { $0.stroke.id })
            strokes.removeAll(where: { ids.contains($0.id) })
        case .clearCanvas:
            strokes = []
        }
    }

    private func revert(_ op: Operation) {
        switch op {
        case .addStroke(let s):
            if let idx = strokes.lastIndex(where: { $0.id == s.id }) {
                strokes.remove(at: idx)
            }
        case .eraseStrokes(let removed):
            for (idx, stroke) in removed.sorted(by: { $0.index < $1.index }) {
                let at = min(idx, strokes.count)
                strokes.insert(stroke, at: at)
            }
        case .clearCanvas(let previous):
            strokes = previous
        }
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: 16ms 批量发送

    private func startFlush() {
        stopFlush()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    private func stopFlush() {
        flushTimer?.invalidate()
        flushTimer = nil
    }

    func flush() {
        guard let id = activeStroke?.id, !pendingPoints.isEmpty else { return }
        let points = pendingPoints
        pendingPoints = []
        sendMessage?(.strokePoints(id: id, points: points))
    }

    /// 当前是否有交互手势进行中（绘制或擦除）。
    var isGestureActive: Bool {
        activeStroke != nil || !pendingErase.isEmpty
    }
}

func ==(lhs: Operation, rhs: Operation) -> Bool {
    switch (lhs, rhs) {
    case (.addStroke(let a), .addStroke(let b)): return a == b
    case (.eraseStrokes(let a), .eraseStrokes(let b)):
        return a.map { $0.index } == b.map { $0.index } && a.map { $0.stroke } == b.map { $0.stroke }
    case (.clearCanvas(let a), .clearCanvas(let b)): return a == b
    default: return false
    }
}
