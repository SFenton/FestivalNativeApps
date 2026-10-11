package com.festivalscoretracker.android.ui.songs

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.material3.adaptive.HingeInfo
import androidx.compose.material3.adaptive.Posture
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.BucketHeaderFixtures
import com.festivalscoretracker.android.testing.SectionIndexFixtures
import com.festivalscoretracker.android.ui.common.LocalShellPosture
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlin.math.abs
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Songs `wide-columns` (#581): two row-major columns in wide landscape and unfolded windows,
 * one in portrait, compact and at large text; at a book fold the columns meet at the hinge and
 * the full-line content stays in the leading pane; folding reflows in place and keeps the
 * reader's place; Quick Links still land.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w891dp-h411dp-xxhdpi")
@OptIn(androidx.compose.ui.test.ExperimentalTestApi::class)
class SongsWideColumnsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    /** Hinge as (left, right) in dp, or null for no fold. */
    private lateinit var hinge: MutableState<Pair<Float, Float>?>
    private var separating = false

    private fun launch(transport: HttpTransport = SectionIndexFixtures.transport(), prefs: InMemoryPreferences = InMemoryPreferences(), fold: Pair<Float, Float>? = null) {
        hinge = mutableStateOf(fold)
        val debug = DebugLaunch(stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = prefs)
        rule.setContent {
            val density = LocalDensity.current.density
            val posture = hinge.value?.let { (left, right) ->
                Posture(
                    isTabletop = false,
                    hingeList = listOf(HingeInfo(Rect(left * density, 0f, right * density, 4000f), isFlat = !separating, isVertical = true, isSeparating = separating, isOccluding = separating)),
                )
            }
            // Always provide (null = no fold) so changing the fold recomposes rather than recreating the app.
            CompositionLocalProvider(LocalShellPosture provides posture) { FestivalApp(container, debug) }
        }
        settle()
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String) = rule.waitUntil(20_000) { settle(100); rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    private fun bounds(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot

    private val density get() = rule.activity.resources.displayMetrics.density

    /** Song row tags in reading position (top, then start), below [belowPx]. */
    private fun visibleRows(belowPx: Float = 0f): List<Pair<String, Rect>> {
        val isRow = SemanticsMatcher("song row") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.songs.row.") == true }
        return rule.onAllNodes(isRow).fetchSemanticsNodes()
            .filter { it.layoutInfo.isPlaced && it.boundsInRoot.top >= belowPx - 1 && it.boundsInRoot.height > 0 }
            .map { it.config[SemanticsProperties.TestTag] to it.boundsInRoot }
            .sortedWith(compareBy({ it.second.top }, { it.second.left }))
    }

    /** First fully visible row under the pinned search field. */
    private fun firstRow(): String = visibleRows(bounds("fst.songs.list").top).first().first

    private fun assertTwoColumns() {
        val a = bounds("fst.songs.row.s-0-1")
        val b = bounds("fst.songs.row.s-0-2")
        val next = bounds("fst.songs.row.s-1-1")
        assertEquals("row-major: the second song sits beside the first", a.top, b.top, 1f)
        assertTrue("start column first ($a, $b)", a.right <= b.left)
        assertTrue("the next section starts the next line", next.top >= a.bottom)
        assertEquals("the next line starts in the leading column", a.left, next.left, 1f)
    }

    private fun assertOneColumn() {
        val a = bounds("fst.songs.row.s-0-1")
        val b = bounds("fst.songs.row.s-0-2")
        assertTrue("one column: the second song is below the first", b.top >= a.bottom)
        assertEquals(a.left, b.left, 1f)
    }

    @Test
    fun wideLandscapePhoneShowsTwoEqualRowMajorColumns() {
        launch()
        waitForTag("fst.songs.row.s-0-1")
        assertTwoColumns()
        val a = bounds("fst.songs.row.s-0-1")
        val b = bounds("fst.songs.row.s-0-2")
        assertEquals("flat: equal halves", a.width, b.width, 2f)
        assertEquals("12 dp between the columns", 12 * density, b.left - a.right, 2f)
        // No list/detail split any more: Songs fills the window.
        assertTrue(rule.onAllNodesWithTag("fst.songs.detail-pane").fetchSemanticsNodes().isEmpty())
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun portraitPhoneKeepsOneColumn() {
        launch()
        waitForTag("fst.songs.row.s-0-2")
        assertOneColumn()
    }

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun portraitTabletKeepsOneColumn() {
        launch()
        waitForTag("fst.songs.row.s-0-2")
        assertOneColumn()
    }

    @Test
    @Config(qualifiers = "w640dp-h360dp-xhdpi")
    fun compactLandscapeTooNarrowForTwoColumnsKeepsOne() {
        launch()
        waitForTag("fst.songs.row.s-0-2")
        assertOneColumn()
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-xxhdpi", fontScale = 2f)
    fun largeTextKeepsOneColumn() {
        launch()
        waitForTag("fst.songs.row.s-0-2")
        assertOneColumn()
    }

    @Test
    @Config(qualifiers = "w851dp-h882dp-xhdpi")
    fun flatUnfoldedSplitsAtTheContentMidpoint() {
        launch(fold = 425.5f to 425.5f)
        waitForTag("fst.songs.row.s-0-1")
        assertTwoColumns()
        assertEquals("flat: equal halves, not the fold", bounds("fst.songs.row.s-0-1").width, bounds("fst.songs.row.s-0-2").width, 2f)
    }

    @Test
    @Config(qualifiers = "w851dp-h882dp-xhdpi")
    fun bookPostureColumnsMeetAtTheFoldAndFullLineContentStaysInTheLeadingPane() {
        separating = true
        launch(fold = 420f to 432f)
        waitForTag("fst.songs.row.s-0-1")
        assertTwoColumns()
        val foldLeft = 420f * density
        val foldRight = 432f * density
        val start = bounds("fst.songs.row.s-0-1")
        val end = bounds("fst.songs.row.s-0-2")
        assertEquals("the leading column ends at the fold", foldLeft, start.right, 2f)
        assertEquals("the trailing column starts at the fold", foldRight, end.left, 2f)
        assertTrue("the search field stays off the fold", bounds("fst.songs.search").right <= foldLeft + 1)
    }

    @Test
    @Config(qualifiers = "w851dp-h882dp-xhdpi")
    fun foldingReflowsInPlaceAndKeepsTheReadersPlace() {
        launch()
        waitForTag("fst.songs.row.s-0-2")
        // Folded (taller than wide, no fold): one column. Scroll so M's second song leads.
        assertOneColumn()
        val m = SectionIndexFixtures.labels.indexOf("M")
        rule.onNodeWithTag("fst.songs.list").performScrollToIndex(m * 2 + 1)
        settle()
        assertEquals("fst.songs.row.s-$m-2", firstRow())
        // Unfold: two columns, and M's line (holding that song) stays first.
        hinge.value = 425.5f to 425.5f
        settle()
        assertEquals("fst.songs.row.s-$m-1", firstRow())
        assertEquals(bounds("fst.songs.row.s-$m-1").top, bounds("fst.songs.row.s-$m-2").top, 1f)
        // Fold again: one column, M's first song still leads.
        hinge.value = null
        settle()
        assertEquals("fst.songs.row.s-$m-1", firstRow())
        assertTrue(bounds("fst.songs.row.s-$m-2").top > bounds("fst.songs.row.s-$m-1").top)
    }

    @Test
    fun quickLinksLandOnTheirBucketInTwoColumns() {
        launch(BucketHeaderFixtures.transport(), InMemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Duration")))
        waitForTag("fst.songs.section.duration.1to2")
        val first = bounds("fst.songs.row.s-0")
        val second = bounds("fst.songs.row.s-1")
        assertEquals("bucket rows are two-up", first.top, second.top, 1f)
        waitForTag("fst.quick-links.open")
        rule.onNodeWithTag("fst.quick-links.open").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.quick-links.item.duration:4to5")
        rule.onNodeWithTag("fst.quick-links.item.duration:4to5").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(20_000) { settle(100); rule.onAllNodesWithTag("fst.quick-links.menu").fetchSemanticsNodes().isEmpty() && rule.onAllNodesWithTag("fst.quick-links.sheet").fetchSemanticsNodes().isEmpty() }
        settle(1_200)
        val header = bounds("fst.songs.section.duration.4to5")
        val lead = visibleRows(header.bottom).first()
        val id = lead.first.removePrefix("fst.songs.row.s-").toInt()
        assertTrue("the 4–5 minute bucket leads after the jump (first row ${lead.first})", id / BucketHeaderFixtures.SECTION_SIZE == 3)
        assertTrue("its first row is in the leading column", abs(lead.second.left - first.left) < 2f)
    }
}
