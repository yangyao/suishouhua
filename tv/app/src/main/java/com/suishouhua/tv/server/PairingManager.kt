package com.suishouhua.tv.server

/**
 * 占用状态机（纯 Kotlin，可单元测试）：
 * 单设备独占——同一时间只允许一个客户端保持已配对连接。
 * 配对码机制已移除（v2）：hello 不带码，电视只检查占用。
 */
class PairingManager {

    private var occupied = false

    fun isOccupied(): Boolean = occupied

    /** 空闲则占用并返回 true；已占用返回 false。 */
    @Synchronized
    fun tryClaim(): Boolean {
        if (occupied) return false
        occupied = true
        return true
    }

    /** 释放占用（连接断开）。 */
    fun release() {
        occupied = false
    }
}
