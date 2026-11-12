import SwiftUI

/// 手动输入电视 IP 连接（协议无配对码，支持 `host:port` 写法便于本地联调）。
struct ManualPairView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var isConnecting = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section("电视地址") {
                    TextField("例如 192.168.2.211", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button {
                        connectTapped()
                    } label: {
                        if isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("连接")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(canSubmit ? Theme.blue : Theme.blue.opacity(0.4),
                                            in: Capsule())
                        }
                    }
                    .disabled(!canSubmit || isConnecting)
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(isConnecting)
        .onAppear { reconcile(model.state) }
        .onReceive(model.$state) { reconcile($0) }
    }

    private var canSubmit: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.blue)
            }
            Spacer()
            Text("输入电视地址")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Color.clear.frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func reconcile(_ state: AppModel.ConnectionState) {
        switch state {
        case .rejected(let reason):
            isConnecting = false
            errorText = AppModel.failureText(for: reason)
        case .failed(let text):
            isConnecting = false
            errorText = text
        case .connected:
            isConnecting = false
            errorText = nil
        default:
            break
        }
    }

    private func connectTapped() {
        let cleanHost = host.trimmingCharacters(in: .whitespaces)
        guard let (ip, port) = parseHost(cleanHost) else {
            errorText = "电视地址无效"
            return
        }
        errorText = nil
        isConnecting = true
        // 保持在本页等待结果：paired 由 AppModel 导航到画布；
        // rejected/failed 由上方 reconcile 显示错误文案。
        model.connect(host: ip, port: port)
    }

    /// 支持 "192.168.2.211" 或 "192.168.2.211:9723"（便于本地联调）。
    private func parseHost(_ text: String) -> (String, Int)? {
        let parts = text.split(separator: ":").map(String.init)
        switch parts.count {
        case 1:
            return (parts[0], 9723)
        case 2:
            guard let port = Int(parts[1]) else { return nil }
            return (parts[0], port)
        default:
            return nil
        }
    }
}
