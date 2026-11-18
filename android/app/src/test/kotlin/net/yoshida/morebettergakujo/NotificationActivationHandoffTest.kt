package net.yoshida.morebettergakujo

import org.junit.Assert.*
import org.junit.Test

class NotificationActivationHandoffTest {
    private data class Delivery(val url: String, val token: String?, val reply: (Boolean) -> Unit)
    private val live = mutableListOf<Delivery>()
    private val state = NotificationActivationHandoff { url, token, reply -> live.add(Delivery(url, token, reply)) }
    private val first = "run:1"
    private val second = "run:2"
    private var input = 0
    private fun tap(url: String) = state.attachIntent((++input).toString(), url, false)

    @Test fun latestBeforeTakeThenEveryTapIsLive() {
        tap("A")
        tap("B")
        assertTrue(live.isEmpty())
        assertEquals("B", state.take(first))
        tap("B")
        tap("A")
        assertEquals(listOf("B", "A"), live.map { it.url })
        assertEquals("B", state.take(first)) // Lost receipt before finish.
        state.finish(first, true)
        assertNull(state.take(first))
        live.last().reply(true)
        assertEquals("A", state.consumedIntentUrl)
    }

    @Test fun delayedResultCannotConsumeOrRestoreNewerIntent() {
        for (url in listOf("A", "B")) for (newAccepted in listOf(true, false)) {
            val token = "test" + input + ":1"
            state.take(token)
            tap("A")
            tap(url)
            val (old, newer) = live.takeLast(2)
            newer.reply(newAccepted)
            old.reply(!newAccepted)
            assertEquals(if (newAccepted) url else null, state.consumedIntentUrl)
            assertNull(state.take(token))
            val next = token.dropLast(1) + "2"
            assertEquals(if (newAccepted) null else url, state.take(next))
            state.finish(next, true)
        }
    }

    @Test fun oldFailureAfterReplacementIsOfferedOnceAndOldDetachIsInert() {
        state.take(first)
        tap("A")
        val old = live.single()
        state.end(first)
        assertNull(state.take(second))
        state.end(first)
        old.reply(false)
        assertEquals(listOf(first, second), live.map { it.token })
        live.last().reply(false)
        assertEquals(2, live.size)
        assertNull(state.take(first))
        assertNull(state.take(second))
        assertEquals("A", state.take("run:3"))
    }

    @Test fun oldSuccessCannotSettleSameUrlStillOwnedByAnotherDelivery() {
        state.take(first)
        tap("A")
        tap("A")
        live.first().reply(true)
        assertNull(state.consumedIntentUrl)
        assertNull(state.take(second))
        live[1].reply(false)
        assertEquals(second, live[2].token)
        live[2].reply(true)
        assertEquals("A", state.consumedIntentUrl)
    }

    @Test fun startupFailureAndLateStartupSettlement() {
        tap("A")
        assertEquals("A", state.take(first))
        state.end(first)
        assertNull(state.take(second))
        state.finish(first, false)
        assertEquals(second, live.single().token)
        state.finish(first, true)
        live.single().reply(false)
        assertEquals("A", state.take("run:3"))
        tap("B")
        live.last().reply(false)
        state.finish("run:3", false)
        assertEquals("B", state.take("run:4"))
    }

    @Test fun isolateTakeoverRecoversOnlyLatestOrphan() {
        state.take(first)
        tap("A")
        assertNull(state.take(second))
        val token = "restart:1"
        assertEquals("A", state.take(token))
        live.single().reply(true)
        state.end(second)
        assertNull(state.take(first))
        assertEquals("A", state.take(token))
        state.finish(token, true)
        assertNull(state.take(token))
    }

    @Test fun recreatedCompletedIntentAndFreshSameUrl() {
        state.attachIntent("launch", "A", true)
        assertNull(state.take(first))
        assertEquals("A", state.consumedIntentUrl)
        state.attachIntent("new", "A", false)
        assertNull(state.consumedIntentUrl)
        state.attachIntent("new", "A", false)
        live.single().reply(true)
        state.attachIntent("new", "A", false)
        assertEquals("A", state.consumedIntentUrl)
        assertEquals(1, live.size)
        val newEngine = NotificationActivationHandoff { _, _, _ -> fail("New engine was ready") }
        newEngine.attachIntent("other", "B", false)
        assertEquals("B", newEngine.take("restart:1"))
    }

    @Test fun legacyReadAndUntaggedLiveReply() {
        tap("A")
        assertEquals("A", state.takeLegacy())
        assertNull(state.takeLegacy())
        tap("B")
        assertNull(live.single().token)
        live.single().reply(false)
        assertEquals("B", state.takeLegacy())
    }
}
