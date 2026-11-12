# Proposal

## Why

实现「随手画」产品：用户用手指在 iPhone 上画画，笔迹实时同步显示在客厅的 Sony / Android TV 大屏上。iPhone 负责全部交互（画笔、荧光笔、橡皮擦、颜色粗细、撤销重做、清空、导出），电视只作为 16:9 的纯净画布展示。一次只有一部手机连接一台电视。

## What Changes

- 新建 iOS 应用（Swift/SwiftUI，工作名「随手画」）：
  - 竖屏连接主页（扫码连接 / 输入配对码）与相机扫码页
  - 横屏绘图画布：画笔、荧光笔、橡皮擦、5 色 + 粗细三档、撤销 / 重做、清空、导出图片到相册
  - 顶部连接状态指示（已连接电视 / 已断开）
- 新建 Android TV 应用（Kotlin 原生，参考 navidrome-tv 工程配置）：
  - 配对界面：全屏二维码 + 6 位配对码 + 「等待连接」状态
  - 同步画板：全屏 16:9 白底画布渲染手机笔迹，右上角连接状态，遥控器返回键断开连接
  - 内嵌轻量 HTTP/WebSocket 服务（ pairing + stroke 同步），QR 码内容为 `suishouhua://<host>:<port>?code=<pairing-code>`
- 同步协议（JSON over WebSocket）：
  - `hello`（配对校验）→ `paired` / `rejected`
  - `stroke_start` / `stroke_point`(增量点) / `stroke_end`、`undo` / `redo` / `clear`、`export`(可选快照)
  - 坐标使用 0–1 归一化坐标，两端各自按 16:9 画布映射，避免拉伸或裁切
- 架构决策：**无需独立后端**。电视内嵌服务、手机直连（局域网单跳），延迟最低且不依赖 NAS 在线。QNAP Go 服务端 v1 不部署。
- 仓库结构：`ios/`（Xcode 工程）、`tv/`（Android Studio / Gradle 工程）、共享协议文档 `docs/protocol.md`

## Capabilities

### New Capabilities
- `pairing`: 电视生成二维码与配对码、手机扫码/输码配对、单设备独占连接、断开与超时处理
- `stroke-sync`: 笔迹实时同步（起笔/增量点/收笔）、撤销重做、清空、断线重连后的状态恢复
- `phone-canvas`: iPhone 绘图画布交互与工具（画笔/荧光笔/橡皮擦、颜色粗细、撤销重做、清空、导出）
- `tv-canvas`: 电视画布渲染与展示状态（配对页、同步画板、连接指示、遥控器返回断开）

### Modified Capabilities

（无——全部为新能力）

## Impact

- 新代码：`ios/` Swift 工程（需 Xcode 27.2、iOS 模拟器）、`tv/` Android 工程（compileSdk 34、minSdk 26，复用 navidrome-tv 配置模式）
- 新依赖（TV）：Ktor 或 NanoHTTPD（内嵌 WS 服务）、ZXing（二维码生成）
- 新依赖（iOS）：AVFoundation 扫码（系统框架）、Canvas 自绘（SwiftUI + UIKit gesture）
- 无后端部署；QNAP NAS 不参与 v1
- 网络要求：手机与电视在同一局域网，电视防火墙放行所选端口
