package com.festivalscoretracker.android.whatsnew

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.firstrun.FirstRunMode
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.firstrun.FirstRunSeenStore
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MemoryBlobStore
import com.festivalscoretracker.android.core.whatsnew.WhatsNewMode
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCenter
import com.festivalscoretracker.android.presentation.whatsnew.WhatsNewController
import com.festivalscoretracker.android.ui.firstrun.FirstRunHost
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.whatsnew.WhatsNewHost
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.whatsnew.Changelog
import com.festivalscoretracker.android.core.whatsnew.ChangelogGroup
import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenRecord
import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenStore
import com.festivalscoretracker.android.core.whatsnew.InstallChannel
import com.festivalscoretracker.android.core.whatsnew.WhatsNewBlock
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import com.festivalscoretracker.android.ui.whatsnew.WhatsNewSheet
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** What's New launch gate, Dismiss and Settings replay through the whole shell (Robolectric). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class WhatsNewUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val store = InMemoryPreferences()
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
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

    private val seen: String? get() = store.current[stringPreferencesKey(SettingsRegistry.CHANGELOG_SEEN)]

    @Test
    fun forcedLaunchShowsSheetAndDismissRecordsSeen() {
        launch(DebugLaunch(stillBackground = true, whatsNew = "force"))
        waitForTag("fst.whats-new.sheet")
        rule.onNodeWithText("What's New · ", substring = true).assertIsDisplayed()
        rule.onNodeWithTag("fst.whats-new.section.0").assertIsDisplayed()
        rule.onNodeWithTag("fst.whats-new.dismiss").assertIsDisplayed()
        rule.onNodeWithTag("fst.whats-new.dismiss").performSemanticsAction(SemanticsActions.OnClick)
        waitGone("fst.whats-new.sheet")
        assertEquals(Changelog.currentHash, ChangelogSeenStore.decode(seen)!!.hash)
    }

    /** `presented` (compact): the full-height sheet keeps Dismiss at its bottom edge, not under short notes. */
    @Test
    fun compactSheetPinsDismissToTheBottomEdge() {
        launch(DebugLaunch(stillBackground = true, whatsNew = "force"))
        waitForTag("fst.whats-new.sheet")
        val sheet = rule.onNodeWithTag("fst.whats-new.sheet").fetchSemanticsNode().boundsInWindow
        val dismiss = rule.onNodeWithTag("fst.whats-new.dismiss").fetchSemanticsNode().boundsInWindow
        val gap = with(rule.density) { (sheet.bottom - dismiss.bottom).toDp() }
        // 12 dp bar padding below the button (no navigation bar under Robolectric).
        assertTrue("Dismiss is ${gap} above the sheet's bottom edge", gap.value in 0f..24f)
        val list = rule.onNodeWithTag("fst.whats-new.list").fetchSemanticsNode().boundsInWindow
        assertTrue("list fills the space above the bar", list.bottom <= dismiss.top && sheet.height * 0.5f < list.height)
    }

    /** `hidden-seen`: a stored record of the current hash presents nothing on a normal launch. */
    @Test
    fun seenHashPresentsNothingOnANormalLaunch() {
        kotlinx.coroutines.runBlocking {
            store.updateData { it.toMutablePreferences().apply { set(stringPreferencesKey(SettingsRegistry.CHANGELOG_SEEN), ChangelogSeenStore.encode(ChangelogSeenRecord("2610.01.01", Changelog.currentHash))) } }
        }
        launch(DebugLaunch(stillBackground = true, whatsNew = "on"))
        waitForTag("fst.nav.tab.songs")
        settle(2_000)
        assertTrue(rule.onAllNodesWithTag("fst.whats-new.sheet").fetchSemanticsNodes().isEmpty())
    }

    /** `presented` → `dismissed`: an unseen hash presents on a normal launch and Dismiss records it. */
    @Test
    fun unseenHashPresentsOnANormalLaunch() {
        launch(DebugLaunch(stillBackground = true, whatsNew = "on"))
        waitForTag("fst.whats-new.sheet")
        rule.onNodeWithTag("fst.whats-new.close").performSemanticsAction(SemanticsActions.OnClick)
        waitGone("fst.whats-new.sheet")
        assertEquals(Changelog.currentHash, ChangelogSeenStore.decode(seen)!!.hash)
    }

    /** `waiting-for-first-run`: the launch carousel holds the slot; What's New follows once it closes. */
    @Test
    fun firstRunCarouselShowsFirstThenWhatsNew() {
        launch(DebugLaunch(stillBackground = true, firstRun = "force", whatsNew = "force"))
        waitForTag("fst.first-run.dialog")
        settle(2_000)
        assertTrue(rule.onAllNodesWithTag("fst.whats-new.sheet").fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("fst.first-run.close").performClick()
        waitGone("fst.first-run.dialog")
        waitForTag("fst.whats-new.sheet")
        assertTrue(rule.onAllNodesWithTag("fst.first-run.dialog").fetchSemanticsNodes().isEmpty())
        assertNull(seen)
    }

    /**
     * `waiting-for-first-run` when the launch page resolves late (slow first frames on a live
     * catalogue): What's New must not win the slot on its settle timer before the carousel.
     */
    @Test
    fun lateLaunchPageStillShowsTheCarouselFirst() {
        val center = FirstRunCenter(FirstRunSeenStore(MemoryBlobStore()), FirstRunMode.Force)
        val controller = WhatsNewController(ChangelogSeenStore(MemoryBlobStore()), center, WhatsNewMode.Force, "0.2.0")
        var page by mutableStateOf<FirstRunPageKey?>(null)
        rule.setContent {
            FestivalTheme {
                val active by center.active.collectAsState()
                val settled by center.launchSettled.collectAsState()
                val shown by controller.shown.collectAsState()
                FirstRunHost(center, page, AppSettings(), compact = true, blocked = shown != null, destinationResolved = page != null)
                WhatsNewHost(controller, blocked = active != null || !settled, compact = true)
            }
        }
        repeat(30) { rule.mainClock.advanceTimeBy(100); settle(100) }
        assertTrue("no sheet before the launch page is evaluated", rule.onAllNodesWithTag("fst.whats-new.sheet").fetchSemanticsNodes().isEmpty())
        page = FirstRunPageKey.Songs
        waitForTag("fst.first-run.dialog")
        settle(2_000)
        assertTrue(rule.onAllNodesWithTag("fst.whats-new.sheet").fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("fst.first-run.close").performClick()
        waitGone("fst.first-run.dialog")
        waitForTag("fst.whats-new.sheet")
    }

    /** A destination without a carousel (e.g. Settings) settles the launch: What's New still presents. */
    @Test
    fun destinationWithoutCarouselStillPresents() {
        val center = FirstRunCenter(FirstRunSeenStore(MemoryBlobStore()), FirstRunMode.Force)
        val controller = WhatsNewController(ChangelogSeenStore(MemoryBlobStore()), center, WhatsNewMode.Force, "0.2.0")
        rule.setContent {
            FestivalTheme {
                val active by center.active.collectAsState()
                val settled by center.launchSettled.collectAsState()
                FirstRunHost(center, null, AppSettings(), compact = true, blocked = false, destinationResolved = true)
                WhatsNewHost(controller, blocked = active != null || !settled, compact = true)
            }
        }
        waitForTag("fst.whats-new.sheet")
    }

    @Test
    fun debugDefaultIsOffAndSettingsReplayShowsIt() {
        launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true))
        waitForTag("fst.settings.list")
        settle(1_000)
        assertTrue(rule.onAllNodesWithTag("fst.whats-new.sheet").fetchSemanticsNodes().isEmpty())
        assertNull(seen)
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag("fst.settings.whats-new"))
        rule.onNodeWithTag("fst.settings.whats-new").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.whats-new.sheet")
        rule.onNodeWithTag("fst.whats-new.close").performSemanticsAction(SemanticsActions.OnClick)
        waitGone("fst.whats-new.sheet")
        assertEquals(Changelog.currentHash, ChangelogSeenStore.decode(seen)!!.hash)
    }

    @Test
    fun groupedBlocksShowCategoryHeadingsInOrder() {
        val blocks = listOf(
            WhatsNewBlock("Changes Since Release 2610.01.03", listOf(ChangelogGroup("Songs", listOf("Rows load faster.")), ChangelogGroup(null, listOf("A loose note.")))),
            WhatsNewBlock("Version 2610.01.03", listOf(ChangelogGroup(null, listOf("The first release.")))),
        )
        var dismissed = 0
        rule.setContent { WhatsNewSheet("What's New · 2610.02.02", blocks, compact = false) { dismissed++ } }
        settle()
        rule.onNodeWithText("Changes Since Release 2610.01.03").assertIsDisplayed()
        rule.onNodeWithTag("fst.whats-new.group.0.0").assertIsDisplayed()
        rule.onNodeWithText("Songs").assertIsDisplayed()
        rule.onNodeWithText("Other").assertIsDisplayed()
        rule.onNodeWithText("Rows load faster.").assertIsDisplayed()
        // A block without categories has no headings.
        assertEquals(1, rule.onAllNodesWithText("Other").fetchSemanticsNodes().size)
        rule.onNodeWithText("The first release.").assertIsDisplayed()
        rule.onNodeWithTag("fst.whats-new.dismiss").performClick()
        assertEquals(1, dismissed)
    }

    /** The host shows the install channel's notes: tester installs the grouped tester block, store installs the release. */
    @Test
    fun hostShowsTheInstallChannelsNotes() {
        val entries = Changelog.decode(
            """{"entries":[{"version":"2610.02.02","items":["Songs: Rows load faster."],
              "groups":[{"category":"Songs","items":["Rows load faster."]}],
              "testflight":{"release":null,"vs_release":["Songs: Rows load faster.","General: Polish."],
                "groups":[{"category":"Songs","items":["Rows load faster."]},{"category":"General","items":["Polish."]}]}}]}""",
        )
        var channel by mutableStateOf(InstallChannel.Tester)
        rule.setContent {
            FestivalTheme {
                val center = remember { FirstRunCenter(FirstRunSeenStore(MemoryBlobStore()), FirstRunMode.Off) }
                val controller = remember(channel) {
                    WhatsNewController(ChangelogSeenStore(MemoryBlobStore()), center, WhatsNewMode.Off, "2610.02.02", channel)
                }
                LaunchedEffect(controller) { controller.replay() }
                WhatsNewHost(controller, blocked = false, compact = true, entries = entries)
            }
        }
        waitForTag("fst.whats-new.sheet")
        rule.onNodeWithText("Changes So Far").assertIsDisplayed()
        rule.onNodeWithText("General").assertIsDisplayed()
        rule.onNodeWithText("Polish.").assertIsDisplayed()
        assertTrue(rule.onAllNodesWithText("Version 2610.02.02").fetchSemanticsNodes().isEmpty())
        channel = InstallChannel.Store
        rule.waitUntil(10_000) { rule.onAllNodesWithText("Version 2610.02.02").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("Songs").assertIsDisplayed()
        assertTrue(rule.onAllNodesWithText("Polish.").fetchSemanticsNodes().isEmpty())
        assertTrue(rule.onAllNodesWithText("Changes So Far").fetchSemanticsNodes().isEmpty())
    }
}

/** Wider windows present What's New as a dialog. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class WhatsNewDialogUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun dialogShowsAndDismisses() {
        val debug = DebugLaunch(stillBackground = true, whatsNew = "force")
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        fun settle() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.whats-new.sheet").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.whats-new.list").assertIsDisplayed()
        rule.onNodeWithTag("fst.whats-new.dismiss").performClick()
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.whats-new.sheet").fetchSemanticsNodes().isEmpty() }
        assertNull(container.whatsNew.shown.value)
    }
}

/** Issue #183: a landscape phone (medium width, compact height) shows the 560 dp dialog, not the platform's 320 dp width. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
class WhatsNewLandscapePhoneUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun dialogUsesTheFullModalWidth() {
        val blocks = listOf(WhatsNewBlock("Changes So Far", listOf(ChangelogGroup("General", listOf("Polish.")))))
        rule.setContent { FestivalTheme { WhatsNewSheet("What's New · 2610.02.02", blocks, compact = false) {} } }
        repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        val width = with(rule.density) { rule.onNodeWithTag("fst.whats-new.sheet").fetchSemanticsNode().size.width.toDp() }
        assertEquals(560f, width.value, 1f)
        rule.onNodeWithText("Polish.").assertIsDisplayed()
    }
}
