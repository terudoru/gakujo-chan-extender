package net.yoshida.morebettergakujo

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class GakujoDocumentPermissionsTest {
    private val readWrite = Intent.FLAG_GRANT_READ_URI_PERMISSION or
        Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    @Test
    fun replacingRootPersistsTheNewGrantBeforeReleasingOnlyTheOldRoot() {
        val oldRoot = "content://provider/tree/old"
        val newRoot = "content://provider/tree/new"
        val file = "content://provider/document/file.pdf"
        val grants = mutableSetOf(oldRoot, file)
        GakujoDocumentPermissions.replaceRoot(
            oldRoot,
            newRoot,
            persist = { grants.add(newRoot) },
            release = {
                assertEquals(setOf(oldRoot, newRoot, file), grants)
                assertEquals(oldRoot, it)
                grants.remove(it)
            },
            onReleaseDenied = { fail("Old root should release") }
        )
        assertEquals(setOf(newRoot, file), grants)
    }

    @Test
    fun firstSelectionAndReselectingTheSameRootDoNotReleaseAnything() {
        for (oldRoot in listOf(null, "", "content://provider/tree/new")) {
            var persisted = false
            GakujoDocumentPermissions.replaceRoot(
                oldRoot,
                "content://provider/tree/new",
                persist = { persisted = true },
                release = { fail("No old root should release") },
                onReleaseDenied = { fail("No release was expected") }
            )
            assertEquals(true, persisted)
        }
    }

    @Test
    fun failedNewRootPersistenceKeepsTheOldGrant() {
        val denied = SecurityException("Provider refused")
        try {
            GakujoDocumentPermissions.replaceRoot(
                "content://provider/tree/old",
                "content://provider/tree/new",
                persist = { throw denied },
                release = { fail("Old root must remain after persistence fails") },
                onReleaseDenied = { fail("No release was expected") }
            )
            fail("Persistence failure must reach the caller")
        } catch (error: SecurityException) {
            assertEquals(denied, error)
        }
    }

    @Test
    fun revokedOldRootDoesNotFailTheNewSelection() {
        val denied = SecurityException("Old grant was already revoked")
        val operations = mutableListOf<String>()
        GakujoDocumentPermissions.replaceRoot(
            "content://provider/tree/old",
            "content://provider/tree/new",
            persist = { operations.add("persist") },
            release = { throw denied },
            onReleaseDenied = {
                assertEquals(denied, it)
                operations.add("release denied")
            }
        )
        assertEquals(listOf("persist", "release denied"), operations)
    }

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
