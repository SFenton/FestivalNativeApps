package com.festivalscoretracker.android.settings

import com.festivalscoretracker.android.core.settings.SettingsDetail
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
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
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Settings › CHOpt Path Default View (issues #20, #56, #164): an inline single-choice radio
 * group that saves without leaving Settings, announces its heading, roles and selection, and
 * initializes every later opening of the CHOpt Paths sheet. Synthetic fixtures only.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class PathDefaultViewUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        on("/api/paths/s-alpha/Solo_Guitar/expert/data", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.pathJson }
        onRaw("/api/paths/s-alpha/Solo_Guitar/expert") { HttpResult(200, SongsFixtures.png(), mapOf("X-FST-Publication-Id" to "7")) }
    }

    /** Karaoke hidden, so the Paths sheet opens without its one-time warning. */
    private val store = InMemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.VISIBLE_INSTRUMENTS) to "Solo_Guitar,Solo_Bass"))

    private val image = "fst.settings.path-default-view.image"
    private val text = "fst.settings.path-default-view.text"

    // region Helpers

    private fun launch(debug: DebugLaunch) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = store)
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
        rule.waitForIdle()
    }

    private fun count(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().size

    private fun waitForTag(tag: String) = rule.waitUntil(10_000) { settle(100); count(tag) > 0 }

    private fun waitGone(tag: String) = rule.waitUntil(10_000) { settle(100); count(tag) == 0 }

    private fun click(tag: String) {
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    private fun node(tag: String): SemanticsNode = rule.onNodeWithTag(tag).fetchSemanticsNode()

    private fun selected(tag: String) = node(tag).config.getOrNull(SemanticsProperties.Selected)

    private fun openSettingsAtPathDefault() {
        launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true))
        waitForTag("fst.settings.list")
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag(text))
        settle()
    }

    private fun saveDefault(mode: PathDisplayMode) = runBlocking {
        store.updateData { it.toMutablePreferences().apply { this[stringPreferencesKey(SettingsRegistry.PATH_DEFAULT_VIEW)] = mode.token } }
        Unit
    }

    private fun openPaths() {
        click("fst.song-detail.paths.open")
        waitForTag("fst.paths.display.open")
    }

    private fun closePaths() {
        click("fst.paths.close")
        waitGone("fst.paths.close")
    }

    /** Wait for the sheet to settle on [mode]'s content. */
    private fun waitForDisplay(mode: PathDisplayMode) = when (mode) {
        PathDisplayMode.Text -> waitForTag("fst.paths.row.1")
        PathDisplayMode.Image -> waitForTag("fst.paths.image")
    }

    private fun assertShows(mode: PathDisplayMode) {
        waitForDisplay(mode)
        assertEquals("text table shown", mode == PathDisplayMode.Text, count("fst.paths.table") > 0)
        assertEquals("image shown", mode == PathDisplayMode.Image, count("fst.paths.image") > 0)
    }

    // endregion

    @Test
    fun inlineRadioGroupAnnouncesHeadingRolesAndSelection() {
        openSettingsAtPathDefault()
        // TalkBack: a heading names the setting, then one radio-button stop per option.
        val heading = rule.onNode(hasText("CHOpt Path Default View")).fetchSemanticsNode()
        assertTrue(heading.config.contains(SemanticsProperties.Heading))
        listOf(image to "Image", text to "Text").forEach { (tag, label) ->
            val option = node(tag)
            assertEquals(Role.RadioButton, option.config.getOrNull(SemanticsProperties.Role))
            assertEquals(listOf(label), option.config.getOrNull(SemanticsProperties.Text)?.map { it.text })
            assertTrue("$tag is in a selectable group", option.parent?.config?.contains(SemanticsProperties.SelectableGroup) == true)
            val height = with(rule.density) { option.size.height.toDp().value }
            assertTrue("$tag touch target is $height dp", height >= 48f)
        }
        assertEquals(true, selected(image))
        assertEquals(false, selected(text))
        // No disclosure: both options are always shown, so there is no expanded/collapsed state.
        assertFalse(node(image).config.contains(SemanticsProperties.StateDescription))

        click(text)
        assertTrue("stays on Settings", count("fst.settings.list") == 1 && count("fst.paths.close") == 0)
        assertEquals(true, selected(text))
        assertEquals(false, selected(image))
        assertEquals(PathDisplayMode.Text, SettingsRepository.decode(store.current).pathDefaultView)

        click(text) // re-selecting is a no-op
        assertEquals(PathDisplayMode.Text, SettingsRepository.decode(store.current).pathDefaultView)
        click(image)
        assertEquals(true, selected(image))
        assertEquals(PathDisplayMode.Image, SettingsRepository.decode(store.current).pathDefaultView)
    }

    @Test
    fun savedTextSelectionIsRestoredOnLaunch() {
        saveDefault(PathDisplayMode.Text)
        openSettingsAtPathDefault()
        assertEquals(true, selected(text))
        assertEquals(false, selected(image))
    }

    @Test
    fun largeTextKeepsOptionsWholeAndTappable() {
        RuntimeEnvironment.setFontScale(2f)
        openSettingsAtPathDefault()
        listOf(image, text).forEach { tag ->
            val option = node(tag)
            val height = with(rule.density) { option.size.height.toDp().value }
            assertTrue("$tag touch target is $height dp at 200%", height >= 48f)
            val layouts = mutableListOf<TextLayoutResult>()
            rule.onNode(hasText(if (tag == image) "Image" else "Text") and hasAnyAncestor(hasTestTag(tag)), useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val layout = layouts.single()
            assertFalse("$tag label is ellipsized", (0 until layout.lineCount).any { layout.isLineEllipsized(it) })
            assertTrue("$tag label fits its row", layout.size.height <= option.size.height)
        }
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun expandedWindowOpensTheGroupInTheDetailPane() {
        launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true))
        waitForTag("fst.settings.list")
        // List/detail Settings (issue #371): a chevron row with the current value opens the radio group on the right.
        val row = SettingsDetail.PathDefaultView.rowTag
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag(row))
        assertEquals(0, count(text))
        click(row)
        waitForTag(text)
        val pane = node("fst.settings.detail-pane").boundsInRoot
        listOf(image, text).forEach { tag ->
            val bounds = node(tag).boundsInRoot
            assertTrue("$tag inside the detail pane", bounds.left >= pane.left && bounds.right <= pane.right)
        }
        click(text)
        assertEquals(PathDisplayMode.Text, SettingsRepository.decode(store.current).pathDefaultView)
        assertTrue("the row shows the new value", rule.onAllNodes(hasTestTag(row) and hasText("Text", substring = false)).fetchSemanticsNodes().isNotEmpty())
    }

    @Test
    fun everyPathsOpeningStartsAtTheSavedDefault() {
        launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true))
        waitForTag("fst.song-detail.paths.open")
        openPaths()
        assertShows(PathDisplayMode.Image)
        closePaths()

        // Settings changed while the song stays on the back stack: the next opening follows it.
        saveDefault(PathDisplayMode.Text)
        settle()
        openPaths()
        assertShows(PathDisplayMode.Text)

        // An in-sheet switch lasts for that opening only.
        click("fst.paths.display.open")
        waitForTag("fst.paths.display.image")
        click("fst.paths.display.image")
        assertShows(PathDisplayMode.Image)
        closePaths()
        openPaths()
        assertShows(PathDisplayMode.Text)
    }
}
