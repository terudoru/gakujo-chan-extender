package net.yoshida.morebettergakujo

import java.net.URI

internal object GakujoDownloadRedirectPolicy {
    const val maxRedirects = 10

    fun isAllowedUrl(rawUrl: String?): Boolean {
        if (rawUrl.isNullOrBlank()) {
            return false
        }
        val uri = runCatching { URI(rawUrl) }.getOrNull() ?: return false
        return uri.scheme.equals("https", ignoreCase = true) &&
            uri.host.equals("gakujo.iess.niigata-u.ac.jp", ignoreCase = true) &&
            (uri.port == -1 || uri.port == 443) &&
            uri.userInfo == null
    }

    fun resolveAllowedRedirect(currentUrl: String, location: String): String? {
        val resolved = runCatching {
            URI(currentUrl).resolve(location).toString()
        }.getOrNull() ?: return null
        return resolved.takeIf(::isAllowedUrl)
    }

    fun isRedirectStatus(statusCode: Int): Boolean {
        return statusCode == 301 ||
            statusCode == 302 ||
            statusCode == 303 ||
            statusCode == 307 ||
            statusCode == 308
    }

    fun redirectedMethod(statusCode: Int, currentMethod: String): String {
        val normalized = if (currentMethod.equals("POST", ignoreCase = true)) "POST" else "GET"
        return if (
            normalized == "POST" &&
            (statusCode == 301 || statusCode == 302 || statusCode == 303)
        ) {
            "GET"
        } else {
            normalized
        }
    }
}
