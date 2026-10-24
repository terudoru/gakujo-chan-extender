package net.yoshida.morebettergakujo

import java.io.InputStream
import java.io.OutputStream

internal object GakujoDownloadStreams {
    fun shouldDeleteFailedPickedDestination(initialSize: Long?): Boolean = initialSize == 0L

    fun haveSameContent(
        firstSize: Long,
        secondSize: Long,
        openFirst: () -> InputStream,
        openSecond: () -> InputStream
    ): Boolean {
        if (firstSize != secondSize) {
            return false
        }
        return openFirst().use { first ->
            openSecond().use { second ->
                val firstBuffer = ByteArray(64 * 1024)
                val secondBuffer = ByteArray(firstBuffer.size)
                var count = first.read(firstBuffer)
                while (count != -1) {
                    var offset = 0
                    while (offset < count) {
                        val read = second.read(secondBuffer, offset, count - offset)
                        if (read == -1) {
                            return false
                        }
                        offset += read
                    }
                    for (index in 0 until count) {
                        if (firstBuffer[index] != secondBuffer[index]) {
                            return false
                        }
                    }
                    count = first.read(firstBuffer)
                }
                second.read() == -1
            }
        }
    }

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
