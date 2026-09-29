package com.festivalscoretracker.android.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.serviceinfo.ServiceBarProgress
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfo
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoPhase
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoRows
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoSnapshot
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoText
import com.festivalscoretracker.android.core.serviceinfo.ServiceProcessState
import com.festivalscoretracker.android.core.serviceinfo.ServiceProgressDisplay
import com.festivalscoretracker.android.core.serviceinfo.ServiceProgressReducer
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.serviceinfo.serviceInfo
import com.festivalscoretracker.android.data.serviceinfo.serviceVersion
import com.festivalscoretracker.android.presentation.settings.ServiceInfoPoller
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.settings.ServiceInfoSection
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Settings Service Info: wire read, progress reducer, copy rules, rows and polling. */
@OptIn(ExperimentalCoroutinesApi::class)
class ServiceInfoTest {
    // region Helpers

    private fun update(status: String = "updating", block: ServiceInfo.CurrentUpdate.() -> ServiceInfo.CurrentUpdate = { this }) =
        ServiceInfo.CurrentUpdate(status = status).block()

    private fun info(
        current: ServiceInfo.CurrentUpdate = update(),
        worker: String? = "online",
        contract: Double? = 2.0,
        plan: ServiceInfo.PhasePlan? = null,
        published: String? = null,
        publication: ServiceInfo.PublicationState? = null,
    ) = ServiceInfo(
        contractVersion = contract,
        phasePlan = plan,
        lastCompletedUpdate = published?.let { ServiceInfo.CompletedUpdate(publishedAt = it) },
        currentUpdate = current,
        publication = publication,
        workerStatus = worker?.let { ServiceInfo.WorkerStatus(it) },
    )

    private fun sub(
        sequence: Double = 1.0,
        percent: Double? = 10.0,
        kind: String? = "exact",
        epoch: Double? = 1.0,
        id: String? = "fetching_leaderboards",
        schema: Double? = 1.0,
        completed: Double? = 10.0,
        total: Double? = 100.0,
        final: Boolean? = true,
    ) = ServiceInfo.SubphaseProgress(schema, id, epoch, sequence, kind, "leaderboards", completed, total, final, percent)

    private fun running(
        sub: ServiceInfo.SubphaseProgress? = sub(),
        attempt: Double? = 1.0,
        ordinal: Double? = 1.0,
        at: String? = "2026-09-28T10:00:00Z",
        phaseId: String? = "scrape_leaderboards",
        subphaseId: String? = "fetching_leaderboards",
    ) = info(
        update {
            copy(
                scrapeId = 11.0, operationId = "op", phaseId = phaseId, subphaseId = subphaseId,
                phaseAttempt = attempt, phaseOrdinal = ordinal, subphaseProgress = sub, lastProgressAt = at,
            )
        },
    )

    private val us = Locale.US
    private val utc = ZoneId.of("UTC")

    // endregion

    // region Wire

    @Test
    fun readsServiceInfoKeylessWithFreezeHeaderAndIgnoresInfrastructureFields() = runBlocking {
        val transport = FakeTransport()
        transport.onRaw("/api/service-info") {
            HttpResult(
                200,
                """{"postgresConnectionTarget":"db.internal:5432","serviceInstance":"pod-7","currentUpdate":{"status":"idle"},
                   "workerStatus":{"status":"online","instanceId":"w1"},"activeScrapeId":null}""".toByteArray(),
                mapOf("X-FST-Public-Read-Freeze-Reason" to "scrape"),
            )
        }
        transport.on("/api/version") { """{"version":" 2026.9.28 "}""" }
        val api = FestivalApi("https://fixture.test", transport)
        val snapshot = api.serviceInfo()
        assertEquals("idle", snapshot.info.currentUpdate.status)
        assertEquals("scrape", snapshot.freezeReasonHeader)
        assertFalse(snapshot.toString().contains("db.internal"))
        assertEquals("2026.9.28", api.serviceVersion())
        val request = transport.sent("/api/service-info").single()
        assertEquals("GET", request.method)
        assertTrue(request.headers.keys.none { it.lowercase() == "x-api-key" || it.lowercase().startsWith("x-fst-selected") || it == "X-FST-Publication-Id" })
        // Unpinned: no publication bootstrap.
        assertTrue(transport.sent("/api/publication").isEmpty())
    }

