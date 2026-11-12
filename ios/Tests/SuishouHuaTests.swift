import XCTest
@testable import SuishouHua

final class DrawingEngineTests: XCTestCase {
    private func makeStroke(_ id: String, points: [[Double]] = [[0.1, 0.1], [0.5, 0.5]]) -> Stroke {
        Stroke(id: id, tool: .pen, color: "#3577F2", width: 2, points: points)
    }

    func testAddStrokeUndoRedo() {
        let engine = DrawingEngine()
        var sent: [OutgoingMessage] = []
        engine.sendMessage = { sent.append($0) }

        engine.beginStroke()
        engine.addPoint([0.1, 0.2])
        engine.addPoint([0.3, 0.4])
        engine.endStroke()

        XCTAssertEqual(engine.strokes.count, 1)
        XCTAssertTrue(engine.canUndo)
        XCTAssertFalse(engine.canRedo)
        XCTAssertEqual(engine.strokes[0].points.count, 2)

        engine.undo()
        XCTAssertTrue(engine.strokes.isEmpty)
        XCTAssertFalse(engine.canUndo)
        XCTAssertTrue(engine.canRedo)

        engine.redo()
        XCTAssertEqual(engine.strokes.count, 1)
        XCTAssertTrue(engine.canUndo)
        XCTAssertFalse(engine.canRedo)

        XCTAssertTrue(sent.contains(.undo))
        XCTAssertTrue(sent.contains(.redo))
        XCTAssertTrue(sent.contains(.strokeEnd(id: engine.strokes[0].id)))
    }

    func testRedoClearedByNewOperation() {
        let engine = DrawingEngine()
        engine.beginStroke(); engine.endStroke()
        engine.undo()
        XCTAssertTrue(engine.canRedo)
        engine.beginStroke(); engine.endStroke()
        XCTAssertFalse(engine.canRedo, "新操作应清空重做栈")
        XCTAssertEqual(engine.strokes.count, 1)
    }

    func testEraseStrokeUndo() {
        let engine = DrawingEngine()
        var sent: [OutgoingMessage] = []
        engine.sendMessage = { sent.append($0) }

        engine.beginStroke(); engine.endStroke()
        let id = engine.strokes[0].id

        engine.beginErase()
        engine.eraseStroke(id: id)
        XCTAssertTrue(engine.strokes.isEmpty)
        engine.endErase()

        XCTAssertTrue(sent.contains(.erase(strokeId: id)))
        XCTAssertTrue(engine.canUndo)

        engine.undo()
        XCTAssertEqual(engine.strokes.count, 1)
        XCTAssertEqual(engine.strokes[0].id, id)

        engine.redo()
        XCTAssertTrue(engine.strokes.isEmpty)
    }

    func testEraseMultipleStrokesIsSingleOperation() {
        let engine = DrawingEngine()
        engine.beginStroke(); engine.endStroke()
        engine.beginStroke(); engine.endStroke()
        let ids = engine.strokes.map(\.id)

        engine.beginErase()
        engine.eraseStroke(id: ids[0])
        engine.eraseStroke(id: ids[1])
        engine.endErase()
        XCTAssertTrue(engine.strokes.isEmpty)

        engine.undo()
        XCTAssertEqual(engine.strokes.count, 2, "一次擦除手势应作为单个撤销操作恢复")
    }

    func testClearUndo() {
        let engine = DrawingEngine()
        var sent: [OutgoingMessage] = []
        engine.sendMessage = { sent.append($0) }

        engine.beginStroke(); engine.endStroke()
        let stroke = engine.strokes[0]
        engine.clearAll()
        XCTAssertTrue(engine.strokes.isEmpty)
        XCTAssertTrue(sent.contains(.clear))

        engine.undo()
        XCTAssertEqual(engine.strokes, [stroke])
        engine.redo()
        XCTAssertTrue(engine.strokes.isEmpty)
    }

    func testBatchFlushWithin16ms() {
        let engine = DrawingEngine()
        var batches: [OutgoingMessage] = []
        engine.sendMessage = { batches.append($0) }

        engine.beginStroke()
        engine.addPoint([0, 0])
        engine.addPoint([0.1, 0.1])

        let exp = expectation(description: "flush")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        // flush 定时器 16ms 触发，点已批量发出
        guard case .strokePoints(_, let points)? = batches.first(where: {
            if case .strokePoints = $0 { return true }
            return false
        }) else {
            return XCTFail("未发出 stroke_points")
        }
        XCTAssertEqual(points.count, 2)
    }

    func testApplyHistoryResetsStacks() {
        let engine = DrawingEngine()
        engine.applyHistory([makeStroke("a"), makeStroke("b")])
        XCTAssertEqual(engine.strokes.count, 2)
        XCTAssertFalse(engine.canUndo)
        XCTAssertFalse(engine.canRedo)
        engine.beginStroke(); engine.endStroke()
        XCTAssertTrue(engine.canUndo)
    }
}

final class CanvasGeometryTests: XCTestCase {
    func testNormalizeDenormalizeRoundTrip() {
        let bounds = CGRect(x: 100, y: 50, width: 800, height: 450)
        let point = CGPoint(x: 300, y: 125)
        let normalized = CanvasGeometry.normalize(point, in: bounds)
        XCTAssertEqual(normalized[0], 0.25, accuracy: 1e-9)
        XCTAssertEqual(normalized[1], 1.0 / 6.0, accuracy: 1e-9)
        let back = CanvasGeometry.denormalize(normalized, in: bounds)
        XCTAssertEqual(back, point)
    }

