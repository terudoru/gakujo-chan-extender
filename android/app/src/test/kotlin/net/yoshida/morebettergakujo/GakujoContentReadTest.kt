package net.yoshida.morebettergakujo

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class GakujoContentReadTest {
    @Test
    fun enforcesLimitWhileReading() {
        val bytes = byteArrayOf(1, 2, 3)
        assertArrayEquals(bytes, readContentBytes(bytes.inputStream(), 3))
        assertThrows(IllegalArgumentException::class.java) {
            readContentBytes(bytes.inputStream(), 2)
        }
    }
}