    @Test
    fun rejectsMalformedBodiesAndVersions() = runBlocking {
        val transport = FakeTransport()
        val api = FestivalApi("https://fixture.test", transport)
        transport.on("/api/service-info") { """{"workerStatus":{}}""" }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { runBlocking { api.serviceInfo() } }
        listOf("\"\"", "\"${"9".repeat(65)}\"", "\"1.0\\u0007\"").forEach { value ->
            transport.on("/api/version") { """{"version":$value}""" }
            assertThrows(FestivalApiException.InvalidResponse::class.java) { runBlocking { api.serviceVersion() } }
        }
        transport.on("/api/service-info", status = 503) { "{}" }
        assertThrows(FestivalApiException::class.java) { runBlocking { api.serviceInfo() } }
        Unit
    }

    // endregion

    // region Reducer

    @Test
    fun idleResetsDisplayAndMemory() {
        val (display, memory) = ServiceProgressReducer.reduce(null, info(update("idle")))
        assertEquals(ServiceProgressDisplay(), display)
        assertNull(memory.operationIdentity)
    }

    @Test
    fun operationIdentityFallsBack() {
        assertNull(ServiceProgressReducer.operationIdentity(info(update())))
        assertEquals(
            "2026-01-01:op:unversioned",
            ServiceProgressReducer.operationIdentity(info(update { copy(operationId = "op", startedAt = "2026-01-01") })),
        )
        assertEquals(
            "5:legacy:v3",
            ServiceProgressReducer.operationIdentity(info(update(), plan = ServiceInfo.PhasePlan("v3")).copy(activeScrapeId = 5.0)),
        )
        assertEquals("1.5", ServiceProgressReducer.format(1.5))
        assertEquals("2", ServiceProgressReducer.format(2.0))
    }

    @Test
    fun exactBarIsMonotonicWithinIdentityAndIgnoresOlderSequences() {
        val (first, memory1) = ServiceProgressReducer.reduce(null, running(sub(sequence = 2.0, percent = 40.0)))
        assertEquals(ServiceBarProgress.Kind.Exact, first.barProgress?.kind)
        assertEquals(40.0, first.barProgress?.percent)
        assertEquals("leaderboards", first.barProgress?.unitsKind)
        // Lower percent, newer sequence: never moves backwards.
        val (second, memory2) = ServiceProgressReducer.reduce(memory1, running(sub(sequence = 3.0, percent = 30.0), at = "2026-09-28T10:00:05Z"))
        assertEquals(40.0, second.barProgress?.percent)
        // Older sequence in the same identity: previous bar kept verbatim.
        val (third, _) = ServiceProgressReducer.reduce(memory2, running(sub(sequence = 1.0, percent = 90.0), at = "2026-09-28T10:00:06Z"))
        assertSame(memory2.display.barProgress, third.barProgress)
    }

    @Test
    fun staleTimestampKeepsPreviousDisplay() {
        val (_, memory) = ServiceProgressReducer.reduce(null, running(at = "2026-09-28T10:00:10Z"))
        val (display, next) = ServiceProgressReducer.reduce(memory, running(sub(percent = 99.0), at = "2026-09-28T10:00:00Z"))
        assertTrue(display.stalePayloadIgnored)
        assertEquals(10.0, display.barProgress?.percent)
        assertEquals(memory.lastProgressTimestamp, next.lastProgressTimestamp)
    }

    @Test
    fun attemptChangeAndOrdinalDropRestart() {
        val (_, memory) = ServiceProgressReducer.reduce(null, running(sub(percent = 80.0), attempt = 1.0, ordinal = 3.0))
        val (retry, _) = ServiceProgressReducer.reduce(memory, running(sub(percent = 5.0), attempt = 2.0, ordinal = 3.0, at = "2026-09-28T09:00:00Z"))
        assertTrue(retry.restarted)
        assertEquals(5.0, retry.barProgress?.percent)
        val (back, _) = ServiceProgressReducer.reduce(memory, running(sub(percent = 5.0), ordinal = 1.0, phaseId = "post_rivals", subphaseId = null))
        assertTrue(back.restarted)
    }

