package net.yoshida.morebettergakujo

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class GakujoDownloadResponsePolicyTest {
    @Test
    fun rejectsHtmlDocumentsRegardlessOfBinaryMimeTypeBeforeOpeningDestination() {
        for ((mimeType, body) in listOf(
            " Text/HTML ; charset=UTF-8" to "<html>login required</html>",
            "application/octet-stream" to "\uFEFF \r\n<!DoCtYpE hTmL><html>expired</html>",
            "application/xhtml+xml" to " \n<HtMl>login</HtMl>",
            "application/pdf" to "<html>session expired</html>",
            "application/octet-stream" to "\uFEFF${" ".repeat(512)}<html>expired</html>",
            null to "<html lang=\"en\">login</html>",
            "" to "<html/>",
            "text/html" to "<!doctype html>"
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
    fun rejectsPdfRequestsRedirectedToHtmlTimeoutPages() {
        val requestedUrl = java.net.URL("https://gakujo.iess.niigata-u.ac.jp/file")
        val requestUrlPath = requestedUrl.path
        val finalUrl = java.net.URL(requestedUrl, "/campusweb/theme/default/Timeout.html")
        assertTrue(finalUrl.path.endsWith(".html"))
        val error = assertThrows(IllegalStateException::class.java) {
            GakujoDownloadResponsePolicy.openValidated(
                ByteArrayInputStream("<html>".toByteArray()), "attachment.pdf", "text/html",
                urlPath = requestUrlPath
            )
        }
        assertEquals(GakujoDownloadResponsePolicy.PAGE_RETURNED_MESSAGE, error.message)
    }

    @Test
    fun permitsExplicitHtmlFilesAndPreservesEveryByteOfRealAttachments() {
        for ((name, mimeType, bytes) in listOf(
            Triple("page.HTML", "text/html", "<html>attachment</html>".toByteArray()),
            Triple("page.HtM", "application/octet-stream", "<!DOCTYPE html>".toByteArray()),
            Triple("attachment.pdf", "text/html", "%PDF-1.7".toByteArray()),
            Triple("attachment.pdf", "application/xhtml+xml", "%PDF-1.7".toByteArray()),
            Triple("notes.txt", "text/html", "login required".toByteArray()),
            Triple("notes.txt", "text/plain", "<html> is an HTML tag".toByteArray()),
            Triple("notes.csv", " Text/CSV ; charset=UTF-8", "<html>,is a tag".toByteArray()),
            Triple("data.bin", "application/octet-stream", "<htmlish>literal bytes".toByteArray()),
            Triple("data.bin", "text/html", "<!doctype htmlish>literal bytes".toByteArray()),
            Triple("data.bin", "text/html", "<html".toByteArray()),
            Triple("data.bin", "text/html", "\uFEFF\uFEFF<html>literal bytes</html>".toByteArray()),
            Triple("data.bin", "application/octet-stream", ByteArray(2050) { (it % 251).toByte() }),
            Triple("notes.txt", "text/plain", "Use <html> in a document".toByteArray())
        )) {
            GakujoDownloadResponsePolicy.openValidated(ByteArrayInputStream(bytes), name, mimeType).use {
                assertArrayEquals(bytes, it.readBytes())
            }
        }
    }

    @Test
    fun permitsContentDispositionHtmlAttachmentsWithGenericRequestedNames() {
        val bytes = "<html>attachment</html>".toByteArray()
        for (name in listOf("page.HTML", "page.HtM")) {
            GakujoDownloadResponsePolicy.openValidated(
                ByteArrayInputStream(bytes), "Download", "text/html", name
            ).use { assertArrayEquals(bytes, it.readBytes()) }
        }
    }

    @Test
    fun permitsHtmlUrlPathsButNotHtmlNamesInQueries() {
        val bytes = "<html>attachment</html>".toByteArray()
        for (url in listOf(
            "https://gakujo.iess.niigata-u.ac.jp/page.HTML?download=1",
            "https://gakujo.iess.niigata-u.ac.jp/page.HtM#content"
        )) {
            GakujoDownloadResponsePolicy.openValidated(
                ByteArrayInputStream(bytes), "Download", "application/pdf",
                urlPath = java.net.URL(url).path
            ).use { assertArrayEquals(bytes, it.readBytes()) }
        }
        assertThrows(IllegalStateException::class.java) {
            GakujoDownloadResponsePolicy.openValidated(
                ByteArrayInputStream(bytes), "Download", "text/html",
                urlPath = java.net.URL("https://gakujo.iess.niigata-u.ac.jp/file?name=page.html").path
            )
        }
    }

    @Test
    fun largeDownloadsDoNotRetainTheMarkedStream() {
        val size = 32L * 1024 * 1024 + 13
        var remaining = size
        val input = object : InputStream() {
            override fun read(): Int {
                if (remaining == 0L) return -1
                remaining--
                return 0
            }
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                // An unbounded mark grows the buffer and eventually requests
                // ever larger reads instead of streaming through a fixed buffer.
                assertTrue("download buffer grew with the file", length <= 64 * 1024)
                if (remaining == 0L) return -1
                val count = minOf(length.toLong(), remaining).toInt()
                buffer.fill(0, offset, offset + count)
                remaining -= count
                return count
            }
        }
        var copied = 0L
        val output = object : OutputStream() {
            override fun write(value: Int) { copied++ }
            override fun write(buffer: ByteArray, offset: Int, length: Int) {
                copied += length
            }
        }
        GakujoDownloadResponsePolicy.openValidated(input, "large.bin", null).use {
            assertTrue("validation read more than a small buffer", size - remaining <= 8192)
            it.copyTo(output)
            assertEquals(size, copied)
            assertThrows(IOException::class.java) { it.reset() }
        }
    }

    @Test
    fun rejectedPickedDocumentIsDeletedOnlyWhenItWasKnownToBeEmpty() {
        for (initialSize in listOf(0L, 42L, null)) {
            var documentExists = true
            var outputOpened = false
            var inputClosed = false
            val input = object : ByteArrayInputStream("<html>login</html>".toByteArray()) {
                override fun close() { inputClosed = true; super.close() }
            }
            val error = assertThrows(IllegalStateException::class.java) {
                GakujoDownloadStreams.copy(
                    openInput = { GakujoDownloadResponsePolicy.openValidated(input, "file.pdf", "text/html") },
                    openOutput = { outputOpened = true; ByteArrayOutputStream() },
                    cleanupFailedDestination = {
                        assertTrue(inputClosed)
                        if (GakujoDownloadStreams.shouldDeleteFailedPickedDestination(initialSize)) {
                            documentExists = false
                        }
                    }
                )
            }
            assertEquals(GakujoDownloadResponsePolicy.PAGE_RETURNED_MESSAGE, error.message)
            assertFalse(outputOpened)
            assertEquals(initialSize != 0L, documentExists)
        }
    }
}
