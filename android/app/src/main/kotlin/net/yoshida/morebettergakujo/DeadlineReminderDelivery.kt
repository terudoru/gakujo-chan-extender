package net.yoshida.morebettergakujo

/** Delivery history survives rescans even when an inexact alarm fires early. */
internal object DeadlineReminderDelivery {
    // Inexact reminders use two alarms each. Leave room below Android's
    // 500-alarm limit for other work, including alarms from older versions.
    const val MAX_BOOKED_REMINDERS = 150
    private const val LEGACY_WINDOW_MILLIS = 2 * 60 * 60 * 1000L

    fun key(id: Int, atMillis: Long): String = key(id.toString(), atMillis)

    fun key(stableKey: String, atMillis: Long): String = "$stableKey|$atMillis"

    fun readHistory(values: List<*>, now: Long = System.currentTimeMillis()): List<String> = values.mapNotNull {
        when (it) {
            is String -> if (it.toIntOrNull() != null) "legacy|$it|$now" else it
            is Number -> "legacy|${it.toInt()}|$now"
            else -> null
        }
    }.filter { !it.startsWith("legacy|") || isActiveLegacy(it, now) }.takeLast(500)

    private fun isActiveLegacy(value: String, now: Long): Boolean =
        value.substringAfterLast('|').toLongOrNull()?.let { now < it + LEGACY_WINDOW_MILLIS } == true

    fun wasDelivered(
        id: Int, atMillis: Long, now: Long, delivered: Set<String>,
        stableKey: String = id.toString(), legacyIds: List<Int> = emptyList()
    ): Boolean = key(stableKey, atMillis) in delivered || (listOf(id) + legacyIds).any { previousId ->
        key(previousId, atMillis) in delivered ||
            // Legacy history only covers early delivery during the migration window.
            (atMillis - now <= LEGACY_WINDOW_MILLIS && delivered.any {
                it.startsWith("legacy|$previousId|") && isActiveLegacy(it, now)
            })
    }

    fun shouldBook(
        id: Int, atMillis: Long, now: Long, delivered: Set<String>,
        stableKey: String = id.toString(), legacyIds: List<Int> = emptyList()
    ): Boolean = atMillis > now && !wasDelivered(id, atMillis, now, delivered, stableKey, legacyIds)

    fun <T> upcoming(
        reminders: List<T>,
        now: Long,
        delivered: Set<String>,
        id: (T) -> Int,
        atMillis: (T) -> Long,
        stableKey: (T) -> String = { id(it).toString() },
        legacyIds: (T) -> List<Int> = { emptyList() }
    ): List<T> = reminders
        .filter { shouldBook(id(it), atMillis(it), now, delivered, stableKey(it), legacyIds(it)) }
        .sortedBy(atMillis)
        .distinctBy(id)
        .take(MAX_BOOKED_REMINDERS)

    fun attempt(onError: (Exception) -> Unit, operation: () -> Unit) {
        try {
            operation()
        } catch (error: Exception) {
            onError(error)
        }
    }

    fun record(
        delivered: List<String>, id: Int, atMillis: Long, now: Long = System.currentTimeMillis(),
        stableKey: String = id.toString()
    ): List<String> {
        val key = key(stableKey, atMillis)
        return (readHistory(delivered, now).filter { it != key } + key).takeLast(500)
    }
}
