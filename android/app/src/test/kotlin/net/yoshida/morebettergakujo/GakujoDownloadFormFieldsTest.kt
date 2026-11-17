package net.yoshida.morebettergakujo

import org.junit.Assert.assertEquals
import org.junit.Test

class GakujoDownloadFormFieldsTest {
    @Test
    fun preservesRepeatedFieldsAndTheirOrder() {
        assertEquals(listOf("fileId" to "A", "event" to "download", "fileId" to "B"),
            GakujoDownloadFormFields.parse(mapOf(
                "formFields" to mapOf("fileId" to "B"),
                "formFieldPairs" to listOf(listOf("fileId", "A"),
                    listOf("event", "download"), listOf("fileId", "B")))))
    }

    @Test
    fun acceptsLegacyFields() {
        assertEquals(listOf("fileId" to "A"),
            GakujoDownloadFormFields.parse(mapOf("formFields" to mapOf("fileId" to "A"))))
    }
}