    @Test
    fun unsupportedOrMismatchedOrIncompleteSubphasesAreIndeterminate() {
        listOf(
            sub(schema = 2.0),
            sub(id = "other"),
            sub(kind = "weird"),
            sub(final = false),
            sub(total = 0.0),
            sub(completed = 101.0),
            sub(completed = null),
            sub(percent = Double.NaN),
        ).forEach { raw ->
            val bar = ServiceProgressReducer.reduce(null, running(raw)).first.barProgress
            assertEquals(raw.toString(), ServiceBarProgress.Kind.Indeterminate, bar?.kind)
            assertNull(bar?.percent)
            assertNull(bar?.unitsCompleted)
        }
        val na = ServiceProgressReducer.reduce(null, running(sub(kind = "not_applicable", epoch = null, id = null))).first.barProgress
        assertEquals(ServiceBarProgress.Kind.NotApplicable, na?.kind)
        assertEquals("fetching_leaderboards", na?.id)
        val clamped = ServiceProgressReducer.reduce(null, running(sub(percent = 140.0))).first.barProgress
        assertEquals(100.0, clamped?.percent)
    }

    @Test
    fun legacySubphaseAndPhaseLevelBars() {
        val legacy = ServiceProgressReducer.reduce(null, running(sub = null)).first.barProgress
        assertEquals(ServiceBarProgress.Kind.Indeterminate, legacy?.kind)
        assertTrue(legacy!!.identity.endsWith("fetching_leaderboards:legacy"))

        val phaseInfo = info(
            update {
                copy(
                    scrapeId = 1.0, phaseId = "post_rivals", phasePercent = 55.0, unitsTotalFinal = true,
                    unitsKind = "accounts", unitsCompleted = 55.0, unitsTotal = 100.0, heartbeatAt = "2026-09-28T10:00:00Z",
                )
            },
        )
        val (display, memory) = ServiceProgressReducer.reduce(null, phaseInfo)
        assertEquals(55.0, display.phasePercent)
        assertEquals(ServiceBarProgress.Kind.Exact, display.barProgress?.kind)
        assertEquals(55.0, display.barProgress?.percent)
        // Same phase, lower percent: the phase percent stays monotonic.
        val lower = phaseInfo.copy(currentUpdate = phaseInfo.currentUpdate.copy(phasePercent = 20.0, heartbeatAt = "2026-09-28T10:00:05Z"))
        assertEquals(55.0, ServiceProgressReducer.reduce(memory, lower).first.phasePercent)
        // Legacy (v1) payload without a final total: no phase percent.
        val v1 = info(update { copy(scrapeId = 1.0, phasePercent = 55.0, unitsTotalFinal = true) }, contract = null)
        assertNull(ServiceProgressReducer.reduce(null, v1).first.phasePercent)
        assertEquals(ServiceBarProgress.Kind.Indeterminate, ServiceProgressReducer.reduce(null, v1).first.barProgress?.kind)
    }

    // endregion

    // region Text

    @Test
    fun processAndServiceStates() {
        assertEquals(ServiceProcessState.Stopped, ServiceInfoText.processState(info(worker = null)))
        listOf("offline", "stale", "stopping").forEach { assertEquals(ServiceProcessState.Stopped, ServiceInfoText.processState(info(worker = it))) }
        assertEquals(ServiceProcessState.Updating, ServiceInfoText.processState(info()))
        assertEquals(ServiceProcessState.Idle, ServiceInfoText.processState(info(update("idle"), worker = "starting")))
        assertEquals("Leaderboard Updater Unavailable", ServiceInfoText.serviceState(info(update("idle")), ServiceProcessState.Stopped))
        assertEquals("Last Leaderboard Update Failed", ServiceInfoText.serviceState(info(update("failed")), ServiceProcessState.Stopped))
        assertEquals("Leaderboard Update Stalled", ServiceInfoText.serviceState(info(update("stalled")), ServiceProcessState.Idle))
        assertEquals("Waiting for the Next Update", ServiceInfoText.serviceState(info(update("idle")), ServiceProcessState.Idle))
        assertEquals("Paused Hard", ServiceInfoText.serviceState(info(update("paused_hard")), ServiceProcessState.Idle))
        assertEquals(listOf("Loading", "Updating", "Idle", "Stopped"), ServiceProcessState.entries.map { it.label })
    }

