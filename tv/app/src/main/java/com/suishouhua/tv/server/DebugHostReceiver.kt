package com.suishouhua.tv.server

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast

/** adb 广播设置/清除二维码主机覆盖值。 */
class DebugHostReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            DebugHostStore.ACTION_SET -> {
                val host = intent.getStringExtra(DebugHostStore.EXTRA_HOST)
                DebugHostStore.set(context, host)
                val msg = if (host.isNullOrBlank()) "QR host 覆盖已清除" else "QR host 覆盖为 $host"
                Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
                android.util.Log.i("DebugHostReceiver", msg)
            }
            DebugHostStore.ACTION_CLEAR -> {
                DebugHostStore.set(context, null)
                Toast.makeText(context, "QR host 覆盖已清除", Toast.LENGTH_SHORT).show()
                android.util.Log.i("DebugHostReceiver", "QR host 覆盖已清除")
            }
        }
        // 通知刷新二维码（由 MainActivity 注册时挂上）
        onQrRefreshRequested?.invoke()
    }

    companion object {
        /** MainActivity 注册，用于触发重新生成二维码展示。 */
        @Volatile
        var onQrRefreshRequested: (() -> Unit)? = null
    }
}
