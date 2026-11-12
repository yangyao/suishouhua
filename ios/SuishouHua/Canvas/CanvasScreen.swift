import SwiftUI
import Photos
import UIKit

/// 横屏绘图画布：顶栏（标题/连接状态/撤销/重做/清空/导出）+ 16:9 letterbox 画布 + 底部浮动工具栏。
struct CanvasScreen: View {
    @EnvironmentObject private var model: AppModel

    @State private var showClearConfirm = false
    @State private var showExportDenied = false

    var body: some View {
        // 三段结构、互不重叠：顶栏（safe area 之下一行）→ 画布（弹性占满中间，
        // 16:9 letterbox 居中，内部无任何 UI，即电视屏幕的完整镜像）→ 工具栏（下方独立一行）
        VStack(spacing: 0) {
            TopBar(
                engine: model.engine,
                connected: isConnected,
                onUndo: { model.engine.undo() },
                onRedo: { model.engine.redo() },
                onClear: { showClearConfirm = true },
                onExport: { exportCanvas() },
                onLeave: { model.leaveCanvas() }
            )
            GeometryReader { geo in
                let frame = CanvasGeometry.letterboxFrame(
                    contentAspect: 16.0 / 9.0,
                    in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 8, dy: 6))
                CanvasRepresentable(engine: model.engine)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            }
            ToolBar(engine: model.engine)
                .padding(.vertical, 6)
        }
        .background(Theme.background.ignoresSafeArea())
        .alert("清空画板？", isPresented: $showClearConfirm) {
            Button("清空", role: .destructive) { model.engine.clearAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空后将同时清空电视上的画布")
        }
        .alert("无法保存到相册", isPresented: $showExportDenied) {
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请在系统设置中允许「随手画」访问相册")
        }
        .overlay(alignment: .center) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
            }
        }
    }

    private var isConnected: Bool {
        if case .connected = model.state { return true }
        return false
    }

    private func exportCanvas() {
        guard let image = CanvasExporter.renderCurrent() else { return }
        PhotoSaver.shared.save(image) { granted in
            DispatchQueue.main.async {
                if granted {
                    model.showToast("已保存到相册")
                } else {
                    showExportDenied = true
                }
            }
        }
    }
}

/// 画布持有者：让 Toolbar/Export 等访问同一个 engine 实例。
struct CanvasRepresentable: UIViewRepresentable {
    @ObservedObject var engine: DrawingEngine

    func makeUIView(context: Context) -> CanvasUIView {
        let view = CanvasUIView()
        CanvasUIView.registerCurrent(view)
        view.engine = engine
        return view
    }

    func updateUIView(_ view: CanvasUIView, context: Context) {
        view.engine = engine
        view.syncStrokes(engine.strokes)
    }
}

// MARK: - 顶栏

struct TopBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var engine: DrawingEngine
    let connected: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onClear: () -> Void
    let onExport: () -> Void
    let onLeave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Text("随手画")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                statusView
            }
            Spacer()
            if connected == false {
                Button("返回连接页", action: onLeave)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.blue)
            }
            button(Image(systemName: "arrow.uturn.backward"), enabled: engine.canUndo, action: onUndo)
                .font(.system(size: 16))
            button(Image(systemName: "arrow.uturn.forward"), enabled: engine.canRedo, action: onRedo)
                .font(.system(size: 16))
            button(Image(systemName: "trash"), enabled: true, action: onClear)
                .font(.system(size: 16))
            button(Image(systemName: "square.and.arrow.up"), enabled: true, action: onExport)
                .font(.system(size: 16))
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    @ViewBuilder private var statusView: some View {
        if connected {
            HStack(spacing: 5) {
                Circle().fill(Theme.green).frame(width: 8, height: 8)
                Text("已连接电视").font(.system(size: 13)).foregroundStyle(Theme.inkSecondary)
            }
        } else if case .connecting = model.state {
            HStack(spacing: 5) {
                Circle().fill(Theme.orange).frame(width: 8, height: 8)
                Text("正在连接电视…").font(.system(size: 13)).foregroundStyle(Theme.inkSecondary)
            }
        } else {
            HStack(spacing: 5) {
                Circle().fill(Theme.orange).frame(width: 8, height: 8)
                Text("连接已断开，正在重连…").font(.system(size: 13)).foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func button(_ label: Image, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .foregroundStyle(enabled ? Theme.ink : Theme.inkSecondary.opacity(0.4))
        }
        .disabled(!enabled)
    }
}

// MARK: - 底部工具栏

struct ToolBar: View {
    @ObservedObject var engine: DrawingEngine

    var body: some View {
        HStack(spacing: 16) {
            toolButton("pencil.tip", tool: .pen)
            toolButton("highlighter", tool: .marker)
            eraserButton
            divider
            ForEach(Theme.strokePalette, id: \.self) { hex in
                ColorDot(hex: hex, selected: engine.colorHex == hex) {
                    engine.colorHex = hex
                }
            }
            divider
            ForEach([1, 2, 3], id: \.self) { level in
                WidthDot(level: level, selected: engine.widthLevel == level) {
                    engine.widthLevel = level
                }
            }
        }
        .padding(.horizontal, 18)
        .background(
            Capsule().fill(.white)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        )
    }

    private var divider: some View {
        Rectangle().fill(Theme.inkSecondary.opacity(0.25)).frame(width: 1, height: 26)
    }

    private func toolButton(_ symbol: String, tool: Tool) -> some View {
        Button {
            engine.tool = tool
            engine.isEraser = false
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(engine.tool == tool && !engine.isEraser ? Theme.blue : Theme.ink)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(engine.tool == tool && !engine.isEraser ? Theme.blue.opacity(0.14) : .clear)
                )
        }
    }

    private var eraserButton: some View {
        Button {
            engine.isEraser.toggle()
        } label: {
            Image(systemName: "eraser")
                .font(.system(size: 18))
                .foregroundStyle(engine.isEraser ? Theme.blue : Theme.ink)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(engine.isEraser ? Theme.blue.opacity(0.14) : .clear)
                )
        }
    }
}

struct ColorDot: View {
    let hex: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: hex) ?? .blue)
                .frame(width: selected ? 22 : 20, height: selected ? 22 : 20)
                .overlay(
                    Circle().stroke(selected ? Theme.blue : .clear, lineWidth: 2)
                        .padding(selected ? -4 : -3)
                )
        }
    }
}

struct WidthDot: View {
    let level: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(selected ? Theme.blue : Theme.ink.opacity(0.55))
                .frame(width: dotSize, height: dotSize)
                .padding(selected ? 3 : 0)
                .overlay(
                    Circle().stroke(selected ? Theme.blue : .clear, lineWidth: 1.5)
                        .padding(-3)
                )
        }
    }

    private var dotSize: CGFloat {
        [6, 10, 15][level - 1]
    }
}

// MARK: - 相册保存

final class PhotoSaver: NSObject {
    static let shared = PhotoSaver()
    private var completion: ((Bool) -> Void)?

    func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc func image(_ image: UIImage,
                     didFinishSavingWithError error: Error?,
                     contextInfo: UnsafeRawPointer) {
        let granted = error == nil
        completion?(granted)
        completion = nil
    }
}
