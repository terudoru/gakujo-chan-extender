package net.yoshida.morebettergakujo

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class GakujoDocumentPermissionsTest {
    private val readWrite = Intent.FLAG_GRANT_READ_URI_PERMISSION or
        Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    @Test
    fun persistsOnlyTheOfferedReadWriteFlags() {
        for (offered in listOf(readWrite, Intent.FLAG_GRANT_READ_URI_PERMISSION)) {
            val persisted = mutableListOf<Int>()
            GakujoDocumentPermissions.persistIfOffered(
                offered or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                persist = { persisted.add(it) },
                onDenied = { fail("Permission should persist") }
            )
            assertEquals(listOf(offered), persisted)
        }
    }

    @Test
    fun temporaryGrantsAreNotPersisted() {
        GakujoDocumentPermissions.persistIfOffered(
            readWrite,
            persist = { fail("Temporary grants cannot be persisted") },
            onDenied = { fail("No persistence attempt was expected") }
        )
    }

    @Test
    fun rejectedPersistenceIsReportedWithoutFailingTheDownload() {
        val denied = SecurityException("Provider refused")
        val errors = mutableListOf<SecurityException>()
        GakujoDocumentPermissions.persistIfOffered(
            readWrite or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            persist = { throw denied },
            onDenied = { errors.add(it) }
        )
        assertEquals(listOf(denied), errors)
    }
}
