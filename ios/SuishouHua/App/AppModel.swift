import Foundation
import SwiftUI
import UIKit

/// 连接与全局导航编排：配对、心跳、断线重连（5 分钟内指数退避）、history 恢复。
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case home
        case scan
        case manual
        case canvas
    }

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case reconnecting        // 曾成功配对，断线自动重连中
        case rejected(RejectionReason)
        case failed(String)      // 连接失败文案
    }

    @Published var screen: Screen = .home
    @Published var state: ConnectionState = .idle
    @Published var toast: String?

    let engine = DrawingEngine()
    let connection = TVConnection()

    // 连接目标（重连复用）
    private(set) var host: String?
    private(set) var port: Int = 9723
    private var hasEverPaired = false

    // 重连
    private var disconnectDate: Date?
    private var reconnectAttempt = 0
    private var reconnectTimer: Timer?
    private static let reconnectWindow: TimeInterval = 5 * 60
    private static let maxBackoff: TimeInterval = 30

    // 心跳
    private var pingTimer: Timer?

    init() {
        engine.sendMessage = { [weak self] message in
            self?.connection.send(message.encoded ?? "")
        }
        connection.onEvent = { [weak self] event in
            self?.handleConnectionEvent(event)
        }
    }

    // MARK: 配对入口

    /// 扫码 / 手动输入统一入口（协议无配对码，连接即用）。
    func connect(host: String, port: Int = 9723) {
        stopReconnect()
        self.host = host
        self.port = port
        hasEverPaired = false
        openSocket()
    }

    /// 配对失败原因 → 用户文案。
    static func failureText(for reason: RejectionReason) -> String {
        switch reason {
        case .inUse:
            return "电视已被其他手机连接"
        case .unknown:
            return unreachableText
        }
    }

    static let unreachableText = "无法连接到电视，请确认在同一 Wi-Fi"

    // MARK: 连接生命周期

    private func openSocket() {
        guard let host else { return }
        state = hasEverPaired ? .reconnecting : .connecting
        connection.open(host: host, port: port)
        // 连上即发 hello（协议要求首条消息，无字段）。
        pendingHello = true
    }

    private var pendingHello = false

    private func handleConnectionEvent(_ event: TVConnection.Event) {
        // TVConnection 回调在后台线程，统一切回主线程更新 @Published 状态
        DispatchQueue.main.async { [weak self] in
            self?.processConnectionEvent(event)
        }
    }

    private func processConnectionEvent(_ event: TVConnection.Event) {
        switch event {
        case .open:
            if pendingHello {
                pendingHello = false
                connection.send(OutgoingMessage.hello.encoded ?? "")
            }
            startPing()

        case .closed(let error):
            stopPing()
            handleDisconnect(error)

        case .text(let text):
            guard let message = IncomingMessage.decode(text) else { return }
            handleMessage(message)
        }
    }

    private func handleMessage(_ message: IncomingMessage) {
        switch message {
        case .paired:
            hasEverPaired = true
            reconnectAttempt = 0
            disconnectDate = nil
            stopReconnect()
            state = .connected
            screen = .canvas
            OrientationLock.set(.landscape)

        case .rejected(let reason):
            stopPing()
            stopReconnect()
            hasEverPaired = false
            state = .rejected(reason)
            if screen == .canvas {
                screen = .manual
                OrientationLock.set(.portrait)
            }

        case .pong:
            break

        case .unknown:
            break
        }
    }

    private func handleDisconnect(_ error: Error?) {
        pendingHello = false
        if case .connected = state {
            disconnectDate = Date()
            reconnectAttempt = 0
            state = .reconnecting
            scheduleReconnect()
        } else if case .reconnecting = state {
            scheduleReconnect()
        } else if case .rejected = state {
            // 已收到明确拒绝原因，保持该文案，不覆盖为网络错误
        } else {
            // 尚未配对成功就断开（首次连接失败）
            state = .failed(Self.unreachableText)
            if screen == .canvas { screen = .manual }
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        guard let disconnectDate, Date().timeIntervalSince(disconnectDate) < Self.reconnectWindow else {
            state = .failed(Self.unreachableText)
            return
        }
        let delay = min(Self.maxBackoff, pow(2, Double(reconnectAttempt)))
        reconnectAttempt += 1
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.openSocket()
        }
    }

    private func stopReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: 心跳

    private func startPing() {
        stopPing()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.connection.send(OutgoingMessage.ping.encoded ?? "")
        }
    }

    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    // MARK: 用户操作

    /// 主动断开并返回连接主页。
    func leaveCanvas() {
        stopReconnect()
        stopPing()
        connection.close()
        hasEverPaired = false
        state = .idle
        screen = .home
        OrientationLock.set(.portrait)
    }

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }
}
