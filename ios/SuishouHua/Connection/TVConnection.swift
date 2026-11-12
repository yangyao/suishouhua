import Foundation

/// WebSocket 客户端：URLSessionWebSocketTask，收到文本帧转成事件回调。
/// ping 心跳与重连策略由 AppModel 编排，这里只负责连接与收发。
final class TVConnection: NSObject {
    enum Event {
        case open                       // socket 建立
        case closed(error: Error?)      // 断开（含服务器关闭）
        case text(String)               // 收到一帧文本
    }

    var onEvent: ((Event) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private(set) var isOpen = false

    // MARK: 连接

    func open(host: String, port: Int) {
        close()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        guard let url = URL(string: "ws://\(host):\(port)/ws") else {
            onEvent?(.closed(error: nil))
            return
        }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop(task)
    }

    /// 用户主动断开，不触发 closed 之外的副作用。
    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        isOpen = false
    }

    func send(_ string: String, completion: ((Error?) -> Void)? = nil) {
        guard let task else { completion?(TVError.notConnected); return }
        task.send(.string(string)) { error in
            completion?(error)
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, task === self.task else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.onEvent?(.text(text))
                }
                self.receiveLoop(task)
            case .failure(let error):
                if task === self.task {
                    self.isOpen = false
                    self.onEvent?(.closed(error: error))
                }
            }
        }
    }

    enum TVError: Error {
        case notConnected
    }
}

extension TVConnection: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        guard task === self.task else { return }
        isOpen = true
        onEvent?(.open)
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        guard task === self.task else { return }
        isOpen = false
        onEvent?(.closed(error: nil))
    }
}
