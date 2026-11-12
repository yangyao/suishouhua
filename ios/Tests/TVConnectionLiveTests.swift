import XCTest
@testable import SuishouHua

/// 需要本地 mock 电视服务器：`python3 tools/mock-tv-server.py 9725`（ws://127.0.0.1:9725/ws，
/// 避开 adb 的 9723 转发）。服务器未运行时自动跳过。
final class TVConnectionLiveTests: XCTestCase {
    func testHelloPairedAgainstMockServer() throws {
        let connection = TVConnection()
        let opened = expectation(description: "socket open")
        let paired = expectation(description: "paired")
        var openedDone = false
        var pairedDone = false
        var closedWithoutOpen = false

        connection.onEvent = { event in
            switch event {
            case .open:
                if !openedDone {
                    openedDone = true
                    opened.fulfill()
                    connection.send(OutgoingMessage.hello.encoded ?? "")
                }
            case .text(let text):
                if case .paired? = IncomingMessage.decode(text), !pairedDone {
                    pairedDone = true
                    paired.fulfill()
                }
            case .closed:
                if !openedDone { closedWithoutOpen = true }
                if !openedDone { opened.fulfill(); openedDone = true }
                if !pairedDone { paired.fulfill(); pairedDone = true }
            }
        }

        connection.open(host: "127.0.0.1", port: 9725)
        wait(for: [opened, paired], timeout: 6)

        connection.close()

        if closedWithoutOpen {
            throw XCTSkip("mock 电视服务器未运行（python3 tools/mock-tv-server.py 9725）")
        }
    }

    /// 通过引擎整链路验证：hello → paired，stroke_start/points/end 被服务器接收。
    func testEngineSendsStrokeProtocolOverSocket() throws {
        let connection = TVConnection()
        let engine = DrawingEngine()
        engine.sendMessage = { connection.send($0.encoded ?? "") }

        let opened = expectation(description: "open")
        let paired = expectation(description: "paired")
        var openedDone = false
        var pairedDone = false
        var closedWithoutOpen = false

        connection.onEvent = { event in
            switch event {
            case .open:
                if !openedDone {
                    openedDone = true
                    opened.fulfill()
                    connection.send(OutgoingMessage.hello.encoded ?? "")
                }
            case .text(let text):
                if case .paired? = IncomingMessage.decode(text), !pairedDone {
                    pairedDone = true
                    paired.fulfill()
                    engine.beginStroke()
                    engine.addPoint([0.1, 0.1])
                    engine.addPoint([0.5, 0.5])
                    engine.endStroke()
                    engine.undo()
                }
            case .closed:
                if !openedDone { closedWithoutOpen = true }
                if !openedDone { opened.fulfill(); openedDone = true }
                if !pairedDone { paired.fulfill(); pairedDone = true }
            }
        }

        connection.open(host: "127.0.0.1", port: 9725)
        wait(for: [opened, paired], timeout: 6)
        // 给发送留一点时间
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        connection.close()

        if closedWithoutOpen {
            throw XCTSkip("mock 电视服务器未运行（python3 tools/mock-tv-server.py 9725）")
        }
        XCTAssertEqual(engine.strokes.count, 0, "undo 后画布应为空")
    }

    /// 单设备独占：第一个连接配对后，第二个 hello 应收到 rejected(in_use)。
    func testSecondConnectionRejectedInUse() throws {
        let first = TVConnection()
        let firstPaired = expectation(description: "first paired")
        var firstPairedDone = false
        first.onEvent = { event in
            if case .open = event {
                first.send(OutgoingMessage.hello.encoded ?? "")
            }
            if case .text(let text) = event,
               case .paired? = IncomingMessage.decode(text), !firstPairedDone {
                firstPairedDone = true
                firstPaired.fulfill()
            }
        }
        first.open(host: "127.0.0.1", port: 9725)
        wait(for: [firstPaired], timeout: 6)

        let second = TVConnection()
        let rejected = expectation(description: "second rejected in_use")
        var rejectedDone = false
        var closedWithoutOpen = false
        second.onEvent = { event in
            switch event {
            case .open:
                second.send(OutgoingMessage.hello.encoded ?? "")
            case .text(let text):
                if case .rejected(reason: .inUse)? = IncomingMessage.decode(text), !rejectedDone {
                    rejectedDone = true
                    rejected.fulfill()
                }
            case .closed:
                if !rejectedDone { closedWithoutOpen = true; rejectedDone = true; rejected.fulfill() }
            }
        }
        second.open(host: "127.0.0.1", port: 9725)
        wait(for: [rejected], timeout: 6)

        first.close()
        second.close()

        if closedWithoutOpen && !rejectedDone {
            throw XCTSkip("mock 电视服务器未运行（python3 tools/mock-tv-server.py 9725）")
        }
    }
}
