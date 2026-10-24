package net.yoshida.morebettergakujo

import java.io.BufferedInputStream
import java.io.InputStream
import java.io.InputStreamReader

internal object GakujoDownloadResponsePolicy {
    const val PAGE_RETURNED_MESSAGE =
        "ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください"

    fun openValidated(input: InputStream, fileName: String, mimeType: String?): BufferedInputStream {
        val buffered = BufferedInputStream(input)
        try {
            if (!Regex("\\.html?$", RegexOption.IGNORE_CASE).containsMatchIn(fileName.trim())) {
                if (mimeType?.substringBefore(';')?.trim()?.equals("text/html", ignoreCase = true) == true) {
                    throw IllegalStateException(PAGE_RETURNED_MESSAGE)
                }
                buffered.mark(Int.MAX_VALUE)
                val reader = InputStreamReader(buffered, Charsets.UTF_8)
                val prefix = StringBuilder()
                while (prefix.length < 14) {
                    val read = reader.read()
                    if (read == -1) break
                    val character = read.toChar()
                    if (prefix.isNotEmpty() || (!character.isWhitespace() && character != '\uFEFF')) {
                        prefix.append(character)
                    }
                }
                buffered.reset()
                if (prefix.startsWith("<!doctype html", ignoreCase = true) ||
                    prefix.startsWith("<html", ignoreCase = true)) {
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