    @Test
    fun phaseAndSubphaseLabels() {
        val display = ServiceProgressDisplay(phaseId = "post.compute-rankings", subphaseId = "per_instrument_rankings")
        val current = info()
        assertEquals("Computing Rankings", ServiceInfoText.phaseLabel(current, display))
        assertEquals("Waiting for the next update", ServiceInfoText.phaseLabel(info(update("idle")), display))
        assertEquals("Waiting for progress", ServiceInfoText.phaseLabel(current, ServiceProgressDisplay()))
        assertEquals("Legacy Phase", ServiceInfoText.phaseLabel(info(update { copy(phase = "Legacy Phase") }), ServiceProgressDisplay()))
        val plan = ServiceInfo.PhasePlan(phases = listOf(ServiceInfo.PhaseDescriptor("new_phase", "Server Label")))
        assertEquals("Server Label", ServiceInfoText.phaseLabel(info(plan = plan), ServiceProgressDisplay(phaseId = "new_phase")))
        assertEquals("New Phase Two", ServiceInfoText.phaseLabel(current, ServiceProgressDisplay(phaseId = "new_phaseTwo")))

        assertEquals("Calculating Instrument Rankings", ServiceInfoText.subphaseLabel(current, display))
        assertNull(ServiceInfoText.subphaseLabel(current, ServiceProgressDisplay()))
        assertNull(ServiceInfoText.subphaseLabel(current, ServiceProgressDisplay(subphaseId = "updating")))
        assertEquals("Cleaning Lead Rank History", ServiceInfoText.subphaseLabel(current, ServiceProgressDisplay(subphaseId = "cleanup_rank_history_Solo_Guitar")))
        assertEquals("Cleaning Duo Rank History", ServiceInfoText.dynamicSubphaseLabel("cleanup_band_rank_history_duo"))
        assertNull(ServiceInfoText.dynamicSubphaseLabel("cleanup_rank_history_"))
        assertNull(ServiceInfoText.dynamicSubphaseLabel("other"))
        assertEquals("Some Op", ServiceInfoText.subphaseLabel(info(update { copy(subOperation = "some.op") }), ServiceProgressDisplay()))

        assertEquals("A", ServiceInfoText.phaseTitle("A", null))
        assertEquals("A", ServiceInfoText.phaseTitle("A", " a "))
        assertEquals("A · B", ServiceInfoText.phaseTitle("A", "B"))
        assertEquals("Step2 Ready Now", ServiceInfoText.fallbackLabel("step2Ready_now"))
    }

    @Test
    fun progressUnitsPublicationAndFreezeText() {
        fun bar(kind: ServiceBarProgress.Kind, percent: Double?, completed: Double?, total: Double?, unit: String?) =
            ServiceBarProgress("i", null, 0.0, kind, percent, unit, completed, total)
        assertEquals("42.5%", ServiceInfoText.progressText(bar(ServiceBarProgress.Kind.Exact, 42.5, null, null, null)))
        assertEquals(ServiceInfoText.PROGRESS_INDETERMINATE, ServiceInfoText.progressText(bar(ServiceBarProgress.Kind.Indeterminate, null, null, null, null)))
        assertEquals(ServiceInfoText.PROGRESS_INDETERMINATE, ServiceInfoText.progressText(null))
        assertEquals("1,234 of 5,000 band types completed", ServiceInfoText.unitsText(bar(ServiceBarProgress.Kind.Exact, 1.0, 1234.0, 5000.0, "band_types"), us))
        assertEquals("3 Widgets Big completed", ServiceInfoText.unitsText(bar(ServiceBarProgress.Kind.Exact, 1.0, 3.0, null, "widgetsBig"), us))
        assertEquals("3 items completed", ServiceInfoText.unitsText(bar(ServiceBarProgress.Kind.Exact, 1.0, 3.0, null, null), us))
        assertNull(ServiceInfoText.unitsText(null, us))

        assertEquals("Sep 28, 2026, 10:00 AM UTC", ServiceInfoText.lastPublished(info(published = "2026-09-28T10:00:00.1234567Z"), utc, us))
        assertEquals(
            "Sep 28, 2026, 10:00 AM UTC",
            ServiceInfoText.lastPublished(info(publication = ServiceInfo.PublicationState(publishedAt = "2026-09-28T12:00:00+02:00")), utc, us),
        )
        assertEquals(ServiceInfoText.PUBLICATION_UNAVAILABLE, ServiceInfoText.lastPublished(info(published = "garbage"), utc, us))
        assertEquals(Instant.parse("2026-09-28T10:00:00.1234567Z"), ServiceInfoText.parseDate(" 2026-09-28T10:00:00.1234567Z "))
        assertNull(ServiceInfoText.parseDate(" "))

        val body = info()
        assertNull(ServiceInfoText.freezeNotice(ServiceInfoSnapshot(body)))
        assertNull(ServiceInfoText.freezeNotice(ServiceInfoSnapshot(body, " ")))
        assertTrue(ServiceInfoText.freezeNotice(ServiceInfoSnapshot(body, "publish"))!!.startsWith("Paused while new scores publish"))
        val frozen = info(publication = ServiceInfo.PublicationState(publicReadsFrozen = true, freezeReason = "max-score-maintenance:v1:x"))
        assertTrue(ServiceInfoText.freezeNotice(ServiceInfoSnapshot(frozen))!!.startsWith("Paused for service maintenance"))
        val frozenNoReason = info(publication = ServiceInfo.PublicationState(publicReadsFrozen = true))
        assertTrue(ServiceInfoText.freezeNotice(ServiceInfoSnapshot(frozenNoReason))!!.startsWith("Paused for service maintenance"))
    }

