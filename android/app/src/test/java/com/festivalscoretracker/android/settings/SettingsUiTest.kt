package com.festivalscoretracker.android.settings

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
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

    private val settingsTab = DebugLaunch(section = FestivalSection.Settings, stillBackground = true)

    @Test
    fun everySettingPersistsAndPropagates() {
        launch(settingsTab)
        waitForTag("fst.settings.list")
        tap("fst.settings.show-instrument-icons")
        tap("fst.settings.enable-visual-order")
        tap("fst.settings.song-row-order.0.down")
        tap("fst.settings.path-default-view.text")
        tap("fst.settings.path-column-order.4.up")
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
    fun quickLinksSheetJumpsAndServiceCheckReportsPublication() {
        launch(settingsTab)
        waitForTag("fst.quick-links.open")
        rule.onNodeWithTag("fst.quick-links.open").performClick()
        waitForTag("fst.quick-links.sheet")
        rule.onNodeWithTag("fst.quick-links.item.service-info").performSemanticsAction(SemanticsActions.OnClick)
        waitGone("fst.quick-links.sheet")
        waitForTag("fst.settings.check-publication")
        rule.onNodeWithTag("fst.settings.check-publication").performClick()
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag("fst.settings.publication-status").fetchSemanticsNodes().isNotEmpty() }
        rule.waitUntil(10_000) { settle(100); runCatching { rule.onNodeWithText("Up to date: publication 7 (scrape 11), 3 songs.").assertExists() }.isSuccess }
        rule.onNodeWithTag("fst.quick-links.open").performClick()
        waitForTag("fst.quick-links.item.reset")
        rule.onNodeWithTag("fst.quick-links.item.reset").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.settings.reset")
        rule.onNodeWithTag("fst.settings.reset").assertIsDisplayed()
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
        rule.onNodeWithTag("fst.licenses.list").performScrollToNode(hasTestTag("fst.licenses.asset.instrument-icons"))
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
        rule.onNodeWithTag("fst.first-run.skip").performClick()
        waitGone("fst.first-run.dialog")
        // Dismissed slides never show again on the next visit.
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
        rule.onNodeWithText("New", useUnmergedTree = true).assertExists()
        rule.onNodeWithText("Alpha Tune · Lead", useUnmergedTree = true).assertExists()
        rule.onNodeWithTag("fst.notifications.row.n-total").performSemanticsAction(SemanticsActions.OnClick) // no destination: stays open
        settle()
        rule.onNodeWithTag("fst.notifications.row.n-song").performSemanticsAction(SemanticsActions.OnClick)
        waitGone("fst.notifications.sheet")
        waitForTag("fst.song-detail.intensity")
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
        // Nothing open: full-width list, no empty detail pane.
        assertTrue(rule.onAllNodesWithTag("fst.licenses.detail-pane").fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("fst.licenses.list").performScrollToNode(hasTestTag("fst.licenses.row.com.squareup.okhttp3:okhttp"))
        rule.onNodeWithTag("fst.licenses.row.com.squareup.okhttp3:okhttp").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.licenses.text").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.licenses.detail-pane").assertExists()
        assertTrue(rule.onAllNodesWithTag("fst.licenses.detail").fetchSemanticsNodes().isEmpty())
    }
}
