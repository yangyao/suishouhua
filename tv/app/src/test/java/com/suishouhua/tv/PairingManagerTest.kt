package com.suishouhua.tv

import com.suishouhua.tv.server.PairingManager
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PairingManagerTest {

    @Test
    fun `空闲时占用成功`() {
        val pm = PairingManager()
        assertFalse(pm.isOccupied())
        assertTrue(pm.tryClaim())
        assertTrue(pm.isOccupied())
    }

    @Test
    fun `已占用时再次占用失败`() {
        val pm = PairingManager()
        assertTrue(pm.tryClaim())
        assertFalse(pm.tryClaim())
        assertTrue(pm.isOccupied())
    }

    @Test
    fun `释放后可再次占用`() {
        val pm = PairingManager()
        assertTrue(pm.tryClaim())
        pm.release()
        assertFalse(pm.isOccupied())
        assertTrue(pm.tryClaim())
    }
}
