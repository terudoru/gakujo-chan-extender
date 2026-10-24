package net.yoshida.morebettergakujo

import java.util.Locale

internal object GakujoDownloadMimeType {
    fun forFileName(fileName: String, lookup: (String) -> String?): String {
        val extension = fileName.substringAfterLast('.', "").lowercase(Locale.ROOT)
        return extension.takeIf { it.isNotEmpty() }?.let(lookup) ?: "application/octet-stream"
    }
}
