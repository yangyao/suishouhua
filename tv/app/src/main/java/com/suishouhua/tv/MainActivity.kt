package com.suishouhua.tv

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import com.suishouhua.tv.model.StrokeHistory
import com.suishouhua.tv.render.CanvasView
import com.suishouhua.tv.render.QrCode
import com.suishouhua.tv.server.DebugHostReceiver
import com.suishouhua.tv.server.DebugHostStore
import com.suishouhua.tv.server.PairingManager
import com.suishouhua.tv.server.SyncServer

class MainActivity : Activity(), SyncServer.Listener {

    private lateinit var pairingScreen: View
    private lateinit var canvasScreen: View
    private lateinit var qrImage: ImageView
    private lateinit var canvasView: CanvasView

    private val history = StrokeHistory()
    private val pairing = PairingManager()
    private lateinit var server: SyncServer

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        pairingScreen = findViewById(R.id.pairingScreen)
        canvasScreen = findViewById(R.id.canvasScreen)
        qrImage = findViewById(R.id.qrImage)
        canvasView = findViewById(R.id.canvasView)
        canvasView.attach(history)

        val drawPageHtml = assets.open("draw.html").use { it.readBytes().decodeToString() }
        server = SyncServer(pairing, history, this, drawPageHtml)

        DebugHostStore.load(this)
        DebugHostReceiver.onQrRefreshRequested = { server.refreshPairing() }
        registerReceiver(
            DebugHostReceiver(),
            android.content.IntentFilter().apply {
                addAction(DebugHostStore.ACTION_SET)
                addAction(DebugHostStore.ACTION_CLEAR)
            },
            Context.RECEIVER_EXPORTED,
        )
    }

    override fun onStart() {
        super.onStart()
        server.start()
    }

    override fun onStop() {
        server.stop()
        super.onStop()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && canvasScreen.visibility == View.VISIBLE) {
            // 遥控器返回键：断开连接，回配对页
            server.disconnectClient()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    // ---- SyncServer.Listener（服务端已在主线程回调） ----

    override fun onWaitingForPairing(qrPayload: String) {
        pairingScreen.visibility = View.VISIBLE
        canvasScreen.visibility = View.GONE
        // 批量像素写入，开销可接受；直接同步生成避免线程时序问题
        QrCode.generate(qrPayload, 720)?.let { qrImage.setImageBitmap(it) }
    }

    override fun onPaired() {
        canvasView.reset()
        canvasView.fullRedraw()
        pairingScreen.visibility = View.GONE
        canvasScreen.visibility = View.VISIBLE
    }

    override fun onDisconnected() {
        // 回配对页、清空画布显示；数据保留 5 分钟供重连恢复
        canvasView.reset()
        server.refreshPairing()
        pairingScreen.visibility = View.VISIBLE
        canvasScreen.visibility = View.GONE
    }

    override fun onStrokePoints(id: String) = canvasView.onPoints(id, history)

    override fun onStrokeStarted(id: String) {
        history.strokeById(id)?.let { canvasView.onStrokeStarted(it) }
    }

    override fun onStrokeEnded(id: String) {
        canvasView.onStrokeEnded(id)
    }

    override fun onFullRedrawNeeded() = canvasView.fullRedraw()
}
