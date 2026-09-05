package net.yoshida.morebettergakujo

import java.net.URLDecoder
import java.util.Locale

internal object GakujoContentDisposition {
    fun fileName(header: String?): String? {
        if (header.isNullOrBlank()) {
            return null
        }

        val parameters = mutableMapOf<String, String>()
        val parameter = Regex("""(?:^|;)\s*([^=;\s]+)\s*=\s*(?:"((?:\\.|[^"\\])*)"|([^;]*))""")
        for (match in parameter.findAll(header)) {
            val key = match.groupValues[1].lowercase(Locale.ROOT)
            val quoted = match.groups[2]?.value
            val value = quoted?.replace(Regex("""\\(.)""")) { it.groupValues[1] }
                ?: match.groupValues[3].trim()
            if (!parameters.containsKey(key)) {
                parameters[key] = value
            }
        }
        val extended = parameters["filename*"]
            ?.let { Regex("""^([^']*)'[^']*'(.+)$""").matchEntire(it) }
        if (extended != null) {
            val charset = extended.groupValues[1].trim().ifBlank { "UTF-8" }
            val encodedName = extended.groupValues[2]
            return runCatching {
                // '+' is literal in filename*, unlike HTML form encoding.
                URLDecoder.decode(encodedName.replace("+", "%2B"), charset)
            }.getOrDefault(encodedName)
        }
        return parameters["filename"]
    }
}
