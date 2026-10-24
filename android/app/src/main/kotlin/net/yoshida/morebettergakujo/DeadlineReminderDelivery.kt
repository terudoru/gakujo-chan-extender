package net.yoshida.morebettergakujo

/** Delivery history survives rescans even when an inexact alarm fires early. */
internal object DeadlineReminderDelivery {
    // Inexact reminders use two alarms each. Leave room below Android's
    // 500-alarm limit for other work, including alarms from older versions.
    const val MAX_BOOKED_REMINDERS = 150

    fun shouldBook(id: Int, atMillis: Long, now: Long, delivered: Set<Int>): Boolean =
        atMillis > now && id !in delivered

    fun <T> upcoming(
        reminders: List<T>,
        now: Long,
        delivered: Set<Int>,
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

    fun record(delivered: List<Int>, id: Int): List<Int> =
        (delivered.filter { it != id } + id).takeLast(500)
}
