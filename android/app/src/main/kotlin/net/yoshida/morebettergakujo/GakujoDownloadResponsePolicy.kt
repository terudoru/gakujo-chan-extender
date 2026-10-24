package net.yoshida.morebettergakujo

import java.io.BufferedInputStream
import java.io.InputStream

internal object GakujoDownloadResponsePolicy {
    const val PAGE_RETURNED_MESSAGE =
        "ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください"

    fun openValidated(
        input: InputStream,
        fileName: String,
        mimeType: String?,
        contentDispositionFileName: String? = null
    ): BufferedInputStream {
        val buffered = BufferedInputStream(input)
        try {
            val htmlName = Regex("\\.html?$", RegexOption.IGNORE_CASE)
            val type = mimeType?.substringBefore(';')?.trim().orEmpty()
            val canBePage = listOf("", "text/html", "application/xhtml+xml", "application/octet-stream")
                .any { it.equals(type, ignoreCase = true) }
            if (canBePage && !htmlName.containsMatchIn(fileName.trim()) &&
                !htmlName.containsMatchIn(contentDispositionFileName?.trim().orEmpty())) {
                val prefix = ByteArray(1024)
                // Bound the mark so copying the rest cannot retain the entire file.
                buffered.mark(prefix.size)
                var count = 0
                while (count < prefix.size) {
                    val read = buffered.read(prefix, count, prefix.size - count)
                    if (read == -1) break
                    count += read
                }
                buffered.reset()
                if (Regex(
                    """^\uFEFF?[\x09-\x0D\x20]*(?:<!doctype html|<html)[\x09-\x0D\x20/>]""",
                    RegexOption.IGNORE_CASE
                ).containsMatchIn(String(prefix, 0, count, Charsets.UTF_8))) {
                    throw IllegalStateException(PAGE_RETURNED_MESSAGE)
                }
            }
            return buffered
        } catch (error: Exception) {
            try {
                buffered.close()
            } catch (closeError: Exception) {
                error.addSuppressed(closeError)
            }
            throw error
        }
    }
}
