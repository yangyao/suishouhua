# Design

## Context

全新仓库，两个客户端工程从零搭建：

- **TV 端**：Kotlin 原生 Android TV 应用。参考 `../navidrome-tv` 的工程配置（compileSdk 34 / minSdk 26 / Gradle Kotlin DSL）与遥控器处理模式；本机 adb 已连接 Sony 真机（192.168.2.211）与模拟器，可直接验证。
- **iOS 端**：SwiftUI 应用。本机 Xcode 27.2 + iPhone 模拟器可用；扫码需真机相机，模拟器上以手动输码路径验证。
- 架构决策（已与用户确认）：无独立后端，电视内嵌 WebSocket 服务，手机局域网直连。QNAP Go 服务端 v1 不实现。

## Goals / Non-Goals

**Goals:**
- 局域网内扫码即连，配对到出笔 < 5 秒
- 书写延迟（落笔→电视渲染）≤ 100ms，增量点合并间隔 ≤ 16ms
- 两端画布（笔画序列）最终一致，断线 5 分钟内可恢复
- 界面符合设计稿（design-concepts/ 三张图）：暖白底、石墨文字、蓝色主色

**Non-Goals:**
- 多手机、多电视、房间/账户体系
- 云端存储、订阅、AI 功能
- Go/NAS 后端（协议设计保持可切换，留作未来扩展）
- Apple Pencil 支持

## Decisions

### D1. TV 内嵌服务：Ktor (CIO) 而非 NanoHTTPD
Ktor CIO 引擎单依赖、协程原生、WebSocket 支持成熟，Kotlin 工程无跨语言负担。服务仅在应用前台运行，端口固定 9723（随手画谐音），HTTP `/pair/info` 返回 `{code, canvasAspect}`，WS 路径 `/ws`。备选 NanoHTTPD+Java-WebSocket 被否：两个库、回调风格、无协程。

### D2. 配对码：6 位数字，UI 校验 + WS hello 校验双保险
二维码含 `suishouhua://host:port?code=NNNNNN`。手动输码场景手机可先 GET `/pair/info` 拿到当前 code 做预校验；最终以 WS `hello{code}` 的 `paired/rejected` 为准。码 10 分钟过期或被使用后轮换。

### D3. 协议：JSON over WebSocket，消息类型小型枚举
`docs/protocol.md` 为唯一权威定义。消息：`hello/paired/rejected`、`stroke_start{tool,color,width,id}`、`stroke_point{x,y}[批量数组]`、`stroke_end`、`undo/redo/clear`、`history{strokes[]}`、`ping/pong`。坐标 0–1 归一化；橡皮擦按笔画（`erase{strokeId}` 走 undo 栈同一路径）。选 JSON 而非二进制：消息量小（16ms 合并后 ~60msg/s），可读性与调试优先；未来需要再升级 MessagePack，不影响 spec。

### D4. TV 渲染：Canvas 自绘而非 Compose 笔画对象树
单一 `StrokeHistory` 列表 + `Canvas.drawPath` 增量重绘：收到 stroke_point 只重绘当前笔画所在脏区域；undo/redo/clear 全量重绘。笔画点用 `Path.quadraticBezierTo` 平滑。备选 Compose `Canvas` 声明式全量重组被否：60fps 下重组开销大。

### D5. iOS 绘图：SwiftUI + UIGestureRecognizer 桥接的 PencilKit 风格自绘
不用 PencilKit（其 PKCanvasView 面向 Apple Pencil，导出与坐标提取繁琐，且我们只需 5 色 3 粗）。自建 `Stroke` 模型 + `UIView`（`draw(_:)`/CAShapeLayer）捕获 touch，SwiftUI `UIViewRepresentable` 包装。触摸采样合并间隔 16ms 发送。

### D6. iOS 扫码：AVFoundation `AVCaptureMetadataOutput`（qr 原生支持）
无需三方库。模拟器不可用相机 → 保留「输入配对码」路径作为一等入口兼测试路径。

### D7. 仓库布局与双 Agent 分工
```
ios/          # Xcode 工程（随手画）
tv/           # Android 工程（随手画 TV）
docs/protocol.md   # 共享协议权威定义（两端各按此实现）
openspec/     # 规划工件
```
iOS Agent 与 TV Agent 依据 protocol.md 并行开发，联调用 TV 模拟器 + iOS 模拟器（手动输码）在本机即可完成。

### D8. TV 端二维码生成：ZXing core（纯生成，无相机依赖）
`com.google.zxing:core` 仅用于把字符串渲染为 Bitmap，体积小、无传递依赖。

## Risks / Trade-offs

- [模拟器无相机，扫码无法端到端验证] → 手动输码为一等入口；真机联调在任务中单列
- [网络切换/休眠导致 WS 静默断开] → 30s ping/pong 心跳；手机端 5 分钟内指数退避自动重连 + history 恢复
- [电视被路由器 AP 隔离，手机连不上] → 连接失败文案明确提示检查同一 Wi-Fi；设计稿已含手动输码兜底
- [高笔压快速书写丢点] → 16ms 合并 + stroke_end 前本地全量点已在手机渲染，电视丢点仅影响末端精度，可接受
- [Go 1.20 环境存在但 v1 无后端] → 协议不假设服务端拓扑，未来加 NAS 中继只改连接目标，不改消息 schema

## Migration Plan

纯新增项目，无迁移。回滚 = 删除 `ios/`、`tv/` 目录。

## Open Questions

无——关键决策（无后端、Kotlin、直连）已由用户确认。
