package net.yoshida.morebettergakujo

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class GakujoContentReadTest {
    @Test
    fun readsRangeAndRejectsInvalidOrShortRanges() {
        val bytes = byteArrayOf(1, 2, 3, 4)
        assertArrayEquals(byteArrayOf(2, 3), readContentChunk(bytes.inputStream(), 1, 2))
        assertThrows(IllegalArgumentException::class.java) {
            readContentChunk(bytes.inputStream(), 0, 8 * 1024 * 1024 + 1)
        }
        assertThrows(java.io.EOFException::class.java) {
            readContentChunk(bytes.inputStream(), 3, 2)
        }
    }
}
