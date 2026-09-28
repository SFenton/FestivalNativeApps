package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.service.ServiceFreezeReason
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import kotlinx.coroutines.CancellationException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ServiceIssueTest {
    @Test
    fun freezeReasonsSplitLifecycleFromOutage() {
        ServiceFreezeReason.scoreUpdateReasons.forEach { assertTrue(ServiceFreezeReason.isScoreUpdate(it)) }
        assertTrue(ServiceFreezeReason.isScoreUpdate(" Scrape "))
        assertFalse(ServiceFreezeReason.isScoreUpdate("publication-isolation-pending"))
        assertFalse(ServiceFreezeReason.isScoreUpdate("max-score-maintenance:v1:x"))
    }

    @Test
    fun mapsEveryErrorKind() {
        assertEquals(ServiceIssue.ScrapeInProgress(30), ServiceIssue.from(FestivalApiException.PublicReadFrozen("scrape", "30")))
        assertEquals(ServiceIssue.Unavailable(null), ServiceIssue.from(FestivalApiException.PublicReadFrozen("maintenance", "abc")))
        assertEquals(ServiceIssue.Unavailable(12), ServiceIssue.from(FestivalApiException.Unavailable("12")))
        assertEquals(ServiceIssue.Syncing, ServiceIssue.from(FestivalApiException.Syncing()))
        assertEquals(ServiceIssue.NotFound, ServiceIssue.from(FestivalApiException.HttpStatus(404)))
        assertEquals(ServiceIssue.Other("Too many requests. Try again shortly."), ServiceIssue.from(FestivalApiException.HttpStatus(429)))
        assertEquals(ServiceIssue.Other("The app blocked an unsafe request."), ServiceIssue.from(FestivalApiException.ForbiddenRequest()))
        assertEquals(ServiceIssue.Offline, ServiceIssue.from(UnknownHostException()))
        assertEquals(ServiceIssue.Offline, ServiceIssue.from(ConnectException()))
        assertEquals(ServiceIssue.Offline, ServiceIssue.from(SocketTimeoutException()))
        assertEquals(ServiceIssue.Offline, ServiceIssue.from(IOException()))
        assertEquals(ServiceIssue.Other("Something went wrong. Try again."), ServiceIssue.from(IllegalStateException("server text")))
        assertThrows(CancellationException::class.java) { ServiceIssue.from(CancellationException()) }
    }

    @Test
    fun retryAfterParsing() {
        assertEquals(30, ServiceIssue.retryAfterSeconds(" 30 "))
        assertNull(ServiceIssue.retryAfterSeconds("0"))
        assertNull(ServiceIssue.retryAfterSeconds("86401"))
        assertNull(ServiceIssue.retryAfterSeconds("Wed, 21 Oct 2026 07:28:00 GMT"))
        assertNull(ServiceIssue.retryAfterSeconds(null))
    }

    @Test
    fun presentation() {
        val freeze = ServiceIssue.ScrapeInProgress(30)
        assertTrue(freeze.retriesAutomatically)
        assertEquals(30, freeze.retryAfterSeconds)
        assertEquals("Scores are updating", freeze.title)
        assertTrue(freeze.message.contains("automatically"))
        assertFalse(ServiceIssue.Unavailable(5).retriesAutomatically)
        assertEquals(5, ServiceIssue.Unavailable(5).retryAfterSeconds)
        assertEquals("The service is temporarily unavailable. Try again in 5 seconds.", ServiceIssue.Unavailable(5).message)
        assertEquals("The service is temporarily unavailable. Try again.", ServiceIssue.Unavailable(null).message)
        assertNull(ServiceIssue.Unavailable(5).title)
        assertEquals("You're offline", ServiceIssue.Offline.title)
        assertEquals("Check your connection and try again.", ServiceIssue.Offline.message)
        assertEquals("Still syncing", ServiceIssue.Syncing.title)
        assertTrue(ServiceIssue.Syncing.message.isNotBlank())
        assertEquals("This content is no longer available.", ServiceIssue.NotFound.message)
        assertNull(ServiceIssue.NotFound.title)
        assertNull(ServiceIssue.NotFound.retryAfterSeconds)
        assertEquals("custom", ServiceIssue.Other("custom").message)
    }

    @Test
    fun backoffDoublesToCapAndResetsAfterQuietPeriod() {
        var now = 0L
        val backoff = ServiceRetryBackoff { now }
        val delays = (0 until 6).map {
            val delay = backoff.nextDelay("songs", 30)
            now += delay * 1_000L
            delay
        }
        assertEquals(listOf(30, 60, 120, 240, 300, 300), delays)
        now += 10 * 60 * 1_000L
        assertEquals(30, backoff.nextDelay("songs", 30))
        backoff.reset("songs")
        assertEquals(ServiceRetryBackoff.DEFAULT_DELAY, backoff.nextDelay("songs", null))
        assertEquals(1, backoff.nextDelay("other", 0))
        assertEquals(ServiceRetryBackoff.CAP, backoff.nextDelay("big", 9_999))
    }
}
