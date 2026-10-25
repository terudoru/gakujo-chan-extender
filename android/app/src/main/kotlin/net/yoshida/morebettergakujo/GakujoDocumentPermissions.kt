package net.yoshida.morebettergakujo

import android.content.Intent

internal object GakujoDocumentPermissions {
    fun replaceRoot(
        previousUri: String?,
        newUri: String,
        persist: () -> Unit,
        release: (String) -> Unit,
        onReleaseDenied: (SecurityException) -> Unit
    ) {
        persist()
        if (previousUri.isNullOrBlank() || previousUri == newUri) {
            return
        }
        try {
            release(previousUri)
        } catch (error: SecurityException) {
            onReleaseDenied(error)
        }
    }

    fun persistIfOffered(
        flags: Int,
        persist: (Int) -> Unit,
        onDenied: (SecurityException) -> Unit
    ) {
        if (flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION == 0) {
            return
        }
        val offered = flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            persist(offered)
        } catch (error: SecurityException) {
            onDenied(error)
        }
    }
}
