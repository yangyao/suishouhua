# Spec Delta

## Purpose

定义手机与电视之间笔迹与画板指令的实时同步协议与行为：起笔/增量点/收笔、撤销重做、清空、断线恢复，保证两端画布一致且延迟可感。

## ADDED Requirements

### Requirement: 通信通道
配对成功后，手机与电视 SHALL 通过单一 WebSocket 连接交换 JSON 消息。所有画板相关指令（笔迹、撤销、重做、清空）与状态变更 MUST 通过该通道传递，且消息 MUST 为 UTF-8 JSON。

#### Scenario: 通道建立
- **WHEN** 配对成功（paired 消息送达双方）
- **THEN** 双方进入同步画板状态，后续消息在此通道上传输

### Requirement: 笔迹增量同步
手机 SHALL 在用户落笔时发送 `stroke_start`（含颜色、粗细、工具类型），移动时以增量点发送 `stroke_point`（含归一化坐标 0–1），收笔时发送 `stroke_end`。坐标 MUST 以 16:9 画布为基准归一化，两端各自映射显示，避免拉伸或裁切。

#### Scenario: 一笔画的同步
- **WHEN** 用户在手机画布上完成一次落笔—移动—抬手
- **THEN** 电视按相同顺序收到 stroke_start、若干 stroke_point、stroke_end，并渲染出与手机一致的笔迹

#### Scenario: 荧光笔样式
- **WHEN** 用户使用荧光笔绘制
- **THEN** stroke_start 携带工具类型 marker，电视以半透明宽笔触渲染

### Requirement: 撤销与重做
手机端执行撤销或重做时 SHALL 发送 `undo` / `redo` 消息，电视端 MUST 同步移除或恢复对应笔画，两端笔画序列保持一致。

#### Scenario: 撤销同步
- **WHEN** 用户在手机点击撤销，上一笔从手机画布移除
- **THEN** 电视画布同步移除同一笔

### Requirement: 清空画板
手机端执行清空时 SHALL 发送 `clear` 消息，电视端 MUST 清空画布。清空操作 MUST 可被撤销链恢复。

#### Scenario: 清空同步
- **WHEN** 用户在手机点击清空并确认
- **THEN** 两端画布同时清空，电视显示纯白画布

### Requirement: 断线行为
手机端 SHOULD 以 ping/pong 作为链路探测（5s 周期），但电视端 MUST NOT 据此做超时断开。连接真正断开（TCP 层）后，若 5 分钟内手机重连成功，电视 MAY 发送当前完整笔画序列（`history`）供手机恢复；单连接模型下电视端断开即丢弃画布，`history` 为预留消息，两端当前实现可静默忽略。

#### Scenario: 网络抖动后重连
- **WHEN** 手机因网络抖动断开后重新扫码连接
- **THEN** 获得全新画布继续绘制；如收到 `history` 则按序列恢复

### Requirement: 同步延迟
在局域网环境下，从手机落笔到电视开始渲染对应线段的时间 SHOULD 不超过 100ms。为降低延迟，增量点消息 SHOULD 合并发送但合并间隔不超过 16ms。

#### Scenario: 流畅书写
- **WHEN** 用户以正常速度连续书写
- **THEN** 电视上的笔迹连贯出现，无可感知的停顿或跳跃
