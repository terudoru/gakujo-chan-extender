package net.yoshida.morebettergakujo

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class GakujoDownloadStreamsTest {
    @Test
    fun differentSizesDoNotOpenEitherStream() {
        assertFalse(GakujoDownloadStreams.haveSameContent(
            3L, 4L,
            { throw AssertionError("size mismatch must short-circuit") },
            { throw AssertionError("size mismatch must short-circuit") }
        ))
    }

    @Test
    fun comparesMultipleChunksWithDifferentShortReadBoundariesAndClosesStreams() {
        val bytes = ByteArray(2 * 64 * 1024 + 17) { (it % 251).toByte() }
        var firstClosed = false
        var secondClosed = false
        val first = object : ByteArrayInputStream(bytes) {
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                return super.read(buffer, offset, minOf(length, 4093))
            }
            override fun close() { firstClosed = true; super.close() }
        }
        val second = object : ByteArrayInputStream(bytes) {
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                return super.read(buffer, offset, minOf(length, 1009))
            }
            override fun close() { secondClosed = true; super.close() }
        }

        assertTrue(GakujoDownloadStreams.haveSameContent(
            bytes.size.toLong(), bytes.size.toLong(), { first }, { second }
        ))
        assertTrue(firstClosed)
        assertTrue(secondClosed)
    }

    @Test
    fun rejectsSameSizeContentThatDiffersAfterTheFirstChunk() {
        val bytes = ByteArray(2 * 64 * 1024 + 17) { 1 }
        val different = bytes.copyOf().also { it[it.lastIndex] = 2 }
        assertFalse(GakujoDownloadStreams.haveSameContent(
            bytes.size.toLong(), different.size.toLong(),
            { ByteArrayInputStream(bytes) }, { ByteArrayInputStream(different) }
        ))
    }

    @Test
    fun checksActualEofEvenWhenProviderSizesMatch() {
        assertFalse(GakujoDownloadStreams.haveSameContent(
            0L, 0L,
            { ByteArrayInputStream(byteArrayOf(1)) },
            { ByteArrayInputStream(byteArrayOf(1, 2)) }
        ))
        assertFalse(GakujoDownloadStreams.haveSameContent(
            0L, 0L,
            { ByteArrayInputStream(byteArrayOf(1, 2)) },
            { ByteArrayInputStream(byteArrayOf(1)) }
        ))
        assertTrue(GakujoDownloadStreams.haveSameContent(
            0L, 0L,
            { ByteArrayInputStream(byteArrayOf()) },
            { ByteArrayInputStream(byteArrayOf()) }
        ))
    }

    @Test
    fun comparisonClosesBothStreamsOnReadFailure() {
        var firstClosed = false
        var secondClosed = false
        val first = object : InputStream() {
            override fun read(): Int { throw IOException("provider unavailable") }
            override fun close() { firstClosed = true }
        }
        val second = object : ByteArrayInputStream(byteArrayOf(1)) {
            override fun close() { secondClosed = true; super.close() }
        }
        assertThrows(IOException::class.java) {
            GakujoDownloadStreams.haveSameContent(1L, 1L, { first }, { second })
        }
        assertTrue(firstClosed)
        assertTrue(secondClosed)
    }

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
