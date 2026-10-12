package com.festivalscoretracker.android.ui.songdetail

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalDensity
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
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.ui.common.FestivalMarquee
import com.festivalscoretracker.android.ui.search.GlobalSearchTags
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

/**
 * `song-header` R2–R4 (issue #315) on every Android song page, in the whole shell against a
 * synthetic song with an overflowing title: the in-page title takes the full width beside the
 * art (or icon) on one scrolling line, Reduce Motion tail-truncates it, 200% text wraps it
 * in-page, and the pinned top-bar title stays one scrolling line that fills the bar. On the song
 * boards the pinned title sits over the board's line (issue #580): the instrument led by its
 * decorative icon, or the band size alone, read with the title as one TalkBack stop.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SongHeaderTitleUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val store = InMemoryPreferences()
    private val transport = BandFixtures.install(FakeTransport.standard()).apply {
        ProfileFixtures.register(this)
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) {
            Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null").replace("\"title\":\"Alpha Tune\"", "\"title\":\"$LONG\"")
        }
    }

    // region Harness

    private fun launch(route: String, fontScale: Float = 1f, reduceMotion: Boolean = false, profile: SelectedPlayer? = null) {
        if (reduceMotion) {
            runBlocking { store.updateData { it.toMutablePreferences().apply { this[booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION)] = true } } }
        }
        val debug = DebugLaunch(route = DebugLaunch.parseRoute(route), songQuery = route.removePrefix("song:").takeIf { route.startsWith("song:") }, profile = profile, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = store)
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) { FestivalApp(container, debug) }
        }
        settle()
    }

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
        rule.waitForIdle()
    }

    private fun titles(header: String) =
        rule.onAllNodes(hasText(LONG, substring = true) and hasAnyAncestor(hasTestTag(header)), useUnmergedTree = true).fetchSemanticsNodes()

    /** Waits for [header] to show the long title and lets the load fade finish. */
    private fun waitForTitle(header: String): SemanticsNode {
        rule.waitUntil(20_000) { settle(100); titles(header).isNotEmpty() }
        settle(2_000)
        return titles(header).single()
    }

    private fun bounds(tag: String): Rect = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().first().boundsInRoot

    private fun mode(node: SemanticsNode) = node.config.getOrNull(FestivalMarquee.ModeKey)

    private fun layout(node: SemanticsNode): TextLayoutResult {
        val layouts = mutableListOf<TextLayoutResult>()
        node.config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
        return layouts.single()
    }

    private fun px(dp: Float) = dp * rule.activity.resources.displayMetrics.density

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun subtitles() = rule.onAllNodesWithTag("fst.nav.subtitle", useUnmergedTree = true).fetchSemanticsNodes()

    /**
     * The pinned title's board line reads [board], sits under the title inside the bar, and the
     * bar's title block is one TalkBack stop that names the song and the board once each, with
     * no icon description.
     */
    private fun assertBoardLine(title: SemanticsNode, board: String) {
        val subtitle = subtitles().single()
        assertEquals(board, subtitle.config[SemanticsProperties.Text].joinToString { it.text })
        assertEquals("one line", 1, layout(subtitle).lineCount)
        assertFalse("not ellipsized", layout(subtitle).isLineEllipsized(0))
        val line = subtitle.boundsInRoot
        val bar = bounds("fst.nav.top-bar")
        assertTrue("board line ${line.top} under the title ${title.boundsInRoot.bottom}", line.top >= title.boundsInRoot.bottom - px(1f))
        assertTrue("title $title inside the bar $bar", title.boundsInRoot.top >= bar.top - px(1f))
        assertTrue("board line $line inside the bar $bar", line.bottom <= bar.bottom + px(1f))
        val block = rule.onNodeWithTag("fst.nav.title-block").fetchSemanticsNode().config
        val texts = block[SemanticsProperties.Text].map { it.text }
        assertEquals("song read once in $texts", 1, texts.count { it == LONG })
        assertEquals("board read once in $texts", 1, texts.count { it == board })
        assertTrue("song before board in $texts", texts.indexOf(LONG) < texts.indexOf(board))
        assertTrue("no icon description", block.getOrNull(SemanticsProperties.ContentDescription).isNullOrEmpty())
    }

    /** The instrument icon leads the board line, centred on it and no taller than its line. */
    private fun assertInstrumentIcon() {
        val icon = bounds("fst.nav.subtitle-icon")
        val line = subtitles().single().boundsInRoot
        assertTrue("icon $icon before the name $line", icon.right <= line.left + px(0.5f))
        assertEquals(line.center.y, icon.center.y, px(2f))
        assertTrue("icon $icon within the line $line", icon.height <= line.height + px(1f))
    }

    /**
     * The in-page title scrolls on one line and its box reaches the header's trailing edge.
     *
     * @param header Tag of the header row.
     */
    private fun assertScrollsAcrossTheColumn(header: String) {
        val title = waitForTitle(header)
        assertEquals("$header title mode", FestivalMarquee.Mode.Scrolling, mode(title))
        assertEquals("$header title lines", 1, layout(title).lineCount)
        val row = bounds(header)
        val box = title.boundsInRoot
        assertEquals("$header title ends at the header's edge ($box in $row)", row.right, box.right, px(1f))
        assertTrue("$header title takes most of the row ($box in $row)", box.width > row.width * 0.6f)
        assertTrue("the full text is wider than the box", layout(title).size.width > box.width)
    }

    /** Scrolls [list] until the header leaves and returns the pinned bar title. */
    private fun pinnedTitle(list: String): SemanticsNode {
        val items = rule.onNodeWithTag(list).fetchSemanticsNode().config.getOrNull(SemanticsProperties.CollectionInfo)?.rowCount ?: 2
        rule.onNodeWithTag(list).performScrollToIndex((items - 1).coerceIn(1, 2))
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodes(hasTestTag("fst.nav.title") and hasText(LONG), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        settle()
        return rule.onAllNodes(hasTestTag("fst.nav.title") and hasText(LONG), useUnmergedTree = true).fetchSemanticsNodes().single()
    }

    /** The pinned title is one scrolling line that runs up to the bar's first action. */
    private fun assertPinnedTitleScrollsAcrossTheBar(list: String) {
        val title = pinnedTitle(list)
        assertEquals("bar title mode", FestivalMarquee.Mode.Scrolling, mode(title))
        assertEquals("bar title lines", 1, layout(title).lineCount)
        val search = bounds(GlobalSearchTags.OPEN)
        val box = title.boundsInRoot
        assertTrue("bar title reaches the actions ($box, search $search)", search.left - box.right < px(16f))
        assertTrue("bar title is beside the back button and before the actions", box.left < search.left)
    }

    // endregion

    // region Normal text

    @Test
    fun songDetailTitleScrollsAcrossTheHeaderAndTheBar() {
        launch("song:s-alpha")
        assertScrollsAcrossTheColumn(DETAIL_HEADER)
        // TalkBack reads the full title once, in the header's one heading stop.
        val stops = rule.onAllNodes(hasText(LONG) and hasAnyAncestor(hasTestTag(DETAIL_HEADER))).fetchSemanticsNodes()
        assertEquals(1, stops.size)
        assertTrue(stops.single().config.contains(SemanticsProperties.Heading))
        assertEquals(1, stops.single().config[SemanticsProperties.Text].count { it.text == LONG })
        assertPinnedTitleScrollsAcrossTheBar("fst.song-detail.list")
        // Song Details pins the title alone (like Apple's caption-free SongBarTitle).
        assertTrue(subtitles().isEmpty())
        assertFalse(exists("fst.nav.title-block"))
    }

    @Test
    fun songLeaderboardTitleScrollsAcrossTheHeaderAndTheBar() {
        launch("songLeaderboard:s-alpha:Solo_Guitar")
        assertScrollsAcrossTheColumn(DETAIL_HEADER)
        assertPinnedTitleScrollsAcrossTheBar("fst.song-leaderboard.list")
    }

    @Test
    fun songBandLeaderboardTitleScrollsAcrossTheHeaderAndTheBar() {
        launch("songBandLeaderboard:s-alpha:Band_Duets")
        assertScrollsAcrossTheColumn(BAND_HEADER)
        // Issue #317: like the solo board, the bar takes the song title once the header scrolls away.
        assertPinnedTitleScrollsAcrossTheBar("fst.song-band-leaderboard.list")
    }

    @Test
    fun playerHistoryTitleScrollsAcrossTheSummaryRow() {
        launch("playerHistory:s-alpha:Solo_Guitar", profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        assertScrollsAcrossTheColumn(HISTORY_HEADER)
    }

    @Test
    fun shortTitlesStayStill() {
        launch("song:s-beta")
        val header = rule.onAllNodes(hasAnyAncestor(hasTestTag(DETAIL_HEADER)) and hasText("Beta", substring = true), useUnmergedTree = true)
        rule.waitUntil(20_000) { settle(100); header.fetchSemanticsNodes().isNotEmpty() }
        settle(2_000)
        val title = header.fetchSemanticsNodes().first()
        assertEquals(FestivalMarquee.Mode.Static, mode(title))
        assertEquals(1, layout(title).lineCount)
    }

    // endregion

    // region Board line (issue #580)

    @Test
    fun songLeaderboardBarShowsTheInstrumentUnderThePinnedTitle() {
        launch("songLeaderboard:s-alpha:Solo_Guitar")
        waitForTitle(DETAIL_HEADER)
        assertTrue("no board line while the header shows", subtitles().isEmpty())
        assertFalse(exists("fst.nav.subtitle-icon"))
        val title = pinnedTitle("fst.song-leaderboard.list")
        assertEquals("the title still scrolls", FestivalMarquee.Mode.Scrolling, mode(title))
        assertBoardLine(title, "Lead")
        assertInstrumentIcon()
        // The header back in view empties the bar again.
        rule.onNodeWithTag("fst.song-leaderboard.list").performScrollToIndex(0)
        rule.waitUntil(5_000) { settle(100); subtitles().isEmpty() }
        assertFalse(exists("fst.nav.subtitle-icon"))
    }

    @Test
    fun songBandLeaderboardBarShowsTheBandSizeWithoutAnIcon() {
        launch("songBandLeaderboard:s-alpha:Band_Duets")
        waitForTitle(BAND_HEADER)
        assertTrue("no board line while the header shows", subtitles().isEmpty())
        val title = pinnedTitle("fst.song-band-leaderboard.list")
        assertBoardLine(title, "Duos")
        assertFalse("a band size has no icon", exists("fst.nav.subtitle-icon"))
    }

    @Test
    fun largeTextGrowsTheBarOnceToFitTheTitleAndBoardLine() {
        launch("songLeaderboard:s-alpha:Solo_Guitar", fontScale = 2f)
        waitForTitle(DETAIL_HEADER)
        val empty = bounds("fst.nav.top-bar")
        val title = pinnedTitle("fst.song-leaderboard.list")
        assertEquals("the bar keeps its height when the title appears", empty.height, bounds("fst.nav.top-bar").height, px(1f))
        assertEquals("the bar title keeps scrolling", FestivalMarquee.Mode.Scrolling, mode(title))
        assertEquals(1, layout(title).lineCount)
        assertEquals("board line at 200% text", 2f, layout(subtitles().single()).layoutInput.density.fontScale, 0.01f)
        assertBoardLine(title, "Lead")
        assertInstrumentIcon()
        assertTrue("the icon grows with the text", bounds("fst.nav.subtitle-icon").height > px(24f))
    }

    // endregion

    // region Reduce Motion

    @Test
    fun reduceMotionTruncatesTheLeaderboardAndBarTitles() {
        launch("songLeaderboard:s-alpha:Solo_Guitar", reduceMotion = true)
        val title = waitForTitle(DETAIL_HEADER)
        assertEquals(FestivalMarquee.Mode.Truncated, mode(title))
        assertEquals(1, layout(title).lineCount)
        assertTrue("ends in an ellipsis", layout(title).isLineEllipsized(0))
        assertEquals("still spans the column", bounds(DETAIL_HEADER).right, title.boundsInRoot.right, px(1f))
        val bar = pinnedTitle("fst.song-leaderboard.list")
        assertEquals(FestivalMarquee.Mode.Truncated, mode(bar))
        assertEquals(1, layout(bar).lineCount)
    }

    @Test
    fun reduceMotionTruncatesTheBandTitle() {
        launch("songBandLeaderboard:s-alpha:Band_Duets", reduceMotion = true)
        val title = waitForTitle(BAND_HEADER)
        assertEquals(FestivalMarquee.Mode.Truncated, mode(title))
        assertEquals(1, layout(title).lineCount)
    }

    @Test
    fun reduceMotionTruncatesTheHistoryTitle() {
        launch("playerHistory:s-alpha:Solo_Guitar", reduceMotion = true, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        val title = waitForTitle(HISTORY_HEADER)
        assertEquals(FestivalMarquee.Mode.Truncated, mode(title))
        assertEquals(1, layout(title).lineCount)
    }

    // endregion

    // region Large text

    @Test
    fun largeTextWrapsTheInPageTitleButKeepsTheBarTitleOnOneLine() {
        launch("song:s-alpha", fontScale = 2f)
        val title = waitForTitle(DETAIL_HEADER)
        assertEquals(FestivalMarquee.Mode.Wrapped, mode(title))
        assertTrue("wraps in-page", layout(title).lineCount > 1)
        val bar = pinnedTitle("fst.song-detail.list")
        assertEquals("the bar title keeps scrolling", FestivalMarquee.Mode.Scrolling, mode(bar))
        assertEquals(1, layout(bar).lineCount)
    }

    @Test
    fun largeTextWrapsTheBandTitle() {
        launch("songBandLeaderboard:s-alpha:Band_Duets", fontScale = 2f)
        val title = waitForTitle(BAND_HEADER)
        assertEquals(FestivalMarquee.Mode.Wrapped, mode(title))
        assertTrue(layout(title).lineCount > 1)
    }

    @Test
    fun largeTextWrapsTheHistoryTitle() {
        launch("playerHistory:s-alpha:Solo_Guitar", fontScale = 2f, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        val title = waitForTitle(HISTORY_HEADER)
        assertEquals(FestivalMarquee.Mode.Wrapped, mode(title))
        assertTrue(layout(title).lineCount > 1)
    }

    // endregion

    private companion object {
        /** Synthetic overflowing title (no real song data). */
        const val LONG = "Through the Fire and Flames of a Synthetic Overflowing Title"
        const val DETAIL_HEADER = "fst.song-detail.header"
        const val BAND_HEADER = "fst.song-band-leaderboard.song"
        const val HISTORY_HEADER = "fst.history.subtitle"
    }
}
