package com.suishouhua.tv.server

import android.os.Handler
import android.os.Looper
import com.suishouhua.tv.model.StrokeHistory
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.application.install
import io.ktor.server.cio.CIO
import io.ktor.server.engine.ApplicationEngine
import io.ktor.server.engine.embeddedServer
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import io.ktor.server.websocket.DefaultWebSocketServerSession
import io.ktor.server.websocket.WebSockets
import io.ktor.server.websocket.webSocket
import io.ktor.websocket.CloseReason
import io.ktor.websocket.Frame
import io.ktor.websocket.close
import io.ktor.websocket.readText
import io.ktor.websocket.send
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * 内嵌 Ktor CIO 服务：HTTP /draw + WS /ws，端口 9723。
 * 服务仅在 Activity 前台生命周期内运行（start/stop 由 MainActivity 管理）。
 */
class SyncServer(
    private val pairing: PairingManager,
    private val history: StrokeHistory,
    private val listener: Listener,
    /** Web 画板单页 HTML（来自 assets/draw.html）。 */
    private val drawPageHtml: String,
) {

    interface Listener {
        /** 二维码内容变化（进入配对页）。 */
        fun onWaitingForPairing(qrPayload: String)
        /** 一部手机配对成功，应显示同步画板。 */
        fun onPaired()
        /** 连接断开（远端断开 / 本端返回键），应回配对页。 */
        fun onDisconnected()
        /** 当前笔画有增量点，可只重绘增量区域。 */
        fun onStrokePoints(id: String)
        /** 笔画开始/结束。 */
        fun onStrokeStarted(id: String)
        fun onStrokeEnded(id: String)
        /** undo/redo/erase/clear 之后需要全量重绘。 */
        fun onFullRedrawNeeded()
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var scope: CoroutineScope? = null
    private var engine: ApplicationEngine? = null

    @Volatile
    private var session: DefaultWebSocketServerSession? = null

    /** 画布内容保留起始时间（断开时刻），5 分钟内重连可恢复。 */
    @Volatile
    private var retainedAtMs = 0L

    private fun ui(block: () -> Unit) {
        mainHandler.post(block)
    }

    fun start() {
        if (engine != null) return
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        engine = tryStartServer()
        if (engine == null) {
            // 端口被占用（如上一个进程未完全退出）：延迟重试
            scope?.launch {
                var e: ApplicationEngine? = null
                repeat(5) {
                    delay(1500)
                    e = tryStartServer()
                    if (e != null) return@repeat
                }
                engine = e
                if (e != null) announcePairing()
            }
            return
        }
        announcePairing()
    }

    private fun tryStartServer(): ApplicationEngine? = try {
        embeddedServer(CIO, port = Protocol.PORT, host = "0.0.0.0") {
            install(WebSockets)
            routing {
                get("/draw") {
                    call.respondText(drawPageHtml, ContentType.Text.Html, HttpStatusCode.OK)
                }
                webSocket("/ws") {
                    handleSession(this)
                }
            }
        }.start(wait = false)
    } catch (t: Throwable) {
        android.util.Log.w("SyncServer", "bind 9723 failed: ${t.message}")
        null
    }

    fun stop() {
        val s = session
        val closer = CoroutineScope(Dispatchers.IO)
        if (s != null) {
            closer.launch {
                try {
                    s.close(CloseReason(CloseReason.Codes.NORMAL, "shutdown"))
                } catch (_: Exception) {
                }
            }
        }
        try {
            engine?.stop(500, 1000)
        } catch (_: Exception) {
        }
        engine = null
        scope?.cancel()
        scope = null
        session = null
    }

    /** 本端主动断开（遥控器返回键）。 */
    fun disconnectClient() {
        val s = session ?: return
        scope?.launch {
            try {
                s.close(CloseReason(CloseReason.Codes.NORMAL, "bye"))
            } catch (_: Exception) {
            }
        }
    }

    /** 刷新配对页二维码展示。 */
    fun refreshPairing() {
        announcePairing()
    }

    fun qrPayload(): String {
        val host = DebugHostStore.effectiveHost(com.suishouhua.tv.net.IpUtil.lanIpv4())
        return "http://$host:${Protocol.PORT}/draw"
    }

    private fun announcePairing() {
        android.util.Log.i("SyncServer", "announcePairing")
        ui { listener.onWaitingForPairing(qrPayload()) }
    }

    private suspend fun closeQuietly(s: DefaultWebSocketServerSession, reason: String) {
        try {
            s.close(CloseReason(CloseReason.Codes.NORMAL, reason))
        } catch (_: Exception) {
        }
    }

    private suspend fun handleSession(ws: DefaultWebSocketServerSession) {
        android.util.Log.d(TAG, "ws accept from ${ws.call.request.local.remoteHost}")
        var claimed = false
        var cause = "EOF" // incoming 通道正常耗尽即 EOF
        try {
            for (frame in ws.incoming) {
                val text = (frame as? Frame.Text)?.readText() ?: continue
                val msg = Protocol.parse(text) ?: continue // 未知/坏帧静默忽略

                if (!claimed) {
                    if (msg !is Protocol.InMessage.Hello) continue // hello 必须为首条消息
                    if (!pairing.tryClaim()) {
                        android.util.Log.w(TAG, "rejected: in_use")
                        ws.send(Protocol.rejected("in_use"))
                        cause = "rejected(in_use)"
                        break
                    }
                    claimed = true
                    session = ws
                    ws.send(Protocol.paired())
                    maybeSendHistory(ws)
                    android.util.Log.i(TAG, "hello+paired, history=${history.visibleStrokes().size} strokes")
                    ui { listener.onPaired() }
                    continue
                }

                when (msg) {
                    is Protocol.InMessage.Ping -> {
                        android.util.Log.d(TAG, "app ping received")
                        ws.send(Protocol.pong())
                        android.util.Log.d(TAG, "app pong sent")
                    }
                    is Protocol.InMessage.StrokeStart -> {
                        history.begin(com.suishouhua.tv.model.Stroke(msg.id, msg.tool, msg.color, msg.width))
                        android.util.Log.d(TAG, "stroke_start id=${msg.id}")
                        ui { listener.onStrokeStarted(msg.id) }
                    }
                    is Protocol.InMessage.StrokePoints -> {
                        history.addPoints(msg.id, msg.points)
                        ui { listener.onStrokePoints(msg.id) }
                    }
                    is Protocol.InMessage.StrokeEnd -> {
                        history.end(msg.id)
                        val pts = history.strokeById(msg.id)?.points?.size ?: -1
                        android.util.Log.d(TAG, "stroke_end id=${msg.id} pts=$pts totalStrokes=${history.visibleStrokes().size}")
                        ui { listener.onStrokeEnded(msg.id) }
                    }
                    is Protocol.InMessage.Erase -> {
                        history.erase(msg.strokeId)
                        android.util.Log.d(TAG, "erase strokeId=${msg.strokeId} totalStrokes=${history.visibleStrokes().size}")
                        ui { listener.onFullRedrawNeeded() }
                    }
                    Protocol.InMessage.Undo -> {
                        history.undo()
                        android.util.Log.d(TAG, "undo totalStrokes=${history.visibleStrokes().size}")
                        ui { listener.onFullRedrawNeeded() }
                    }
                    Protocol.InMessage.Redo -> {
                        history.redo()
                        android.util.Log.d(TAG, "redo totalStrokes=${history.visibleStrokes().size}")
                        ui { listener.onFullRedrawNeeded() }
                    }
                    Protocol.InMessage.Clear -> {
                        history.clearAll()
                        android.util.Log.d(TAG, "clear totalStrokes=0")
                        ui { listener.onFullRedrawNeeded() }
                    }
                    is Protocol.InMessage.Hello -> Unit // 已配对后重复 hello 忽略
                }
            }
        } catch (t: Throwable) {
            // 连接异常按断开处理
            cause = "IO error: ${t.javaClass.simpleName}: ${t.message}"
        } finally {
            android.util.Log.w(TAG, "disconnected claimed=$claimed reason=$cause")
            if (claimed) {
                session = null
                pairing.release()
                retainedAtMs = System.currentTimeMillis()
                ui { listener.onDisconnected() }
            }
        }
    }

    /** 配对成功后：5 分钟内有保留画布则先发 history 恢复。 */
    private suspend fun maybeSendHistory(ws: DefaultWebSocketServerSession) {
        val withinRetention = System.currentTimeMillis() - retainedAtMs < RETENTION_MS
        if (!withinRetention) history.reset()
        val strokes = history.visibleStrokes()
        if (strokes.isNotEmpty()) {
            ws.send(Protocol.history(strokes))
        }
    }

    companion object {
        /** 断开后画布内容保留 5 分钟。 */
        const val RETENTION_MS = 5 * 60 * 1000L

        /** 定位日志统一 tag。 */
        const val TAG = "SyncTrace"
    }
}
