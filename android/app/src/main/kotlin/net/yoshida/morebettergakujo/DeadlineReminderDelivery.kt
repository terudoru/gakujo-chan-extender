package net.yoshida.morebettergakujo

/** Delivery history survives rescans even when an inexact alarm fires early. */
internal object DeadlineReminderDelivery {
    fun shouldBook(id: Int, atMillis: Long, now: Long, delivered: Set<Int>): Boolean =
        atMillis > now && id !in delivered

    fun record(delivered: List<Int>, id: Int): List<Int> =
        (delivered.filter { it != id } + id).takeLast(500)
}
