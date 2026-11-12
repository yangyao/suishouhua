package com.suishouhua.tv.server

import android.content.Context
import android.content.SharedPreferences

/**
 * 调试用：通过 adb 广播覆盖二维码里的主机地址（模拟器 10.0.2.15 外界不可达，
 * 可用 Mac 局域网 IP + TCP 中继测试）。仅影响 QR payload 展示，WS 握手不涉及 host 校验。
 *
 * adb shell am broadcast -a com.suishouhua.tv.SET_HOST --es host 192.168.2.200
 * adb shell am broadcast -a com.suishouhua.tv.CLEAR_HOST
 */
object DebugHostStore {

    const val ACTION_SET = "com.suishouhua.tv.SET_HOST"
    const val ACTION_CLEAR = "com.suishouhua.tv.CLEAR_HOST"
    const val EXTRA_HOST = "host"

    private const val PREFS = "debug_host"
    private const val KEY_HOST = "host"

    @Volatile
    var overrideHost: String? = null
        private set

    fun set(context: Context, host: String?) {
        val prefs: SharedPreferences = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        overrideHost = host?.takeIf { it.isNotBlank() }
        prefs.edit().putString(KEY_HOST, overrideHost).apply()
    }

    fun load(context: Context) {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        overrideHost = prefs.getString(KEY_HOST, null)
    }

    /** 返回用于 QR 的 host：优先覆盖值，否则自动获取。 */
    fun effectiveHost(autoHost: String?): String = overrideHost ?: autoHost ?: "0.0.0.0"
}