    // endregion

    // region Rows

    @Test
    fun rowsForEveryPhase() {
        assertEquals(ServiceInfoRows("Loading", ServiceProcessState.Loading), ServiceInfoRows.make(ServiceInfoPhase.Loading))
        assertEquals(ServiceInfoRows("Failed to load data", ServiceProcessState.Stopped), ServiceInfoRows.make(ServiceInfoPhase.Failed))

        val snapshot = ServiceInfoSnapshot(running(sub(percent = 42.5, completed = 425.0, total = 1000.0)))
        val (display, _) = ServiceProgressReducer.reduce(null, snapshot.info)
        val rows = ServiceInfoRows.make(ServiceInfoPhase.Loaded(snapshot, display), utc, us)
        assertEquals("Scraping Leaderboard Scores", rows.stateDescription)
        assertEquals(ServiceProcessState.Updating, rows.processState)
        assertEquals("Scraping Leaderboard Scores · Fetching Leaderboards", rows.phaseTitle)
        assertTrue(rows.showBar)
        assertEquals(42.5, rows.barPercent)
        assertEquals("42.5%", rows.progressText)
        assertEquals("425 of 1,000 leaderboards completed", rows.unitsText)
        assertEquals(ServiceInfoText.PUBLICATION_UNAVAILABLE, rows.lastPublished)
        assertNull(rows.freezeNotice)

        val indeterminate = ServiceInfoSnapshot(running(sub = null))
        val indeterminateRows = ServiceInfoRows.make(ServiceInfoPhase.Loaded(indeterminate, ServiceProgressReducer.reduce(null, indeterminate.info).first))
        assertTrue(indeterminateRows.showBar)
        assertNull(indeterminateRows.barPercent)
        assertEquals(ServiceInfoText.PROGRESS_INDETERMINATE, indeterminateRows.progressText)

        val na = ServiceInfoSnapshot(running(sub(kind = "not_applicable")))
        assertFalse(ServiceInfoRows.make(ServiceInfoPhase.Loaded(na, ServiceProgressReducer.reduce(null, na.info).first)).showBar)

        val idle = ServiceInfoSnapshot(info(update("idle"), published = "2026-09-28T10:00:00Z"), "scrape")
        val idleRows = ServiceInfoRows.make(ServiceInfoPhase.Loaded(idle, ServiceProgressDisplay()), utc, us)
        assertEquals("Waiting for the Next Update", idleRows.stateDescription)
        assertEquals(ServiceProcessState.Idle, idleRows.processState)
        assertNull(idleRows.phaseTitle)
        assertFalse(idleRows.showBar)
        assertNull(idleRows.progressText)
        assertEquals("Sep 28, 2026, 10:00 AM UTC", idleRows.lastPublished)
        assertTrue(idleRows.freezeNotice!!.startsWith("Paused while"))

        // A failed update that still names its phase shows the phase row without a bar.
        val failed = ServiceInfoSnapshot(info(update("failed") { copy(phase = "Scraping") }))
        val failedRows = ServiceInfoRows.make(ServiceInfoPhase.Loaded(failed, ServiceProgressDisplay()))
        assertEquals("Scraping", failedRows.phaseTitle)
        assertFalse(failedRows.showBar)
    }