    func testNormalizeClamps() {
        let bounds = CGRect(x: 0, y: 0, width: 1600, height: 900)
        XCTAssertEqual(CanvasGeometry.normalize(CGPoint(x: -5, y: 950), in: bounds), [0, 1])
        XCTAssertEqual(CanvasGeometry.normalize(CGPoint(x: 1700, y: -1), in: bounds), [1, 0])
    }

    func testLetterboxWiderContainer() {
        // 容器更宽：以高度为准，左右留白
        let frame = CanvasGeometry.letterboxFrame(contentAspect: 16.0 / 9.0,
                                                  in: CGRect(x: 0, y: 0, width: 1000, height: 450))
        XCTAssertEqual(frame.height, 450)
        XCTAssertEqual(frame.width, 800, accuracy: 0.001)
        XCTAssertEqual(frame.minX, 100, accuracy: 0.001)
    }

    func testLetterboxTallerContainer() {
        let frame = CanvasGeometry.letterboxFrame(contentAspect: 16.0 / 9.0,
                                                  in: CGRect(x: 0, y: 0, width: 640, height: 500))
        XCTAssertEqual(frame.width, 640)
        XCTAssertEqual(frame.height, 360, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 70, accuracy: 0.001)
    }
}

final class ProtocolTests: XCTestCase {
    func testHelloEncoding() throws {
        let json = OutgoingMessage.hello.encoded
        XCTAssertNotNil(json)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json!.utf8)) as? [String: Any])
        XCTAssertEqual(obj["type"] as? String, "hello")
        XCTAssertNil(obj["code"], "协议已移除配对码，hello 不应携带 code 字段")
        XCTAssertEqual(obj.count, 1, "hello 应只有 type 字段")
    }

    func testStrokeStartEncoding() throws {
        let json = try XCTUnwrap(OutgoingMessage.strokeStart(id: "a1b2", tool: .marker,
                                                             color: "#F28C28", width: 2).encoded)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(obj["type"] as? String, "stroke_start")
        XCTAssertEqual(obj["id"] as? String, "a1b2")
        XCTAssertEqual(obj["tool"] as? String, "marker")
        XCTAssertEqual(obj["color"] as? String, "#F28C28")
        XCTAssertEqual(obj["width"] as? Int, 2)
    }

    func testStrokePointsEncoding() throws {
        let json = try XCTUnwrap(OutgoingMessage.strokePoints(id: "a1b2",
                                                              points: [[0.51, 0.32], [0.515, 0.325]]).encoded)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(obj["points"] as? [[Double]], [[0.51, 0.32], [0.515, 0.325]])
    }

    func testSimpleMessagesEncoding() throws {
        for (message, type) in [(OutgoingMessage.undo, "undo"),
                                (OutgoingMessage.redo, "redo"),
                                (OutgoingMessage.clear, "clear"),
                                (OutgoingMessage.ping, "ping")] {
            let json = try XCTUnwrap(message.encoded, "\(type) 应可编码")
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            XCTAssertEqual(obj["type"] as? String, type)
        }
        let erase = try XCTUnwrap(OutgoingMessage.erase(strokeId: "s1").encoded)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(erase.utf8)) as? [String: Any])
        XCTAssertEqual(obj["type"] as? String, "erase")
        XCTAssertEqual(obj["strokeId"] as? String, "s1")
    }

    func testPairedDecode() {
        let message = IncomingMessage.decode(#"{"type":"paired","canvasAspect":1.7777}"#)
        XCTAssertEqual(message, .paired(canvasAspect: 1.7777))
    }

    func testRejectedDecode() {
        XCTAssertEqual(IncomingMessage.decode(#"{"type":"rejected","reason":"in_use"}"#),
                       .rejected(reason: .inUse))
        // 协议 v1：仅剩 in_use；其他 reason 归为 unknown
        XCTAssertEqual(IncomingMessage.decode(#"{"type":"rejected","reason":"bad_code"}"#),
                       .rejected(reason: .unknown))
    }

    func testHistorySilentlyIgnored() {
        // v1 预留消息：接收端应静默忽略
        XCTAssertEqual(
            IncomingMessage.decode(##"{"type":"history","strokes":[{"id":"a","tool":"pen","color":"#000000","width":1,"points":[[0,0]]}]}"##),
            .unknown)
    }

    func testFailureTextMapping() {
        XCTAssertEqual(AppModel.failureText(for: .inUse), "电视已被其他手机连接")
        XCTAssertEqual(AppModel.failureText(for: .unknown), AppModel.unreachableText)
    }

    func testPongAndUnknown() {
        XCTAssertEqual(IncomingMessage.decode(#"{"type":"pong"}"#), .pong)
        XCTAssertEqual(IncomingMessage.decode(#"{"type":"future_thing","x":1}"#), .unknown)
        XCTAssertNil(IncomingMessage.decode("not json"))
    }

    func testTargetURLParse() {
        // 新格式：http URL（可能带 query / path）
        let http = ScanView.parseTargetURL("http://192.168.2.211:9723/draw")
        XCTAssertEqual(http?.host, "192.168.2.211")
        XCTAssertEqual(http?.port, 9723)
        let withQuery = ScanView.parseTargetURL("http://192.168.2.211:9723/draw?x=1")
        XCTAssertEqual(withQuery?.host, "192.168.2.211")
        XCTAssertEqual(withQuery?.port, 9723)
        // 旧格式兼容：suishouhua://（忽略 query）
        let legacy = ScanView.parseTargetURL("suishouhua://192.168.2.211:9723?code=482619")
        XCTAssertEqual(legacy?.host, "192.168.2.211")
        XCTAssertEqual(legacy?.port, 9723)
        XCTAssertNil(ScanView.parseTargetURL("ftp://192.168.2.211:9723/draw"))
        XCTAssertNil(ScanView.parseTargetURL("not a url"))
    }
}
