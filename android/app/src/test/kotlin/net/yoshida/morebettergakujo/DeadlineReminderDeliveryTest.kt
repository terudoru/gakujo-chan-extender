package net.yoshida.morebettergakujo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeadlineReminderDeliveryTest {
    @Test
    fun booksOnlyThe150SoonestEligibleReminders() {
        val reminders = (400 downTo 1).map { it to it * 1000L }
        val upcoming = DeadlineReminderDelivery.upcoming(
            reminders,
            now = 1000L,
            delivered = setOf(DeadlineReminderDelivery.key(2, 2000L)),
            id = { it.first },
            atMillis = { it.second }
        )
        assertEquals((3..152).toList(), upcoming.map { it.first })
        // Two fallback alarms per reminder stay below the per-app limit.
        assertTrue(upcoming.size * 2 < 500)
    }

    @Test
    fun duplicateIdsDoNotConsumeTheBookingBudget() {
        val reminders = listOf(1 to 200L, 1 to 100L, 2 to 300L)
        assertEquals(
            listOf(1 to 100L, 2 to 300L),
            DeadlineReminderDelivery.upcoming(
                reminders, 0L, emptySet(), { it.first }, { it.second }
            )
        )
    }

    @Test
    fun alarmFailuresAreReportedAndDoNotStopLaterOperations() {
        for (failure in listOf(SecurityException("revoked"), IllegalStateException("alarm limit"))) {
            val errors = mutableListOf<Exception>()
            val attempted = mutableListOf<Int>()
            for (id in 1..3) {
                DeadlineReminderDelivery.attempt(onError = { errors.add(it) }) {
                    attempted.add(id)
                    if (id == 1) throw failure
                }
            }
            assertEquals(listOf(1, 2, 3), attempted)
            assertEquals(listOf(failure), errors)
        }
    }

    @Test
    fun earlyDeliveryIsNotBookedAgainBeforeItsPlannedTime() {
        val at = 11 * 60 * 60 * 1000L
        assertTrue(DeadlineReminderDelivery.shouldBook(42, at, at - 20 * 60 * 1000L, emptySet()))

        // Delivered at 10:45, then rescanned at 10:50 (or restored after reboot).
        val delivered = DeadlineReminderDelivery.record(emptyList(), 42, at)
        assertFalse(DeadlineReminderDelivery.shouldBook(42, at, at - 10 * 60 * 1000L, delivered.toSet()))
        assertTrue(DeadlineReminderDelivery.shouldBook(43, at, at - 10 * 60 * 1000L, delivered.toSet()))
    }

    @Test
    fun extendedDeadlineWithTheSameIdCanBeBookedAndDelivered() {
        val originalAt = 1000L
        val extendedAt = 2000L
        val delivered = DeadlineReminderDelivery.record(emptyList(), 42, originalAt)
        assertFalse(DeadlineReminderDelivery.shouldBook(42, originalAt, 900L, delivered.toSet()))
        assertTrue(DeadlineReminderDelivery.shouldBook(42, extendedAt, 900L, delivered.toSet()))
        val next = DeadlineReminderDelivery.record(delivered, 42, extendedAt)
        assertEquals(
            listOf(DeadlineReminderDelivery.key(42, originalAt), DeadlineReminderDelivery.key(42, extendedAt)),
            next
        )
        assertFalse(DeadlineReminderDelivery.shouldBook(42, extendedAt, 1900L, next.toSet()))
    }

    @Test
    fun deliveryHistoryKeepsOnlyTheLast500DistinctIdAndTimePairs() {
        val delivered = (1..501).fold(emptyList<String>()) { history, at ->
            DeadlineReminderDelivery.record(history, 42, at.toLong())
        }
        assertEquals((2..501).map { DeadlineReminderDelivery.key(42, it.toLong()) }, delivered)
        val repeated = DeadlineReminderDelivery.record(delivered, 42, 2L)
        assertEquals(500, repeated.size)
        assertEquals(DeadlineReminderDelivery.key(42, 2L), repeated.last())
        assertEquals(1, repeated.count { it == DeadlineReminderDelivery.key(42, 2L) })
    }

    @Test
    fun eachEarlyDeliveryRefillsThe150SlotsFromTheFullSavedList() {
        val saved = (1..200).map { it to 1000000L + it * 1000L }
        var delivered = emptyList<String>()
        fun upcoming() = DeadlineReminderDelivery.upcoming(
            saved, 999999L, delivered.toSet(), { it.first }, { it.second }
        )
        assertEquals((1..150).toList(), upcoming().map { it.first })
        for (id in 1..50) {
            val reminder = upcoming().first()
            assertEquals(id, reminder.first)
            delivered = DeadlineReminderDelivery.record(delivered, reminder.first, reminder.second)
            val rebooked = upcoming()
            assertEquals(150, rebooked.size)
            assertEquals((id + 1..id + 150).toList(), rebooked.map { it.first })
        }
        assertEquals(200, upcoming().last().first)
    }

    @Test
    fun elapsedRemindersAreNotBookedEvenWithoutDeliveryHistory() {
        assertFalse(DeadlineReminderDelivery.shouldBook(42, 100L, 100L, emptySet()))
        assertFalse(DeadlineReminderDelivery.shouldBook(42, 99L, 100L, emptySet()))
    }
}
