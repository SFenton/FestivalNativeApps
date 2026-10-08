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
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.onChildren
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasTestTag
import com.festivalscoretracker.android.core.settings.SettingsDetailText
import com.festivalscoretracker.android.core.settings.SettingsDetail
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.hasAnyDescendant
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
import org.robolectric.annotation.GraphicsMode

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
        // Percent and units are spoken on the phase, not printed (web parity).
        val phase = rule.onNodeWithTag("fst.settings.service-info.phase").fetchSemanticsNode()
        assertTrue(phase.config[SemanticsProperties.StateDescription].startsWith("42.5%"))
        rule.onNodeWithText("42.5%", useUnmergedTree = true).assertDoesNotExist()
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
    fun privacyPolicyRowOpensTheSharedPolicyInASheet() {
        launch(settingsTab)
        waitForTag("fst.settings.list")
        tap("fst.settings.privacy-policy")
        waitForTag("fst.privacy-policy.content")
        rule.onNodeWithTag("fst.privacy-policy.sheet").assertExists()
        rule.onNodeWithTag("fst.privacy-policy.title").assertTextEquals("Privacy Policy")
        rule.onNodeWithTag("fst.privacy-policy.effective-date").assertTextEquals("Effective October 3, 2026")
        // Section titles are headings, in contract order.
        rule.onNodeWithTag("fst.privacy-policy.content").performScrollToNode(hasTestTag("fst.privacy-policy.section.contact"))
        rule.onNodeWithText("Contact Us").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        rule.onNodeWithTag("fst.privacy-policy.close").performSemanticsAction(SemanticsActions.OnClick)
        waitGone("fst.privacy-policy.sheet")
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

/** Expanded window: Settings is a list/detail page (issue #371) and Quick Links stays a top-bar menu. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class ExpandedSettingsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private fun settle() = rule.settleSettings()

    private fun waitForTag(tag: String) = rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    private fun waitGone(tag: String) = rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty() }

    private fun tapInList(tag: String) {
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag(tag))
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun quickLinksMenuOnExpandedWindows() {
        rule.openSettings()
        // Expanded windows: an anchored dropdown from the top-bar button, never a side pane.
        waitForTag("fst.quick-links.open")
        assertTrue(rule.onAllNodesWithTag("fst.quick-links.pane").fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("fst.quick-links.open").performClick()
        waitForTag("fst.quick-links.menu")
        rule.onNodeWithTag("fst.quick-links.item.licenses").performSemanticsAction(SemanticsActions.OnClick)
        // The jump lands on the Licenses chevron row in the list; the pane is unchanged.
        waitForTag("fst.settings.licenses")
        rule.onNodeWithTag("fst.settings.detail-placeholder").assertExists()
    }

    @Test
    fun nothingSelectedShowsTheCentredSettingsPlaceholder() {
        rule.openSettings()
        waitForTag("fst.settings.detail-placeholder")
        val list = rule.onNodeWithTag("fst.settings.list").getUnclippedBoundsInRoot()
        val pane = rule.onNodeWithTag("fst.settings.detail-pane").getUnclippedBoundsInRoot()
        // List on the left at the shared list-pane width (40% clamped 320-440 dp), detail on the right.
        val listWidth = (list.right - list.left).value
        assertTrue("list width $listWidth", listWidth in 319.5f..440.5f)
        assertTrue(list.right <= pane.left)
        rule.onNodeWithTag("fst.settings.detail-placeholder").assert(hasAnyDescendant(hasText("Settings"))).assert(hasAnyDescendant(hasText(SettingsDetailText.PLACEHOLDER_SUBTITLE)))
        // Vertically centred in the pane.
        val title = rule.onAllNodesWithText("Settings", useUnmergedTree = true).fetchSemanticsNodes()
            .map { it.boundsInRoot }.first { it.left >= with(rule.density) { pane.left.toPx() } }
        val titleCentre = with(rule.density) { title.center.y.toDp() }
        val paneCentre = (pane.top + pane.bottom) / 2
        assertEquals(paneCentre.value, titleCentre.value, 60f)
    }

    @Test
    fun plainTogglesActInTheListAndLeaveThePaneAlone() {
        val store = InMemoryPreferences()
        rule.openSettings(store)
        waitForTag("fst.settings.detail-placeholder")
        tapInList("fst.settings.show-instrument-icons")
        assertFalse(SettingsRepository.decode(store.current).showInstrumentIcons)
        rule.onNodeWithTag("fst.settings.detail-placeholder").assertExists()
        // Multi-option sections are chevron rows, not inline cards.
        assertFalse(exists("fst.settings.instrument.${Instrument.entries.first().wireId}"))
        for (detail in SettingsDetail.entries.filter { it.section }) {
            rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag(detail.rowTag))
        }
        assertFalse(exists("fst.settings.service-info"))
    }

    @Test
    fun chevronRowOpensItsOptionsOnTheRight() {
        val store = InMemoryPreferences()
        rule.openSettings(store)
        waitForTag("fst.settings.detail-placeholder")
        tapInList(SettingsDetail.ShowInstruments.rowTag)
        waitForTag("fst.settings.detail.show-instruments")
        waitGone("fst.settings.detail-placeholder")
        rule.onNodeWithTag(SettingsDetail.ShowInstruments.rowTag).assert(SemanticsMatcher.expectValue(SemanticsProperties.Selected, true))
        val instrument = Instrument.entries.first()
        rule.onNodeWithTag("fst.settings.instrument.${instrument.wireId}").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        assertFalse(instrument in SettingsRepository.decode(store.current).visibleInstruments)
        // Another row replaces the pane's content.
        tapInList(SettingsDetail.Version.rowTag)
        waitForTag("fst.settings.app-version")
        assertFalse(exists("fst.settings.detail.show-instruments"))
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag(SettingsDetail.ShowInstruments.rowTag))
        rule.onNodeWithTag(SettingsDetail.ShowInstruments.rowTag).assert(SemanticsMatcher.expectValue(SemanticsProperties.Selected, false))
    }

    @Test
    fun appSettingsOptionsOpenOnTheRightAndCloseWithTheirSwitch() {
        val store = InMemoryPreferences()
        rule.openSettings(store)
        waitForTag("fst.settings.detail-placeholder")
        tapInList(SettingsDetail.PathDefaultView.rowTag)
        waitForTag("fst.settings.path-default-view.${PathDisplayMode.Text.token}")
        rule.onNodeWithTag("fst.settings.path-default-view.${PathDisplayMode.Text.token}").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        assertEquals(PathDisplayMode.Text, SettingsRepository.decode(store.current).pathDefaultView)
        // Maximum Score Leeway exists only while Filter Invalid Scores is on, as on phones.
        assertFalse(exists(SettingsDetail.Leeway.rowTag))
        tapInList("fst.settings.filter-invalid-scores")
        tapInList(SettingsDetail.Leeway.rowTag)
        waitForTag("fst.settings.leeway")
        tapInList("fst.settings.filter-invalid-scores")
        waitForTag("fst.settings.detail-placeholder")
        assertFalse(exists("fst.settings.leeway"))
    }

    @Test
    fun licensesOpenInThePaneAndAPackageInASheet() {
        rule.openSettings()
        waitForTag("fst.settings.detail-placeholder")
        tapInList("fst.settings.licenses")
        waitForTag("fst.licenses.list")
        assertFalse(exists("fst.licenses.detail-pane"))
        val pane = rule.onNodeWithTag("fst.settings.detail-pane").getUnclippedBoundsInRoot()
        assertTrue(rule.onNodeWithTag("fst.licenses.list").getUnclippedBoundsInRoot().left >= pane.left)
        rule.onNodeWithTag("fst.licenses.list").performScrollToNode(hasTestTag("fst.licenses.row.com.squareup.okhttp3:okhttp"))
        rule.onNodeWithTag("fst.licenses.row.com.squareup.okhttp3:okhttp").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.licenses.detail")
        waitForTag("fst.licenses.text")
    }

    @Test
    fun privacyPolicyOpensInThePane() {
        rule.openSettings()
        waitForTag("fst.settings.detail-placeholder")
        tapInList("fst.settings.privacy-policy")
        waitForTag("fst.privacy-policy.content")
        rule.onNodeWithTag("fst.privacy-policy.pane").assertExists()
        assertFalse(exists("fst.privacy-policy.sheet"))
        val pane = rule.onNodeWithTag("fst.settings.detail-pane").getUnclippedBoundsInRoot()
        assertTrue(rule.onNodeWithTag("fst.privacy-policy.content").getUnclippedBoundsInRoot().left >= pane.left)
    }
}

/** Phone: Settings stays one list with every section inline (issue #371 leaves phones unchanged). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class PhoneSettingsLayoutUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun sectionsStayInlineWithoutADetailPane() {
        rule.openSettings()
        assertTrue(rule.onAllNodesWithTag("fst.settings.detail-pane").fetchSemanticsNodes().isEmpty())
        val instrument = Instrument.entries.first()
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag("fst.settings.instrument.${instrument.wireId}"))
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag("fst.settings.path-default-view.${PathDisplayMode.Image.token}"))
        assertTrue(rule.onAllNodesWithTag(SettingsDetail.ShowInstruments.rowTag).fetchSemanticsNodes().isEmpty())
        assertTrue(rule.onAllNodesWithTag(SettingsDetail.PathDefaultView.rowTag).fetchSemanticsNodes().isEmpty())
    }
}

/** 200% text on a phone: the bell's unread badge stays a badge (issue #101). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2f)
class LargeTextNotificationsBadgeUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun badgeTextStopsGrowingAtLargeTextScale() {
        val debug = DebugLaunch(stillBackground = true, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            on("/api/player/${Fixtures.ACCOUNT_A}/notifications", headers = mapOf("X-FST-Publication-Id" to "7")) {
                """{"sourceRunId":3,"items":[
                  {"eventId":2,"notificationGuid":"n-total","eventKind":"player_total_score_improved","newNumeric":5,"detectedAt":"2026-09-27T11:00:00Z"}]}"""
            }
        }
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        fun settle() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        rule.waitUntil(10_000) {
            settle()
            rule.onAllNodesWithTag("fst.shell.notifications").fetchSemanticsNodes().any { node ->
                node.config.getOrNull(SemanticsProperties.ContentDescription)?.firstOrNull() == "Notifications, 1 unread"
            }
        }
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.shell.notifications.badge", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        val badge = rule.onNodeWithTag("fst.shell.notifications.badge", useUnmergedTree = true).getUnclippedBoundsInRoot()
        val bell = rule.onNodeWithTag("fst.shell.notifications").getUnclippedBoundsInRoot()
        // 11 sp label text capped at 130%: a 21 dp line instead of 28 dp+ at 200%, inside the 48 dp bell.
        val badgeHeight = badge.bottom - badge.top
        assertTrue("badge height $badgeHeight", badgeHeight.value <= 22f)
        assertTrue("badge ends ${badge.right} past bell ${bell.right}", badge.right <= bell.right)
        rule.onNodeWithTag("fst.shell.notifications").assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Notifications, 1 unread")))
    }
}

/** 200% text on a landscape tablet: the permanent drawer keeps its labels whole (issue #101). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi", fontScale = 2f)
class LargeTextPermanentDrawerUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun drawerWidensAndStacksDeselectBelowTheName() {
        val debug = DebugLaunch(stillBackground = true, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "SFentonX"))
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        fun settle() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.nav.drawer.deselect").fetchSemanticsNodes().isNotEmpty() }
        val drawer = rule.onNodeWithTag("fst.nav.permanent-drawer").getUnclippedBoundsInRoot()
        assertEquals(360f, (drawer.right - drawer.left).value, 0.5f)
        // One 56 dp row: "Leaderboards" no longer breaks before its last letter.
        val leaderboards = rule.onNodeWithTag("fst.nav.tab.leaderboards").getUnclippedBoundsInRoot()
        assertTrue("leaderboards row ${leaderboards.bottom - leaderboards.top}", (leaderboards.bottom - leaderboards.top).value < 70f)
        val name = rule.onNodeWithTag("fst.nav.drawer.player").getUnclippedBoundsInRoot()
        val deselect = rule.onNodeWithTag("fst.nav.drawer.deselect").getUnclippedBoundsInRoot()
        assertTrue("name row ${name.bottom - name.top}", (name.bottom - name.top).value < 70f)
        assertTrue("deselect ${deselect.top} above name bottom ${name.bottom}", deselect.top >= name.bottom)
        assertTrue("deselect ${deselect.bottom - deselect.top} below 48 dp", (deselect.bottom - deselect.top).value >= 48f)
    }
}

/** 200% text on a medium window: the rail's Profile item goes icon-only like its destinations (issue #101). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w884dp-h1104dp-xhdpi", fontScale = 2f)
class LargeTextRailProfileUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun profileItemDropsItsLabelAndKeepsItsName() {
        val debug = DebugLaunch(stillBackground = true, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "SFentonX"))
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = FakeTransport.standard(), settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        fun settle() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.nav.rail.profile").fetchSemanticsNodes().isNotEmpty() }
        assertTrue(rule.onAllNodesWithText("Profile", useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("fst.nav.rail.profile").assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Profile: SFentonX")))
    }
}

/** Medium window list pane: the pinned Songs search field stays one line tall (issue #101). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w884dp-h1104dp-xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SongsSearchPlaceholderUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun placeholderStaysOnOneLineInTheListPane() {
        val debug = DebugLaunch(stillBackground = true)
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        fun settle() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.songs.search").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.songs.detail-pane").assertExists()
        val field = rule.onNodeWithTag("fst.songs.search").getUnclippedBoundsInRoot()
        assertTrue("search field ${field.right - field.left} wide, ${field.bottom - field.top} tall", (field.bottom - field.top).value <= 64f)
    }
}

/** Version rows keep their labels whole: the long service origin wraps under its label at 200% text (issue #121). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2f)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LargeTextSettingsValueRowUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun serviceOriginStacksUnderItsLabelWhileShortValuesStayInline() {
        rule.openSettings()
        val (title, value) = rule.valueRowBounds("fst.settings.service-origin", "Service")
        assertTrue("value top ${value.top} above title bottom ${title.bottom}", value.top >= title.bottom)
        assertEquals(title.left.value, value.left.value, 0.5f)
        // The label keeps its natural one-line width instead of a one-letter column.
        assertTrue("title width ${title.right - title.left}", (title.right - title.left).value > 80f)
        val (buildTitle, buildValue) = rule.valueRowBounds("fst.settings.build", "Build")
        assertTrue("build value ${buildValue.left} before title end ${buildTitle.right}", buildValue.left > buildTitle.right)
        assertTrue(buildValue.top < buildTitle.bottom)
    }
}

/** At 100% text on a phone the Version rows stay title … value on one line (issue #121). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SettingsValueRowUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun valuesSitAtTheEndOfTheirLabelLine() {
        rule.openSettings()
        for ((tag, label) in listOf("fst.settings.build" to "Build", "fst.settings.service-origin" to "Service")) {
            val (title, value) = rule.valueRowBounds(tag, label)
            assertTrue("$tag value ${value.left} before title end ${title.right}", value.left > title.right)
            assertTrue("$tag value not on the title line", value.top < title.bottom)
        }
        rule.onNodeWithTag("fst.settings.service-origin").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Text))
    }
}

private typealias SettingsRule = androidx.compose.ui.test.junit4.AndroidComposeTestRule<*, ComponentActivity>

private fun SettingsRule.settleSettings() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); waitForIdle() }

/** Opens Settings on synthetic fixtures, persisting to [store]. */
private fun SettingsRule.openSettings(store: InMemoryPreferences = InMemoryPreferences()) {
    val debug = DebugLaunch(section = FestivalSection.Settings, stillBackground = true)
    val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }
    val container = AppContainer(activity, OkHttpClient(), debug, transport = transport, settingsStore = store)
    setContent { FestivalApp(container, debug) }
    waitUntil(10_000) { settleSettings(); onAllNodesWithTag("fst.settings.list").fetchSemanticsNodes().isNotEmpty() }
}

/** Scrolls to the Version row [tag] and returns the unmerged bounds of its [label] and of its value text. */
private fun SettingsRule.valueRowBounds(tag: String, label: String): Pair<androidx.compose.ui.unit.DpRect, androidx.compose.ui.unit.DpRect> {
    onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag(tag))
    settleSettings()
    val texts = onNodeWithTag(tag, useUnmergedTree = true).onChildren()
    texts.assertCountEquals(2)
    texts[0].assertTextEquals(label)
    return texts[0].getUnclippedBoundsInRoot() to texts[1].getUnclippedBoundsInRoot()
}
/** Expanded window: the list pane's sections fill the pane inside its 16 dp margins (issue #371 replaces the centred 840 dp column). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class WideSettingsColumnUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun sectionsFillTheListPane() {
        rule.openSettings()
        val list = rule.onNodeWithTag("fst.settings.list").getUnclippedBoundsInRoot()
        val section = rule.onNodeWithTag("fst.settings.section.app-settings").getUnclippedBoundsInRoot()
        assertEquals(16f, (section.left - list.left).value, 0.5f)
        assertEquals(16f, (list.right - section.right).value, 0.5f)
    }
}
