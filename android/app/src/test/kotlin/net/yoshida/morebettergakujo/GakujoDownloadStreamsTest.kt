package net.yoshida.morebettergakujo

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class GakujoDownloadStreamsTest {
    @Test
    fun doesNotOpenOrTruncateDestinationWhenInputCannotBeOpened() {
        val failure = IOException("connection closed")
        var outputOpened = false
        assertSame(failure, assertThrows(IOException::class.java) {
            GakujoDownloadStreams.copy(
                openInput = { throw failure },
                openOutput = { outputOpened = true; ByteArrayOutputStream() }
            )
        })
        assertFalse(outputOpened)
    }

    @Test
    fun copiesBytesAndClosesBothStreams() {
        var inputClosed = false
        var outputClosed = false
        val input = object : ByteArrayInputStream(byteArrayOf(1, 2, 3)) {
            override fun close() { inputClosed = true; super.close() }
        }
        val output = object : ByteArrayOutputStream() {
            override fun close() { outputClosed = true; super.close() }
        }
        GakujoDownloadStreams.copy({ input }, { output })
        assertArrayEquals(byteArrayOf(1, 2, 3), output.toByteArray())
        assertTrue(inputClosed)
        assertTrue(outputClosed)
    }

    @Test
    fun closesInputWhenDestinationCannotBeOpened() {
        var inputClosed = false
        val input = object : ByteArrayInputStream(byteArrayOf(1)) {
            override fun close() { inputClosed = true; super.close() }
        }
        assertThrows(IOException::class.java) {
            GakujoDownloadStreams.copy({ input }, { throw IOException("denied") })
        }
        assertTrue(inputClosed)
    }

    @Test
    fun cleansOnlyFailedDownloadsAfterClosingStreams() {
        var outputClosed = false
        var cleaned = false
        val output = object : ByteArrayOutputStream() {
            override fun write(bytes: ByteArray, offset: Int, length: Int) {
                throw IOException("disk full")
            }
            override fun close() { outputClosed = true; super.close() }
        }
        assertThrows(IOException::class.java) {
            GakujoDownloadStreams.copy(
                { ByteArrayInputStream(byteArrayOf(1)) },
                { output },
                { assertTrue(outputClosed); cleaned = true }
            )
        }
        assertTrue(cleaned)
        GakujoDownloadStreams.copy(
            { ByteArrayInputStream(byteArrayOf(1)) },
            { ByteArrayOutputStream() },
            { throw AssertionError("successful download must not be deleted") }
        )
    }

    @Test
    fun preservesOriginalFailureWhenCleanupAlsoFails() {
        val failure = IOException("connection failed")
        val cleanupFailure = IOException("provider unavailable")
        assertSame(failure, assertThrows(IOException::class.java) {
            GakujoDownloadStreams.copy(
                { throw failure },
                { ByteArrayOutputStream() },
                { throw cleanupFailure }
            )
        })
        assertArrayEquals(arrayOf(cleanupFailure), failure.suppressed)
    }
}
