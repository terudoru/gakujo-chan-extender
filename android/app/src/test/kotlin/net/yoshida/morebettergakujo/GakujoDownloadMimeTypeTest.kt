package net.yoshida.morebettergakujo

import org.junit.Assert.assertEquals
import org.junit.Test

class GakujoDownloadMimeTypeTest {
    @Test
    fun pickerUsesTheSuggestedNamesExtensionOrFallsBackToBinary() {
        val types = mapOf("pdf" to "application/pdf", "mp3" to "audio/mpeg")
        val extensions = mutableListOf<String>()
        val lookup: (String) -> String? = { extensions.add(it); types[it] }
        assertEquals("application/pdf", GakujoDownloadMimeType.forFileName("講義.資料.PDF", lookup))
        assertEquals("audio/mpeg", GakujoDownloadMimeType.forFileName("lecture.mp3", lookup))
        for (name in listOf("archive.unknown", "download", "download.")) {
            assertEquals("application/octet-stream", GakujoDownloadMimeType.forFileName(name, lookup))
        }
        assertEquals(listOf("pdf", "mp3", "unknown"), extensions)
    }
}
