package net.yoshida.morebettergakujo

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class GakujoDownloadResponsePolicyTest {
    @Test
    fun rejectsHtmlHeadersAndSniffedPagesBeforeOpeningDestination() {
        for ((mimeType, body) in listOf(
            " Text/HTML ; charset=UTF-8" to "login required",
            "application/octet-stream" to "\uFEFF \r\n<!DoCtYpE hTmL><html>expired</html>",
            "application/pdf" to " \n<HtMl>login</HtMl>",
            "application/pdf" to "\uFEFF${" ".repeat(2048)}<html>expired</html>"
        )) {
            var closed = false
            var destinationOpened = false
            val input = object : ByteArrayInputStream(body.toByteArray(Charsets.UTF_8)) {
                override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
                    super.read(buffer, offset, minOf(length, 1))
                override fun close() { closed = true; super.close() }
            }
            val error = assertThrows(IllegalStateException::class.java) {
                GakujoDownloadStreams.copy(
                    { GakujoDownloadResponsePolicy.openValidated(input, "attachment.pdf", mimeType) },
                    { destinationOpened = true; ByteArrayOutputStream() }
                )
            }
            assertEquals(GakujoDownloadResponsePolicy.PAGE_RETURNED_MESSAGE, error.message)
            assertFalse(destinationOpened)
            assertTrue(closed)
        }
    }

    @Test
    fun permitsExplicitHtmlFilesAndPreservesEveryByteOfRealAttachments() {
        for ((name, mimeType, bytes) in listOf(
            Triple("page.HTML", "text/html", "<html>attachment</html>".toByteArray()),
            Triple("page.HtM", "application/octet-stream", "<!DOCTYPE html>".toByteArray()),
            Triple("data.bin", "application/octet-stream", ByteArray(2050) { (it % 251).toByte() }),
            Triple("notes.txt", "text/plain", "Use <html> in a document".toByteArray())
        )) {
            GakujoDownloadResponsePolicy.openValidated(ByteArrayInputStream(bytes), name, mimeType).use {
                assertArrayEquals(bytes, it.readBytes())
            }
        }
    }
}