    // endregion

    // region Poller

    @Test
    fun pollerPollsEveryIntervalUntilCancelledAndShowsFailures() = runTest {
        var reads = 0
        var fail = false
        val poller = ServiceInfoPoller(read = {
            reads++
            if (fail) throw FestivalApiException.Unavailable("5")
            ServiceInfoSnapshot(running(sub(sequence = reads.toDouble(), percent = reads * 10.0), at = "2026-09-28T10:00:0${reads}Z"))
        }, interval = 5.seconds)
        assertEquals(ServiceInfoPhase.Loading, poller.phase.value)
        val job = launch { poller.poll() }
        runCurrent()
        assertEquals(1, reads)
        assertEquals(10.0, (poller.phase.value as ServiceInfoPhase.Loaded).display.barProgress?.percent)
        advanceTimeBy(5_001)
        assertEquals(2, reads)
        assertEquals(20.0, (poller.phase.value as ServiceInfoPhase.Loaded).display.barProgress?.percent)
        fail = true
        advanceTimeBy(5_000)
        assertEquals(ServiceInfoPhase.Failed, poller.phase.value)
        job.cancel()
        advanceTimeBy(60_000)
        assertEquals(3, reads)
        // Memory survives a stop/start (Settings hidden then shown again).
        fail = false
        poller.apply(Result.success(ServiceInfoSnapshot(running(sub(sequence = 9.0, percent = 5.0), at = "2026-09-28T10:00:09Z"))))
        assertEquals(20.0, (poller.phase.value as ServiceInfoPhase.Loaded).display.barProgress?.percent)
    }

    @Test
    fun pollerRethrowsCancellation() = runTest {
        val poller = ServiceInfoPoller(read = { throw CancellationException("stop") })
        assertThrows(CancellationException::class.java) { runBlocking { poller.poll() } }
        assertEquals(ServiceInfoPhase.Loading, poller.phase.value)
    }

    // endregion
}

/** Service Info card rendering for states the phone journey does not reach (Robolectric). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ServiceInfoSectionUiTest {
    @get:Rule
    val rule = createComposeRule()

    private fun render(reduceMotion: Boolean, snapshot: ServiceInfoSnapshot) {
        val poller = ServiceInfoPoller(read = { snapshot })
        rule.setContent {
            FestivalTheme(appReduceMotion = reduceMotion) { Column { ServiceInfoSection(poller) } }
        }
        rule.waitUntil(5_000) { rule.onAllNodesWithTag("fst.settings.service-info.last-published").fetchSemanticsNodes().isNotEmpty() }
    }

    private val indeterminate = ServiceInfoSnapshot(
        ServiceInfo(
            currentUpdate = ServiceInfo.CurrentUpdate(status = "updating", scrapeId = 1.0, phaseId = "post_rivals", subphaseId = "per_song_rivals"),
            workerStatus = ServiceInfo.WorkerStatus("online"),
        ),
        freezeReasonHeader = "publish",
    )

    @Test
    fun indeterminateBarWithFreezeNotice() {
        render(reduceMotion = false, indeterminate)
        rule.onNodeWithTag("fst.settings.service-info.bar", useUnmergedTree = true).assertExists()
        rule.onNodeWithTag("fst.settings.service-info.freeze").assertExists()
        rule.onNodeWithText(ServiceInfoText.PROGRESS_INDETERMINATE, useUnmergedTree = true).assertExists()
    }

    @Test
    fun reducedMotionShowsStillTrack() {
        render(reduceMotion = true, indeterminate)
        rule.onNodeWithTag("fst.settings.service-info.bar", useUnmergedTree = true).assertExists()
        rule.onNodeWithText("Computing Player Rivals · Calculating Player Rivals", useUnmergedTree = true).assertExists()
    }
}
