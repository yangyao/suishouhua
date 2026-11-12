import UIKit

/// 触摸捕获 + 分层渲染的画布视图（UIViewRepresentable 包装）。
/// - 完成笔画：每条 stroke 一个 CAShapeLayer
/// - 绘制中笔画：单独 activeLayer 实时更新
/// - 坐标存储为 0–1 归一化（16:9 画布），渲染时映射到 bounds，不拉伸不裁切
final class CanvasUIView: UIView {
    var engine: DrawingEngine?

    static private(set) weak var current: CanvasUIView?

    static func registerCurrent(_ view: CanvasUIView?) { current = view }

    private var layersByID: [String: CAShapeLayer] = [:]
    private var activeLayer: CAShapeLayer?

    // 擦除手势状态
    private var isErasing = false

    // 工具渲染参数
    static let penWidths: [CGFloat] = [4, 8, 14]
    static let eraserHitRadius: CGFloat = 18

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .white
        isMultipleTouchEnabled = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildAll()
    }

    // MARK: SwiftUI 同步

    /// 引擎 strokes 变化时调用（绘制完成 / undo / redo / erase / history / clear）。
    func syncStrokes(_ strokes: [Stroke]) {
        let ids = Set(strokes.map(\.id))
        for (id, layer) in layersByID where !ids.contains(id) {
            layer.removeFromSuperlayer()
            layersByID.removeValue(forKey: id)
        }
        for stroke in strokes where layersByID[stroke.id] == nil {
            let layer = makeLayer(for: stroke)
            layersByID[stroke.id] = layer
            self.layer.addSublayer(layer)
        }
    }

    private func rebuildAll() {
        layersByID.values.forEach { $0.removeFromSuperlayer() }
        layersByID.removeAll()
        activeLayer?.removeFromSuperlayer()
        activeLayer = nil
        guard let engine else { return }
        for stroke in engine.strokes {
            let layer = makeLayer(for: stroke)
            layersByID[stroke.id] = layer
            self.layer.addSublayer(layer)
        }
        if let active = engine.activeStroke {
            setActiveStroke(active)
        }
    }

    private func makeLayer(for stroke: Stroke) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path(for: stroke).cgPath
        layer.strokeColor = UIColor(hex: stroke.color)?.cgColor
        layer.fillColor = nil
        layer.lineWidth = Self.lineWidth(for: stroke, in: bounds)
        layer.lineCap = .round
        layer.lineJoin = .round
        if stroke.tool == .marker {
            layer.opacity = 0.45
        }
        return layer
    }

    static func lineWidth(for stroke: Stroke, in bounds: CGRect) -> CGFloat {
        let base = penWidths[min(max(stroke.width, 1), 3) - 1]
        // 归一化画布下按视图宽度轻度缩放，保证不同屏幕手感一致
        let scale = bounds.width > 0 ? max(0.8, min(bounds.width / 900, 1.6)) : 1
        let width = base * scale
        return stroke.tool == .marker ? width * 2.2 : width
    }

    /// 贝塞尔平滑：相邻点取中点做二次曲线。
    private func path(for stroke: Stroke) -> UIBezierPath {
        let pts = stroke.points.map { CanvasGeometry.denormalize($0, in: bounds) }
        let path = UIBezierPath()
        guard !pts.isEmpty else { return path }
        if pts.count == 1 {
            // 点按：画一个圆点
            let r = Self.lineWidth(for: stroke, in: bounds) / 2
            path.addArc(withCenter: pts[0], radius: max(r, 1), startAngle: 0,
                        endAngle: .pi * 2, clockwise: true)
            return path
        }
        path.move(to: pts[0])
        if pts.count == 2 {
            path.addLine(to: pts[1])
            return path
        }
        for i in 1..<pts.count - 1 {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                              y: (pts[i].y + pts[i + 1].y) / 2)
            path.addQuadCurve(to: mid, controlPoint: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    // MARK: 触摸

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let engine, let touch = touches.first, activeLayer == nil, !isErasing else { return }
        let point = touch.location(in: self)
        guard bounds.insetBy(dx: -8, dy: -8).contains(point) else { return }
        if engine.isEraser {
            // 橡皮擦
            isErasing = true
            engine.beginErase()
            eraseHit(at: point)
        } else {
            engine.beginStroke()
            engine.addPoint(CanvasGeometry.normalize(point, in: bounds))
            setActiveStroke(engine.activeStroke)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let engine, let touch = touches.first else { return }
        let point = touch.location(in: self)
        if activeLayer != nil {
            engine.addPoint(CanvasGeometry.normalize(point, in: bounds))
            updateActiveLayer()
        } else if isErasing {
            eraseHit(at: point)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishGesture()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishGesture()
    }

    private func finishGesture() {
        guard let engine else { return }
        if activeLayer != nil {
            engine.endStroke()
            activeLayer?.removeFromSuperlayer()
            activeLayer = nil
            syncStrokes(engine.strokes)
        } else if isErasing {
            isErasing = false
            engine.endErase()
        }
    }

    /// 橡皮擦：删除被触碰的整条笔画。
    private func eraseHit(at point: CGPoint) {
        guard let engine else { return }
        for stroke in engine.strokes {
            let path = self.path(for: stroke)
            let radius = Self.eraserHitRadius
            if path.contains(point)
                || stroke.points.map({ CanvasGeometry.denormalize($0, in: bounds) })
                    .contains(where: { hypot($0.x - point.x, $0.y - point.y) <= radius }) {
                layersByID[stroke.id]?.removeFromSuperlayer()
                layersByID.removeValue(forKey: stroke.id)
                engine.eraseStroke(id: stroke.id)
            }
        }
    }

    private func setActiveStroke(_ stroke: Stroke?) {
        activeLayer?.removeFromSuperlayer()
        activeLayer = nil
        guard let stroke else { return }
        let layer = makeLayer(for: stroke)
        activeLayer = layer
        self.layer.addSublayer(layer)
    }

    private func updateActiveLayer() {
        guard let engine, let stroke = engine.activeStroke else { return }
        activeLayer?.path = path(for: stroke).cgPath
    }
}

/// 导出：把当前画布渲染为 UIImage。
enum CanvasExporter {
    static func renderCurrent() -> UIImage? {
        guard let view = CanvasUIView.current, view.bounds.size.width > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
        return renderer.image { _ in
            view.backgroundColor.flatMap { color in
                color.setFill()
                UIRectFill(view.bounds)
            }
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }
}
