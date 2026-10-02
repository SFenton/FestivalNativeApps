package com.festivalscoretracker.android.settings

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import com.festivalscoretracker.android.ui.notifications.NotificationMediaKind
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performCustomAccessibilityActionWithLabel
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.firstrun.FirstRunCatalog
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.LicensesRoute
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.settings.PathColumnKey
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.firstrun.FIRST_RUN_DEMO_IDS
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Settings, Licenses, first-run and notifications journeys on a phone window (Robolectric, synthetic fixtures). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@OptIn(androidx.compose.ui.test.ExperimentalTestApi::class)
class SettingsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val store = InMemoryPreferences()
    private val stored: AppSettings get() = SettingsRepository.decode(store.current)

    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/player/${Fixtures.ACCOUNT_A}/notifications", headers = mapOf("X-FST-Publication-Id" to "7")) {
            """{"sourceRunId":3,"items":[
              {"eventId":1,"notificationGuid":"n-song","eventKind":"player_score_pb","songId":"s-alpha","instrument":"Solo_Guitar","newNumeric":123456,"detectedAt":"2026-09-28T11:00:00Z"},
              {"eventId":2,"notificationGuid":"n-total","eventKind":"player_total_score_improved","newNumeric":5,"detectedAt":"2026-09-27T11:00:00Z"}]}"""
        }
    }

    init {
        transport.on("/api/service-info") {
            """{"contractVersion":2,"postgresConnectionTarget":"secret-host","serviceInstance":"node-1",
              "workerStatus":{"status":"online"},
              "lastCompletedUpdate":{"publishedAt":"2026-09-28T10:00:00.1234567Z"},
              "currentUpdate":{"status":"updating","scrapeId":11,"operationId":"op","phaseId":"scrape_leaderboards",
                "subphaseId":"fetching_leaderboards","phaseAttempt":1,"phaseOrdinal":1,
                "subphaseProgress":{"schemaVersion":1,"id":"fetching_leaderboards","epoch":1,"sequence":3,"kind":"exact",
                  "unitsKind":"leaderboards","unitsCompleted":425,"unitsTotal":1000,"unitsTotalFinal":true,"percent":42.5}}}"""
        }
        transport.on("/api/version") { """{"version":"9.9.9"}""" }
    }

    private fun launch(debug: DebugLaunch) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = store)
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
        rule.waitForIdle()
    }

    private fun waitForTag(tag: String) = rule.waitUntil(10_000) {
        settle(100)
        rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }

    private fun waitGone(tag: String) = rule.waitUntil(10_000) {
        settle(100)
        rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()
    }

    private fun tap(tag: String) {
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag(tag))
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    /** Reorder rows have no arrow buttons (web look); TalkBack's custom actions move them. */
    private fun moveRow(tag: String, action: String) {
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag(tag))
        rule.onNodeWithTag(tag).performCustomAccessibilityActionWithLabel(action)
        settle()
    }

    private val settingsTab = DebugLaunch(section = FestivalSection.Settings, stillBackground = true)

    @Test
    fun everySettingPersistsAndPropagates() {
        launch(settingsTab)
        waitForTag("fst.settings.list")
        tap("fst.settings.show-instrument-icons")
        tap("fst.settings.enable-visual-order")
        moveRow("fst.settings.song-row-order.0", "Move down")
        tap("fst.settings.path-default-view.text")
        moveRow("fst.settings.path-column-order.4", "Move up")
        tap("fst.settings.filter-invalid-scores")
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag("fst.settings.leeway"))
        rule.onNodeWithTag("fst.settings.leeway").performSemanticsAction(SemanticsActions.SetProgress) { it(2.5f) }
        settle()
        tap("fst.settings.tap-telemetry") // disabled until diagnostics
        tap("fst.settings.tap-diagnostics")
        tap("fst.settings.tap-telemetry")
        tap("fst.settings.hide-shop")
        rule.onNodeWithTag("fst.settings.disable-shop-highlighting").assertIsNotEnabled()
        Instrument.entries.drop(1).forEach { tap("fst.settings.instrument.${it.wireId}") }
        tap("fst.settings.instrument.${Instrument.Lead.wireId}") // last one stays on
        rule.onNodeWithTag("fst.settings.instrument.${Instrument.Lead.wireId}").assertIsNotEnabled()
        tap("fst.settings.metadata.last-played")
        tap("fst.settings.motion")
        tap("fst.settings.still-artwork")
        tap("fst.settings.contrast")
        tap("fst.settings.transparency")

        val s = stored
        assertFalse(s.showInstrumentIcons)
        assertTrue(s.enableVisualOrder)
        assertEquals(MetadataField.Percentage, s.songRowVisualOrder.first())
        assertEquals(PathDisplayMode.Text, s.pathDefaultView)
        assertEquals(PathColumnKey.Score, s.pathColumnOrder[3])
        assertTrue(s.filterInvalidScores)
        assertEquals(2.5, s.leeway, 0.0)
        assertTrue(s.tapDiagnostics && s.tapTelemetry)
        assertTrue(s.hideShop)
        assertFalse(s.shopHighlightEnabled)
        assertEquals(setOf(Instrument.Lead), s.visibleInstruments)
        assertFalse(MetadataField.LastPlayed in s.visibleMetadata)
        assertTrue(s.reduceMotion && s.disableAnimatedArtwork && s.increaseContrast && s.reduceTransparency)

        // Reset: cancel keeps everything; confirm restores app settings only.
        tap("fst.settings.reset")
        rule.onNodeWithTag("fst.settings.reset.cancel").performClick()
        settle()
        assertTrue(stored.hideShop)
        tap("fst.settings.reset")
        rule.onNodeWithTag("fst.settings.reset.confirm").performClick()
        settle()
        assertEquals(AppSettings(), stored)
    }

    @Test
    fun quickLinksSheetJumpsToLiveServiceInfo() {
        launch(settingsTab)
        waitForTag("fst.quick-links.open")
        rule.onNodeWithTag("fst.quick-links.open").performClick()
        waitForTag("fst.quick-links.sheet")
        rule.onNodeWithTag("fst.quick-links.item.service-info").performSemanticsAction(SemanticsActions.OnClick)
        waitGone("fst.quick-links.sheet")
        waitForTag("fst.settings.service-info")
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag("fst.settings.service-info.phase").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("Scraping Leaderboard Scores · Fetching Leaderboards", useUnmergedTree = true).assertExists()
        rule.onNodeWithText("42.5%", useUnmergedTree = true).assertExists()
        rule.onNodeWithText("Updating").assertExists()
        rule.onNodeWithTag("fst.settings.service-info.last-published").assertExists()
        // Keyless, and the version row filled from /api/version.
        assertTrue(transport.sent("/api/service-info").isNotEmpty())
        assertTrue(transport.sent("/api/service-info").all { request -> request.headers.keys.none { it.lowercase().startsWith("x-fst-selected") || it.lowercase() == "x-api-key" } })
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag("fst.settings.service-version"))
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithText("9.9.9").fetchSemanticsNodes().isNotEmpty() }
        // The list scrolled, so the floating toolbar slid away (hide-on-scroll); activate it semantically.
        rule.onNodeWithTag("fst.quick-links.open").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.quick-links.item.reset")
        rule.onNodeWithTag("fst.quick-links.item.reset").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.settings.reset")
        rule.onNodeWithTag("fst.settings.reset").assertIsDisplayed()
    }

    @Test
    fun quickLinksLandSectionTitles32DpBelowTheTopBar() {
        launch(settingsTab)
        listOf("show-instruments", "accessibility").forEach { id ->
            waitForTag("fst.quick-links.open")
            rule.onNodeWithTag("fst.quick-links.open").performSemanticsAction(SemanticsActions.OnClick)
            waitForTag("fst.quick-links.item.$id")
            rule.onNodeWithTag("fst.quick-links.item.$id").performSemanticsAction(SemanticsActions.OnClick)
            waitGone("fst.quick-links.sheet")
            settle()
            // #51: the section lands 32 dp below the visible top (the top bar's bottom edge), not flush with it.
            val listTop = rule.onNodeWithTag("fst.settings.list").getUnclippedBoundsInRoot().top
            val sectionTop = rule.onNodeWithTag("fst.settings.section.$id").getUnclippedBoundsInRoot().top
            assertEquals(32f, (sectionTop - listTop).value, 1f)
            // The activation line matches the landing line, so the landed section is the current one.
            val title = if (id == "show-instruments") "Show Instruments" else "Accessibility"
            rule.onNodeWithTag("fst.quick-links.open").assert(
                SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Quick Links, current section $title")),
            )
        }
    }

    @Test
    fun licensesListOpensFullText() {
        launch(DebugLaunch(route = LicensesRoute, stillBackground = true))
        waitForTag("fst.licenses.list")
        rule.onNodeWithText("Open Source Software").assertIsDisplayed()
        rule.onNodeWithTag("fst.licenses.list").performScrollToNode(hasTestTag("fst.licenses.row.com.squareup.okhttp3:okhttp"))
        rule.onNodeWithTag("fst.licenses.row.com.squareup.okhttp3:okhttp").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.licenses.text")
        rule.onNodeWithText("Apache License", substring = true).assertExists()
        // Centred Close dismisses the sheet; the Bundled Assets section is gone (batch 6.17).
        rule.onNodeWithTag("fst.licenses.close").performSemanticsAction(SemanticsActions.OnClick)
        waitGone("fst.licenses.detail")
        assertTrue(rule.onAllNodesWithText("Bundled Assets").fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun firstRunShowsUnseenSlidesOnceAndSettingsReplayShowsAll() {
        launch(DebugLaunch(stillBackground = true, firstRun = "on"))
        waitForTag("fst.first-run.dialog")
        rule.onNodeWithTag("fst.first-run.slide.songs-song-list").assertIsDisplayed()
        // No visible "Slide x of y"; TalkBack reads it from the dots' state.
        assertTrue(rule.onAllNodesWithText("Slide 1 of 6").fetchSemanticsNodes().isEmpty())
        assertEquals("Slide 1 of 6", rule.onNodeWithTag("fst.first-run.position").fetchSemanticsNode().config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.StateDescription))
        rule.onNodeWithTag("fst.first-run.next").performClick()
        settle()
        rule.onNodeWithTag("fst.first-run.back").performClick()
        settle()
        rule.onNodeWithTag("fst.first-run.close").performClick()
        waitGone("fst.first-run.dialog")
        // Only the two displayed slides count as seen (batch 6.7): the next visit shows the other four.
        rule.onNodeWithTag("fst.nav.tab.settings").performClick()
        waitForTag("fst.settings.list")
        rule.onNodeWithTag("fst.nav.tab.songs").performClick()
        waitForTag("fst.first-run.dialog")
        assertEquals("Slide 1 of 4", rule.onNodeWithTag("fst.first-run.position").fetchSemanticsNode().config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.StateDescription))
        repeat(3) {
            rule.onNodeWithTag("fst.first-run.next").performClick()
            settle()
        }
        rule.onNodeWithTag("fst.first-run.done").performClick()
        waitGone("fst.first-run.dialog")
        // Every slide seen now: nothing on the next visit.
        rule.onNodeWithTag("fst.nav.tab.settings").performClick()
        waitForTag("fst.settings.list")
        rule.onNodeWithTag("fst.nav.tab.songs").performClick()
        settle(1_000)
        assertTrue(rule.onAllNodesWithTag("fst.first-run.dialog").fetchSemanticsNodes().isEmpty())
        // Replay ignores gates: all nine Songs slides, even the player-gated ones.
        rule.onNodeWithTag("fst.nav.tab.settings").performClick()
        waitForTag("fst.settings.list")
        tap("fst.settings.first-run.songs")
        waitForTag("fst.first-run.dialog")
        assertEquals("Slide 1 of 9", rule.onNodeWithTag("fst.first-run.position").fetchSemanticsNode().config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.StateDescription))
        repeat(8) {
            rule.onNodeWithTag("fst.first-run.next").performClick()
            settle()
        }
        rule.onNodeWithTag("fst.first-run.done").performClick()
        waitGone("fst.first-run.dialog")
    }

    @Test
    fun everyCatalogSlideHasALiveDemo() {
        val all = com.festivalscoretracker.android.core.firstrun.FirstRunPageKey.entries.flatMap { FirstRunCatalog.slides(it) }.map { it.id }.toSet()
        assertEquals(all, FIRST_RUN_DEMO_IDS)
    }

    @Test
    fun notificationsBellBadgeSheetAndDeepLink() {
        launch(DebugLaunch(stillBackground = true, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")))
        waitForTag("fst.songs.row.s-alpha")
        rule.waitUntil(10_000) { settle(100); runCatching { rule.onNodeWithTag("fst.shell.notifications").assertExists() }.isSuccess }
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag("fst.shell.notifications").fetchSemanticsNodes().any { node ->
                node.config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription)?.firstOrNull() == "Notifications, 2 unread"
            }
        }
        rule.onNodeWithTag("fst.shell.notifications").performClick()
        waitForTag("fst.notifications.row.n-song")
        // Web section heading (upper case on screen, spoken as written).
        rule.onNodeWithText("NEW", useUnmergedTree = true).assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("New")))
        rule.onNodeWithText("Alpha Tune · Lead", useUnmergedTree = true).assertExists()
        // No catalogue art for this song in the fixture: the media rail falls back to the instrument icon.
        rule.onNodeWithTag("fst.notifications.row.n-song").assert(SemanticsMatcher.expectValue(NotificationMediaKind, "soloInstrument"))
        rule.onNodeWithTag("fst.notifications.row.n-song").assert(
            SemanticsMatcher("open hint") { node -> node.config.getOrNull(SemanticsActions.OnClick)?.label == "Open notification" },
        )
        rule.onNodeWithTag("fst.notifications.row.n-total").performSemanticsAction(SemanticsActions.OnClick) // no destination: stays open
        settle()
        rule.onNodeWithTag("fst.notifications.row.n-song").performSemanticsAction(SemanticsActions.OnClick)
        waitGone("fst.notifications.sheet")
        // A single-instrument notification opens Song Detail focused on that chart (web ?instrument=).
        waitForTag("fst.song-detail.preview.Solo_Guitar")
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag("fst.shell.notifications").fetchSemanticsNodes().any { node ->
                node.config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription)?.firstOrNull() == "Notifications"
            }
        }
        assertTrue(transport.requests.none { request -> request.headers.keys.any { it.lowercase().startsWith("x-fst-selected-") } })
    }

    @Test
    fun notificationsWithoutAPlayerPromptForAProfile() {
        launch(DebugLaunch(stillBackground = true, anonymous = true, opensNotifications = true))
        waitForTag("fst.notifications.no-player")
        rule.onNodeWithText("Select Player Profile").performSemanticsAction(SemanticsActions.OnClick)
        waitGone("fst.notifications.sheet")
        // No profile: the bell is not shown (web parity).
        assertTrue(rule.onAllNodesWithTag("fst.shell.notifications").fetchSemanticsNodes().isEmpty())
        assertTrue(runBlocking { transport.sent("/api/player/${Fixtures.ACCOUNT_A}/notifications").isEmpty() })
    }
}

