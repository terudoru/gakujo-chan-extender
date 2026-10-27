package net.yoshida.morebettergakujo

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.security.MessageDigest

class NotificationProofTest {
    @Test fun proofBindsNotificationDestination() {
        val secret = ByteArray(32) { it.toByte() }
        val destination = "https://gakujo.iess.niigata-u.ac.jp/campusweb/page"
        val proof = DeadlineReminders.notificationProof(secret, destination)
        assertArrayEquals(proof, DeadlineReminders.notificationProof(secret, destination))
        assertFalse(MessageDigest.isEqual(proof, DeadlineReminders.notificationProof(secret, "$destination?other=1")))
        assertFalse(MessageDigest.isEqual(proof, DeadlineReminders.notificationProof(ByteArray(32), destination)))
    }
}
