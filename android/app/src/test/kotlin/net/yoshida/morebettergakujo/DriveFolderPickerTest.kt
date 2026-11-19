package net.yoshida.morebettergakujo

import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DriveFolderPickerTest {
    private class Reply : MethodChannel.Result {
        val successes = mutableListOf<Any?>()
        val errors = mutableListOf<String>()
        override fun success(result: Any?) { successes.add(result) }
        override fun error(code: String, message: String?, details: Any?) { errors.add(code) }
        override fun notImplemented() = throw AssertionError("Unexpected method")
    }

    @Test
    fun busyRequestsCannotReplaceTheOriginalReply() {
        val requests = DriveFolderPickRequests()
        val busy = Reply()
        assertNull(requests.begin(busy, pickerActive = true))
        val first = Reply()
        val code = requests.begin(first, pickerActive = false)!!
        assertNull(requests.begin(busy, pickerActive = false))
        requests.selected(code, "folder-a")
        requests.cancel(code)
        assertEquals(listOf("picker_busy", "picker_busy"), busy.errors)
        assertEquals(listOf("folder-a"), first.successes)
        assertNull(requests.activeCode)
    }

    @Test
    fun lateAuthorizationAndActivityResultsCannotCompleteANewPickAfterRecreation() {
        val old = DriveFolderPickRequests()
        val interrupted = Reply()
        val oldCode = old.begin(interrupted, false)!!
        val recreated = DriveFolderPickRequests(old.nextCode)
        old.interrupt()
        val current = Reply()
        val newCode = recreated.begin(current, false)!!
        old.selected(oldCode, "stale-authorization")
        recreated.selected(oldCode, "stale-activity-result")
        assertNotEquals(oldCode, newCode)
        assertEquals(listOf("picker_interrupted"), interrupted.errors)
        assertEquals(emptyList<Any?>(), interrupted.successes)
        assertEquals(newCode, recreated.activeCode)
        recreated.selected(newCode, "new-folder")
        assertEquals(listOf("new-folder"), current.successes)
    }

    @Test
    fun cancelWhileAuthorizingAllowsImmediateRepickAndIgnoresTheOldCallbacks() {
        val requests = DriveFolderPickRequests()
        val launches = mutableListOf<Int>()
        val closes = mutableListOf<Int>()
        val first = Reply()
        val oldCode = requests.begin(first, false)!!
        requests.cancelPending { closes.add(it) }

        val retry = Reply()
        val newCode = requests.begin(retry, false)!!
        requests.launchResolution(oldCode) { launches.add(oldCode) }
        requests.selected(oldCode, "stale-folder")
        requests.failed(oldCode, IllegalStateException())
        requests.launchResolution(newCode) { launches.add(newCode) }
        requests.selected(newCode, "current-folder")

        assertEquals(emptyList<Int>(), closes)
        assertEquals(listOf(newCode), launches)
        assertEquals(listOf(null), first.successes)
        assertEquals(listOf("current-folder"), retry.successes)
        assertEquals(emptyList<String>(), first.errors + retry.errors)
    }

    @Test
    fun cancelClosesOnlyItsLaunchedActivityAndIgnoresItsLateResultEvenIfItCannotClose() {
        val requests = DriveFolderPickRequests()
        val first = Reply()
        val oldCode = requests.begin(first, false)!!
        requests.launchResolution(oldCode) {}
        val closes = mutableListOf<Int>()
        requests.cancelPending {
            closes.add(it)
            throw IllegalStateException("External activity already gone")
        }
        requests.cancelPending { closes.add(it) }

        val retry = Reply()
        val newCode = requests.begin(retry, false)!!
        requests.cancel(oldCode)
        requests.selected(oldCode, "stale-folder")
        requests.selected(newCode, "current-folder")
        assertEquals(listOf(oldCode), closes)
        assertEquals(listOf(null), first.successes)
        assertEquals(listOf("current-folder"), retry.successes)
        assertEquals(emptyList<String>(), first.errors + retry.errors)
    }

    @Test
    fun aSuccessfulResponseMustContainExactlyOneFolderId() {
        val requests = DriveFolderPickRequests()
        for (invalid in listOf(null, "", " ", "a,b", "a,")) {
            val reply = Reply()
            requests.selected(requests.begin(reply, false)!!, invalid)
            assertEquals(listOf("invalid_picker_result"), reply.errors)
            assertEquals(emptyList<Any?>(), reply.successes)
            assertNull(requests.activeCode)
        }
    }

    @Test
    fun cancellationAndProviderFailureAllowRetryWithDifferentOutcomes() {
        val requests = DriveFolderPickRequests()
        val reply = Reply()
        requests.cancel(requests.begin(reply, false)!!)
        requests.failed(requests.begin(reply, false)!!, ApiException(Status(CommonStatusCodes.CANCELED)))
        requests.failed(requests.begin(reply, false)!!, ApiException(Status(CommonStatusCodes.NETWORK_ERROR)))
        requests.failed(requests.begin(reply, false)!!, IllegalStateException("unavailable"))
        assertEquals(listOf(null, null), reply.successes)
        assertEquals(listOf("drive_picker_failed", "drive_picker_failed"), reply.errors)
        assertNull(requests.activeCode)
    }
}
