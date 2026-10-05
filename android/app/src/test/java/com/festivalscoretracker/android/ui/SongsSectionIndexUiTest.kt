package com.festivalscoretracker.android.ui

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performCustomAccessibilityActionWithLabel
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.songs.SongSectionIndex
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.SectionIndexFixtures
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Songs #–Z index rail (`fst.songs.section-index.*`) in each reachable state: hidden for
 * one section and in Year order (decade headers and Quick Links instead), Title and
 * Artist sections, and scrubbing with its value indicator. On a short (landscape phone)
 * window the rail draws only every few letters (issue #48): tapping a drawn letter lands
 * on that letter's section at the top, including far jumps, and the rail's announced
 * section follows at once.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w891dp-h411dp-xxhdpi")
@OptIn(androidx.compose.ui.test.ExperimentalTestApi::class)
class SongsSectionIndexUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val labels = SectionIndexFixtures.labels

    private fun prefs(vararg pairs: Preferences.Pair<*>) = InMemoryPreferences(mutablePreferencesOf(*pairs))

    /** Opens Songs on the synthetic catalogue and waits for the first row. */
    private fun launch(prefs: InMemoryPreferences = InMemoryPreferences()) {
        val debug = DebugLaunch(stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = SectionIndexFixtures.transport(), settingsStore = prefs)
        rule.setContent { com.festivalscoretracker.android.ui.shell.FestivalApp(container, debug) }
        settle()
        waitForTag("fst.songs.row.s-0-1")
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun waitGone(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()
        }
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun railState(): String? =
        rule.onNodeWithTag("fst.songs.section-index").fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription)

    private fun railActions(): List<String> =
        rule.onNodeWithTag("fst.songs.section-index").fetchSemanticsNode().config.getOrNull(SemanticsActions.CustomActions).orEmpty().map { it.label }

    /** Taps the centre of drawn label [k] of [drawn] equal slots. */
    private fun tapLabel(k: Int, drawn: Int) {
        rule.onNodeWithTag("fst.songs.section-index").performTouchInput {
            click(Offset(width / 2f, height * (k + 0.5f) / drawn))
        }
        settle()
    }

    /** Tag of the first song row below the list's top content edge (the rail sits 56 dp under it). */
    private fun firstVisibleRow(): String? {
        val contentTop = rule.onNodeWithTag("fst.songs.section-index").fetchSemanticsNode().boundsInRoot.top -
            56 * rule.activity.resources.displayMetrics.density
        val isRow = SemanticsMatcher("song row") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.songs.row.") == true }
        return rule.onAllNodes(isRow, useUnmergedTree = true).fetchSemanticsNodes()
            .filter { it.layoutInfo.isPlaced && it.boundsInRoot.bottom > contentTop + 1 }
            .minByOrNull { it.boundsInRoot.top }
            ?.config?.getOrNull(SemanticsProperties.TestTag)
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun titleState_isOneTalkBackElementNamingTheTopSection() {
        launch()
        waitForTag("fst.songs.section-index")

        // One element: the labels are cleared from the tree and the # section is spoken in words.
        val rail = rule.onNodeWithTag("fst.songs.section-index").fetchSemanticsNode()
        assertEquals(listOf("Section index"), rail.config.getOrNull(SemanticsProperties.ContentDescription))
        assertTrue("labels are not separate elements", rail.children.isEmpty())
        assertEquals("Numbers and symbols", railState())
        assertFalse("no indicator at rest", exists("fst.songs.section-index.indicator"))
        // At the first section only Next is offered; Next then Previous move one section each way.
        assertEquals(listOf("Next section"), railActions())
        rule.onNodeWithTag("fst.songs.section-index").performCustomAccessibilityActionWithLabel("Next section")
        settle()
        assertEquals("A", railState())
        assertEquals("fst.songs.row.s-1-1", firstVisibleRow())
        assertEquals(listOf("Next section", "Previous section"), railActions())
        rule.onNodeWithTag("fst.songs.section-index").performCustomAccessibilityActionWithLabel("Previous section")
        settle()
        assertEquals("Numbers and symbols", railState())
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun titleState_lastSectionOffersOnlyPrevious() {
        launch()
        waitForTag("fst.songs.section-index")
        // Every label fits on a portrait phone: the bottom slot is Z.
        tapLabel(labels.lastIndex, labels.size)
        assertEquals("Z", railState())
        assertEquals(listOf("Previous section"), railActions())
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun artistState_indexesArtistInitials() {
        launch(prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Artist"))
        waitForTag("fst.songs.section-index")
        assertEquals("A", railState())
        // Three artist sections in equal slots: the last is Z (Zulu Artist).
        tapLabel(2, 3)
        assertEquals("Z", railState())
        assertEquals(listOf("Previous section"), railActions())
        val top = firstVisibleRow()
        assertTrue("a Zulu Artist row is at the top: $top", top != null && (top.removePrefix("fst.songs.row.s-").substringBefore('-').toInt() % 3 == 2))
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun yearState_hidesTheRailForDecadeHeadersAndQuickLinks() {
        launch(prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Year"))
        settle()
        assertFalse("no rail in Year order", exists("fst.songs.section-index"))
        assertTrue("decade header", exists("fst.songs.section.year.1990"))
        assertTrue("Quick Links reach the decades", exists("fst.quick-links.open"))
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun hiddenState_whenTheListHasOneSection_andBackWhenItHasMore() {
        launch()
        waitForTag("fst.songs.section-index")
        rule.onNodeWithTag("fst.songs.search.open").performClick()
        waitForTag("fst.songs.search")
        rule.onNodeWithTag("fst.songs.search").performTextInput("Mtune")
        waitGone("fst.songs.section-index")
        waitForTag("fst.songs.row.s-13-1")
        rule.onNodeWithTag("fst.songs.search").performTextClearance()
        waitForTag("fst.songs.section-index")
        // The list keeps the row the reader was on, and the rail names its section.
        assertEquals("M", railState())
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun scrubbingState_showsTheValueIndicatorUntilRelease() {
        launch()
        waitForTag("fst.songs.section-index")
        val rail = rule.onNodeWithTag("fst.songs.section-index")
        rail.performTouchInput { down(Offset(width / 2f, height * 0.5f / labels.size)) }
        settle(100)
        assertTrue("indicator while pressed", exists("fst.songs.section-index.indicator"))
        assertEquals("Numbers and symbols", railState())
        // Dragging to the M slot jumps there and the indicator follows.
        rail.performTouchInput { moveTo(Offset(width / 2f, height * 13.5f / labels.size)) }
        settle(100)
        assertTrue(exists("fst.songs.section-index.indicator"))
        assertEquals("M", railState())
        assertEquals("fst.songs.row.s-13-1", firstVisibleRow())
        // The indicator is decorative: no text or role of its own for TalkBack.
        val indicator = rule.onNodeWithTag("fst.songs.section-index.indicator", useUnmergedTree = true).fetchSemanticsNode()
        assertTrue(indicator.config.getOrNull(SemanticsProperties.Text).isNullOrEmpty())
        assertTrue(indicator.config.getOrNull(SemanticsProperties.ContentDescription).isNullOrEmpty())
        rail.performTouchInput { up() }
        settle(100)
        assertFalse("indicator cleared on release", exists("fst.songs.section-index.indicator"))
        assertEquals("M", railState())
    }

    /**
     * Narrows the list to one section, then clears the search and returns the rail's left edge
     * on the first frame it exists again, with its resting left edge.
     */
    private fun railReturn(): Pair<Float, Float> {
        waitForTag("fst.songs.section-index")
        val rest = rule.onNodeWithTag("fst.songs.section-index").fetchSemanticsNode().positionInRoot.x
        rule.onNodeWithTag("fst.songs.search.open").performClick()
        waitForTag("fst.songs.search")
        rule.onNodeWithTag("fst.songs.search").performTextInput("Mtune")
        waitGone("fst.songs.section-index")
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("fst.songs.search").performTextClearance()
        var left: Float? = null
        repeat(40) {
            if (left == null) {
                shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(16))
                rule.mainClock.advanceTimeByFrame()
                left = rule.onAllNodesWithTag("fst.songs.section-index").fetchSemanticsNodes().firstOrNull { it.layoutInfo.isPlaced && it.size.width > 0 }?.positionInRoot?.x
            }
        }
        rule.mainClock.autoAdvance = true
        return rest to left!!
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun reduceMotion_showsTheRailWithoutSliding() {
        launch(prefs(booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to true))
        val (rest, first) = railReturn()
        assertEquals("rail at rest on its first frame", rest, first, 0.5f)
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun defaultMotion_slidesTheRailInFromTheEdge() {
        launch()
        val (rest, first) = railReturn()
        assertTrue("rail starts right of its resting place ($first vs $rest)", first > rest + 1f)
    }

    @Test
    fun farJumpsOnASampledRailLandOnTheTappedLetter() {
        launch()
        waitForTag("fst.songs.section-index")

        val rail = rule.onNodeWithTag("fst.songs.section-index").fetchSemanticsNode().boundsInRoot
        val density = rule.activity.resources.displayMetrics.density * rule.activity.resources.configuration.fontScale
        val stride = SongSectionIndex.stride(labels.size, (rail.height / (20 * density)).toInt().coerceAtLeast(2))
        assertTrue("rail must sample labels (stride $stride)", stride >= 3)
        val drawn = (labels.size + stride - 1) / stride

        // Far jump # → the drawn letter at or before P, then back to #, then the last drawn letter.
        val far = (labels.indexOf("P") / stride) * stride
        for (target in listOf(far, 0, (drawn - 2) * stride, stride)) {
            tapLabel(target / stride, drawn)
            assertEquals("tapped ${labels[target]}", SongSectionIndex.spokenLabel(labels[target]), railState())
            assertEquals("${labels[target]} at the top", "fst.songs.row.s-$target-1", firstVisibleRow())
        }
    }
}
