package net.yoshida.morebettergakujo

/** Delivery history survives rescans even when an inexact alarm fires early. */
internal object DeadlineReminderDelivery {
    // Inexact reminders use two alarms each. Leave room below Android's
    // 500-alarm limit for other work, including alarms from older versions.
    const val MAX_BOOKED_REMINDERS = 150

    fun key(id: Int, atMillis: Long): String = "$id|$atMillis"

    fun readHistory(values: List<*>): List<String> = values.mapNotNull {
        when (it) {
            is String -> it
            is Number -> it.toInt().toString()
            else -> null
        }
    }.takeLast(500)

    fun shouldBook(id: Int, atMillis: Long, now: Long, delivered: Set<String>): Boolean =
        atMillis > now && key(id, atMillis) !in delivered &&
            // Legacy id-only history covers early delivery, not a later extension.
            (id.toString() !in delivered || atMillis - now > 2 * 60 * 60 * 1000L)

    fun <T> upcoming(
        reminders: List<T>,
        now: Long,
        delivered: Set<String>,
        id: (T) -> Int,
        atMillis: (T) -> Long
    ): List<T> = reminders
        .filter { shouldBook(id(it), atMillis(it), now, delivered) }
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

    fun record(delivered: List<String>, id: Int, atMillis: Long): List<String> {
        val key = key(id, atMillis)
        return (delivered.filter { it != key } + key).takeLast(500)
    }
}
