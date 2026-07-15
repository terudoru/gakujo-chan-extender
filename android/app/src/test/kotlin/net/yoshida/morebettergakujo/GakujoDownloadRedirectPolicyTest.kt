package net.yoshida.morebettergakujo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GakujoDownloadRedirectPolicyTest {
    @Test
    fun allowsOnlyGakujoHttpsUrls() {
        assertTrue(
            GakujoDownloadRedirectPolicy.isAllowedUrl(
                "https://gakujo.iess.niigata-u.ac.jp/campusweb/file.pdf"
            )
        )
        assertFalse(
            GakujoDownloadRedirectPolicy.isAllowedUrl(
                "http://gakujo.iess.niigata-u.ac.jp/campusweb/file.pdf"
            )
        )
        assertFalse(
            GakujoDownloadRedirectPolicy.isAllowedUrl(
                "https://example.com/file.pdf"
            )
        )
        assertFalse(
            GakujoDownloadRedirectPolicy.isAllowedUrl(
                "https://gakujo.iess.niigata-u.ac.jp:8443/file.pdf"
            )
        )
        assertFalse(
            GakujoDownloadRedirectPolicy.isAllowedUrl(
                "https://user@gakujo.iess.niigata-u.ac.jp/file.pdf"
            )
        )
    }

    @Test
    fun resolvesRelativeRedirectsOnGakujo() {
        assertEquals(
            "https://gakujo.iess.niigata-u.ac.jp/campusweb/download/file.pdf",
            GakujoDownloadRedirectPolicy.resolveAllowedRedirect(
                "https://gakujo.iess.niigata-u.ac.jp/campusweb/start",
                "download/file.pdf"
            )
        )
    }

    @Test
    fun blocksExternalRedirectBeforeNextRequest() {
        assertNull(
            GakujoDownloadRedirectPolicy.resolveAllowedRedirect(
                "https://gakujo.iess.niigata-u.ac.jp/campusweb/start",
                "https://example.com/steal-cookie"
            )
        )
    }

    @Test
    fun appliesBrowserCompatiblePostRedirectSemantics() {
        assertEquals("GET", GakujoDownloadRedirectPolicy.redirectedMethod(302, "POST"))
        assertEquals("GET", GakujoDownloadRedirectPolicy.redirectedMethod(303, "POST"))
        assertEquals("POST", GakujoDownloadRedirectPolicy.redirectedMethod(307, "POST"))
        assertEquals("GET", GakujoDownloadRedirectPolicy.redirectedMethod(307, "GET"))
    }
}
