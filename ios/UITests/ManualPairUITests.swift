import XCTest

/// 模拟器上手动输入电视地址路径 UI 验证（需要本地 mock 电视服务器：
/// `python3 tools/mock-tv-server.py 9725`，协议无配对码）。
final class ManualPairUITests: XCTestCase {
    static let hostPort = "127.0.0.1:9725"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openManualEntry(_ app: XCUIApplication) -> XCUIElement {
        app.launch()
        app.buttons["输入电视地址"].tap()
        let ip = app.textFields["例如 192.168.2.211"]
        XCTAssertTrue(ip.waitForExistence(timeout: 4))
        return ip
    }

    func testManualPairSuccessShowsCanvas() throws {
        let app = XCUIApplication()
        let ip = openManualEntry(app)
        ip.tap()
        ip.typeText(Self.hostPort)
        app.buttons["连接"].tap()
        // 配对成功进入横屏画布，顶栏出现「已连接电视」
        XCTAssertTrue(app.staticTexts["已连接电视"].waitForExistence(timeout: 10))
        // 保持连接 >6s，让至少一次 5s 心跳 ping 发出（mock 服务器侧统计验证）
        Thread.sleep(forTimeInterval: 6)
    }

    func testUnreachableHostShowsWifiError() throws {
        let app = XCUIApplication()
        let ip = openManualEntry(app)
        ip.tap()
        ip.typeText("192.0.2.99")  // RFC 5737 保留段，本机必然连不上
        app.buttons["连接"].tap()
        XCTAssertTrue(app.staticTexts["无法连接到电视，请确认在同一 Wi-Fi"].waitForExistence(timeout: 15))
    }
}
