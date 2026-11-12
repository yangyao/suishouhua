import Foundation

// MARK: - 共享模型（docs/protocol.md）

/// 笔画工具：画笔 / 荧光笔
enum Tool: String, Codable, Equatable, CaseIterable {
    case pen
    case marker
}

/// 一条笔画。points 为 0–1 归一化坐标 [[x, y], ...]，以 16:9 画布左上角为原点。
struct Stroke: Codable, Equatable, Identifiable {
    let id: String
    var tool: Tool
    var color: String   // #RRGGBB
    var width: Int      // 1/2/3（细/中/粗）
    var points: [[Double]]
}

// MARK: - phone → tv

enum OutgoingMessage: Equatable {
    case hello
    case strokeStart(id: String, tool: Tool, color: String, width: Int)
    case strokePoints(id: String, points: [[Double]])
    case strokeEnd(id: String)
    case erase(strokeId: String)
    case undo
    case redo
    case clear
    case ping

    var encoded: String? {
        let obj: [String: Any]
        switch self {
        case .hello:
            obj = ["type": "hello"]
        case .strokeStart(let id, let tool, let color, let width):
            obj = ["type": "stroke_start", "id": id, "tool": tool.rawValue,
                   "color": color, "width": width]
        case .strokePoints(let id, let points):
            obj = ["type": "stroke_points", "id": id, "points": points]
        case .strokeEnd(let id):
            obj = ["type": "stroke_end", "id": id]
        case .erase(let strokeId):
            obj = ["type": "erase", "strokeId": strokeId]
        case .undo:
            obj = ["type": "undo"]
        case .redo:
            obj = ["type": "redo"]
        case .clear:
            obj = ["type": "clear"]
        case .ping:
            obj = ["type": "ping"]
        }
        guard JSONSerialization.isValidJSONObject(obj) else { return nil }
        let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }
}

// MARK: - tv → phone

enum RejectionReason: String {
    case inUse = "in_use"
    case unknown
}

enum IncomingMessage: Equatable {
    case paired(canvasAspect: Double?)
    case rejected(reason: RejectionReason)
    case pong
    case unknown

    /// 解析一帧 tv → phone JSON。未知 type 按协议静默忽略（返回 .unknown）。
    static func decode(_ text: String) -> IncomingMessage? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any],
              let type = dict["type"] as? String else { return nil }
        switch type {
        case "paired":
            let aspect = dict["canvasAspect"] as? Double
            return .paired(canvasAspect: aspect)
        case "rejected":
            let raw = dict["reason"] as? String ?? ""
            let reason = RejectionReason(rawValue: raw) ?? .unknown
            return .rejected(reason: reason)
        case "history":
            // v1 预留消息，当前应静默忽略
            return .unknown
        case "pong":
            return .pong
        default:
            return .unknown
        }
    }
}
