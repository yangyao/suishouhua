# 随手画 · iPhone 端

SwiftUI 应用，与电视端（`../tv`）按 `../docs/protocol.md` 同步画画。

## 打开 / 构建

```bash
cd ios
xcodegen generate          # 已生成 SuishouHua.xcodeproj，改 project.yml 后需重新生成
open SuishouHua.xcodeproj  # 或用 Xcode 直接打开
```

命令行构建 / 测试（iPhone Duo 模拟器）：

```bash
xcodebuild -scheme SuishouHua -destination 'platform=iOS Simulator,name=iPhone Duo' build
xcodebuild -scheme SuishouHua -destination 'platform=iOS Simulator,name=iPhone Duo' test
```

## 本地联调（mock 电视服务器）

```bash
python3 tools/mock-tv-server.py [port]  # 默认 9723；跑测试请用 9725（adb 占用 127.0.0.1:9723）
MOCK_PAIR_CODE=123456 python3 tools/mock-tv-server.py 9725
```

模拟器上选「输入电视地址」，地址填 `127.0.0.1:9725` 即可进入画布（协议无配对码）。
（`Network.framework` 的 NWListener 在部分环境报 POSIX 22，故 mock 用纯 socket 实现 RFC6455。）

## 结构

- `SuishouHua/Protocol/` — 协议消息编解码（JSON over WebSocket，坐标 0–1 归一化）
- `SuishouHua/Engine/` — DrawingEngine：笔画序列、undo/redo 栈、16ms 批量发送
- `SuishouHua/Connection/` — TVConnection：URLSessionWebSocketTask 封装
- `SuishouHua/App/` — AppModel：配对、心跳（5s ping，电视 10s 无帧判线）、断线 5 分钟内指数退避重连、history 恢复
- `SuishouHua/Canvas/` — 画布 UIView（触摸捕获 + CAShapeLayer 贝塞尔平滑）、横屏画布页与工具栏
- `SuishouHua/Views/` — 连接主页 / 扫码页（AVFoundation QR）/ 手动输码页
- `Tests/` — 单元测试（undo/redo 语义、坐标归一化、协议 round-trip、mock 服务器联调）
- `UITests/` — 手动输码路径 UI 测试（需 mock 服务器运行，否则相关用例失败/跳过）
