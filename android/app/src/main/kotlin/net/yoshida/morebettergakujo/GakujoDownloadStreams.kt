package net.yoshida.morebettergakujo

import java.io.InputStream
import java.io.OutputStream

internal object GakujoDownloadStreams {
    fun copy(
        openInput: () -> InputStream,
        openOutput: () -> OutputStream,
        cleanupFailedDestination: (() -> Unit)? = null
    ) {
        try {
            openInput().use { input ->
                openOutput().use { output -> input.copyTo(output) }
            }
        } catch (error: Exception) {
            try {
                cleanupFailedDestination?.invoke()
            } catch (cleanupError: Exception) {
                error.addSuppressed(cleanupError)
            }
            throw error
        }
    }
}
