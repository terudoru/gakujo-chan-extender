package net.yoshida.morebettergakujo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeadlineReminderDeliveryTest {
    @Test
    fun earlyDeliveryIsNotBookedAgainBeforeItsPlannedTime() {
        val at = 11 * 60 * 60 * 1000L
        assertTrue(DeadlineReminderDelivery.shouldBook(42, at, at - 20 * 60 * 1000L, emptySet()))

        // Delivered at 10:45, then rescanned at 10:50 (or restored after reboot).
        val delivered = DeadlineReminderDelivery.record(emptyList(), 42)
        assertFalse(DeadlineReminderDelivery.shouldBook(42, at, at - 10 * 60 * 1000L, delivered.toSet()))
        assertTrue(DeadlineReminderDelivery.shouldBook(43, at, at - 10 * 60 * 1000L, delivered.toSet()))
    }

    @Test
    fun deliveryHistoryKeepsOnlyTheLast500DistinctIds() {
        val delivered = (1..501).fold(emptyList<Int>()) { history, id ->
            DeadlineReminderDelivery.record(history, id)
        }
        assertEquals((2..501).toList(), delivered)
        val repeated = DeadlineReminderDelivery.record(delivered, 2)
        assertEquals(500, repeated.size)
        assertEquals(2, repeated.last())
        assertEquals(1, repeated.count { it == 2 })
    }

    @Test
    fun elapsedRemindersAreNotBookedEvenWithoutDeliveryHistory() {
        assertFalse(DeadlineReminderDelivery.shouldBook(42, 100L, 100L, emptySet()))
        assertFalse(DeadlineReminderDelivery.shouldBook(42, 99L, 100L, emptySet()))
    }
}
