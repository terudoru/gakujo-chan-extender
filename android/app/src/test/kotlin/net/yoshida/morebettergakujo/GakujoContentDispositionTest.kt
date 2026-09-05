package net.yoshida.morebettergakujo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GakujoContentDispositionTest {
    @Test
    fun keepsSemicolonsInQuotedNames() {
        assertEquals("lecture; part 1.pdf", GakujoContentDisposition.fileName(
            "attachment; filename=\"lecture; part 1.pdf\"; size=123"
        ))
    }

    @Test
    fun acceptsWhitespaceAndQuotedEscapes() {
        assertEquals("lecture \"one\".pdf", GakujoContentDisposition.fileName(
            """attachment; filename = "lecture \"one\".pdf" """.trim()
        ))
    }

    @Test
    fun matchesOnlyTheFilenameParameter() {
        assertEquals("right.pdf", GakujoContentDisposition.fileName(
            "attachment; x-filename=wrong.pdf; filename=right.pdf"
        ))
    }

    @Test
    fun decodesExtendedNamesWithTheDeclaredCharset() {
        assertEquals("資料.pdf", GakujoContentDisposition.fileName(
            "attachment; filename=internal.pdf; filename*=UTF-8'ja'%E8%B3%87%E6%96%99.pdf"
        ))
        assertEquals("étude.pdf", GakujoContentDisposition.fileName(
            "attachment; filename*=iso-8859-1''%E9tude.pdf"
        ))
        assertEquals("lecture+notes.pdf", GakujoContentDisposition.fileName(
            "attachment; filename*=UTF-8''lecture+notes.pdf"
        ))
    }

    @Test
    fun handlesMissingAndMalformedHeaders() {
        assertNull(GakujoContentDisposition.fileName(null))
        assertNull(GakujoContentDisposition.fileName("inline"))
        assertEquals("%E7%ZZ.pdf", GakujoContentDisposition.fileName(
            "attachment; filename*=UTF-8''%E7%ZZ.pdf"
        ))
    }
}
