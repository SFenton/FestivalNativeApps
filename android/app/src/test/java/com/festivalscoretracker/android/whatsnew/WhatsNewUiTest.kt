package com.festivalscoretracker.android.whatsnew

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
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
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.whatsnew.Changelog
import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenStore
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
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
