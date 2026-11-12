import SwiftUI
import AVFoundation

/// 扫码页：AVCaptureMetadataOutput 捕获 QR，解析 suishouhua://<host>:<port>?code=<code>。
struct ScanView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = QRScanner()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
                Spacer()
                Text("扫码配对")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Color.clear.frame(width: 24, height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ZStack {
                ScannerPreview(scanner: scanner)
                    .ignoresSafeArea(edges: .bottom)
                // 取景框
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.blue, lineWidth: 3)
                    .frame(width: 240, height: 240)
                    .background(Color.white.opacity(0.06))
                if let error = scanner.errorText {
                    VStack(spacing: 12) {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Button("输入电视地址") {
                            dismiss()
                            model.screen = .manual
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("将电视二维码放入框内")
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(.white)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear { scanner.start(onResult: handleScanResult) }
        .onDisappear { scanner.stop() }
        .onReceive(model.$state) { state in
            if case .rejected(let reason) = state {
                scanner.errorText = AppModel.failureText(for: reason)
                scanner.restart()
            } else if case .failed(let text) = state {
                scanner.errorText = text
                scanner.restart()
            }
        }
    }

    private func handleScanResult(_ payload: String) {
        guard let (host, port) = Self.parseTargetURL(payload) else { return }
        // paired 后由 AppModel 导航到画布；失败留在本页显示错误
        model.connect(host: host, port: port)
    }

    /// 解析二维码 URL，提取电视 host（兼容新旧格式，忽略 query）：
    /// 新：`http://<ip>:<port>/draw`；旧：`suishouhua://<ip>:<port>?code=...`
    static func parseTargetURL(_ string: String) -> (host: String, port: Int)? {
        guard let url = URLComponents(string: string) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" || scheme == "suishouhua",
              let host = url.host, !host.isEmpty else { return nil }
        let port = url.port ?? 9723
        return (host, port)
    }
}

// MARK: - 相机封装

final class QRScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var errorText: String?
    private let session = AVCaptureSession()
    private var running = false
    private var onResult: ((String) -> Void)?
    private var lastPayload: String?
    private var lastHitAt: Date?

    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        AVCaptureVideoPreviewLayer(session: session)
    }()

    func start(onResult: @escaping (String) -> Void) {
        self.onResult = onResult
        guard !running else { return }
        if session.inputs.isEmpty {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                errorText = "相机不可用，可使用「输入电视地址」连接"
                return
            }
            session.beginConfiguration()
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }
            session.commitConfiguration()
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.session.startRunning()
            self.running = true
        }
    }

    func stop() {
        guard running else { return }
        session.stopRunning()
        running = false
    }

    func restart() {
        lastPayload = nil
        guard running else { return }
        session.stopRunning()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
            .first(where: { $0.type == .qr && $0.stringValue != nil }),
              let payload = object.stringValue else { return }
        // 防重复触发：同一内容 2 秒内只处理一次
        if payload == lastPayload, let last = lastHitAt, Date().timeIntervalSince(last) < 2 { return }
        lastPayload = payload
        lastHitAt = Date()
        onResult?(payload)
    }
}

struct ScannerPreview: UIViewRepresentable {
    @ObservedObject var scanner: QRScanner

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        scanner.previewLayer.videoGravity = .resizeAspectFill
        scanner.previewLayer.frame = view.bounds
        view.layer.addSublayer(scanner.previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scanner.previewLayer.frame = uiView.bounds
        CATransaction.commit()
    }
}