/** Expanded window: Settings shows the persistent Quick Links pane instead of the top-bar entry. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class ExpandedSettingsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun quickLinksMenuOnExpandedWindows() {
        val debug = DebugLaunch(section = FestivalSection.Settings, stillBackground = true)
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        fun settle() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        // Expanded windows: an anchored dropdown from the top-bar button, never a side pane.
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.quick-links.open").fetchSemanticsNodes().isNotEmpty() }
        assertTrue(rule.onAllNodesWithTag("fst.quick-links.pane").fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("fst.quick-links.open").performClick()
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.quick-links.menu").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.quick-links.item.licenses").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.settings.licenses").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.settings.licenses").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.licenses.list").fetchSemanticsNodes().isNotEmpty() }
        // Nothing open: the first package fills the detail pane (two populated columns).
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.licenses.text").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.licenses.detail-pane").assertExists()
        rule.onNodeWithTag("fst.licenses.list").performScrollToNode(hasTestTag("fst.licenses.row.com.squareup.okhttp3:okhttp"))
        rule.onNodeWithTag("fst.licenses.row.com.squareup.okhttp3:okhttp").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.licenses.text").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.licenses.detail-pane").assertExists()
        assertTrue(rule.onAllNodesWithTag("fst.licenses.detail").fetchSemanticsNodes().isEmpty())
    }
}
