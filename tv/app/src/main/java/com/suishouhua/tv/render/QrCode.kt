package com.suishouhua.tv.render

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

/** ZXing 生成二维码 Bitmap（仅生成，无相机依赖）。 */
object QrCode {

    fun generate(content: String, sizePx: Int): Bitmap? = try {
        val hints = mapOf(
            EncodeHintType.ERROR_CORRECTION to com.google.zxing.qrcode.decoder.ErrorCorrectionLevel.M,
            EncodeHintType.MARGIN to 1,
        )
        val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, sizePx, sizePx, hints)
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.RGB_565)
        val black = Color.BLACK.toInt()
        val white = Color.WHITE.toInt()
        val row = IntArray(sizePx)
        for (y in 0 until sizePx) {
            for (x in 0 until sizePx) {
                row[x] = if (matrix[x, y]) black else white
            }
            bmp.setPixels(row, 0, sizePx, 0, y, sizePx, 1)
        }
        bmp
    } catch (_: Exception) {
        null
    }
}
