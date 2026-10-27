package net.yoshida.morebettergakujo

import java.io.InputStream
import java.io.OutputStream

internal object GakujoDownloadStreams {
    const val MAX_DOWNLOAD_BYTES = 128L * 1024 * 1024
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
        cleanupFailedDestination: (() -> Unit)? = null,
        maxBytes: Long = MAX_DOWNLOAD_BYTES
    ) {
        require(maxBytes >= 0)
        try {
            openInput().use { input ->
                openOutput().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count == -1) break
                        if (count == 0) {
                            val single = input.read()
                            if (single == -1) break
                            if (total >= maxBytes) {
                                throw java.io.IOException("ダウンロードが大きすぎます")
                            }
                            output.write(single)
                            total++
                            continue
                        }
                        if (count.toLong() > maxBytes - total) {
                            throw java.io.IOException("ダウンロードが大きすぎます")
                        }
                        output.write(buffer, 0, count)
                        total += count
                    }
                }
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
