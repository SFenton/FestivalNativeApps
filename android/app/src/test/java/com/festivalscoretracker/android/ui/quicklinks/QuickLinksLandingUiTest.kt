package com.festivalscoretracker.android.ui.quicklinks

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import androidx.datastore.preferences.core.booleanPreferencesKey
import kotlinx.coroutines.runBlocking
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.CompeteFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
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
 * Issue #159 (validation of #51 / iOS #12): on the real pages that share the Quick Links controller, a
 * jump lands the section's top [QuickLinks.LANDING_OFFSET_DP] (32 dp) below the visible top of the page,
 * just under the top app bar, and the entry then names the landed section (the activation line matches
 * the landing line). Covers the compact sheet, the wider top-bar menu, phone landscape and 2.0 text, for
 * lazy lists (Settings, Leaderboards), row-major grids (player page, Compete) and a plain scrolling
 * column (Band). Issue #587: what lands on the line is the section's heading title, not the padded top of
 * its item, so headings that keep their own top padding (Song Detail's 12 dp instrument header and 16 dp
 * section headers, Compete's 8 dp group headers) leave no dead space under the top bar.
 */
@RunWith(AndroidJUnit4::class)
class QuickLinksLandingUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Helpers

    private fun launch(debug: DebugLaunch, transport: HttpTransport, experimentalRanks: Boolean = false) {
        val store = InMemoryPreferences()
        if (experimentalRanks) {
            runBlocking { store.updateData { it.toMutablePreferences().apply { this[booleanPreferencesKey(SettingsRegistry.EXPERIMENTAL_RANKS)] = true } } }
        }
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = store)
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun songs(transport: FakeTransport) = transport.apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
        rule.waitForIdle()
    }

    private fun nodes(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true)

    private fun node(tag: String): SemanticsNodeInteraction = nodes(tag)[0]

    private fun waitForTag(tag: String) = rule.waitUntil(10_000) { settle(100); nodes(tag).fetchSemanticsNodes().isNotEmpty() }

    private fun waitGone(tag: String) = rule.waitUntil(10_000) { settle(100); nodes(tag).fetchSemanticsNodes().isEmpty() }

    private fun tap(tag: String) {
        waitForTag(tag)
        node(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    /** The entry's spoken label, which names the current section. */
    private fun entryLabel(): String = node(OPEN).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()

    /** How far [tag]'s bounds start below the page's scrolling viewport (the top app bar's bottom edge), in dp. */
    private fun boundsTop(tag: String): Float = (node(tag).getUnclippedBoundsInRoot().top - node(CONTENT).getUnclippedBoundsInRoot().top).value

    /** How far [heading]'s content (inside its own padding) starts below the page's scrolling viewport, in dp. */
    private fun contentTop(heading: SemanticsNodeInteraction): Float {
        val y = heading.fetchSemanticsNode().layoutInfo.coordinates.positionInRoot().y
        return with(rule.density) { y.toDp() }.value - node(CONTENT).getUnclippedBoundsInRoot().top.value
    }

    /** A section whose heading is flush with the tagged section's top. */
    private fun flush(tag: String) = Heading(tag) { boundsTop(tag) }

    /** A heading tagged directly: its title, inside its own top padding. */
    private fun title(tag: String) = Heading(tag) { contentTop(node(tag)) }

    /** The first heading inside the tagged section: its title, inside its own top padding. */
    private fun titleIn(tag: String) = Heading(tag) {
        contentTop(rule.onAllNodes(isHeading() and hasAnyAncestor(hasTestTag(tag)), useUnmergedTree = true)[0])
    }

    /** The heading reading [text], composed once [tag] is: its title, inside its own top padding. */
    private fun titled(text: String, tag: String) = Heading(tag) {
        contentTop(rule.onAllNodes(isHeading() and hasText(text), useUnmergedTree = true)[0])
    }

    /** Opens Quick Links and chooses [id]. */
    private fun jump(id: String) {
        tap(OPEN)
        tap("$ITEM$id")
        waitGone("$ITEM$id")
        settle(1_000)
    }

    /**
     * Jumps to [id] and checks its heading's title (not the section's padded top, issue #587) lands
     * [LANDING_DP] below the top bar and the entry then names the section.
     */
    private fun assertLands(id: String, title: String, heading: Heading) {
        jump(id)
        waitForTag(heading.tag)
        assertEquals("$id's title lands $LANDING_DP dp below the top bar", LANDING_DP, heading.top(), 1f)
        assertTrue("entry names the landed section $title: ${entryLabel()}", entryLabel().endsWith("current section $title"))
    }

    private fun scrollBy(listTag: String, dp: Float) {
        val px = with(rule.density) { dp.dp.toPx() }
        node(listTag).performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, px) }
        settle(1_000)
    }

    /**
     * Without a jump, a section is current once its heading scrolls past the landing line (the activation
     * line is the landing line): current at 20 dp below the top bar, not yet at 44 dp.
     */
    private fun assertActivatesAtTheLandingLine(listTag: String, heading: Heading, title: String) {
        node(listTag).performScrollToNode(hasTestTag(heading.tag))
        settle(1_000)
        scrollBy(listTag, heading.top() - 20f)
        assertEquals(20f, heading.top(), 1f)
        assertTrue("$title is current 12 dp past the landing line: ${entryLabel()}", entryLabel().endsWith("current section $title"))
        scrollBy(listTag, -24f)
        assertEquals(44f, heading.top(), 1f)
        assertFalse("$title is not current 12 dp short of the landing line: ${entryLabel()}", entryLabel().endsWith("current section $title"))
    }

    private fun settings() {
        launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), songs(FakeTransport.standard()))
        waitForTag("fst.settings.list")
        assertLands("show-instruments", "Show Instruments", flush("fst.settings.section.show-instruments"))
        assertLands("accessibility", "Accessibility", flush("fst.settings.section.accessibility"))
        // Back up to a section above: the landing line again, not the list's top.
        assertLands("item-shop", "Item Shop", flush("fst.settings.section.item-shop"))
    }

    private fun profile() {
        val transport = songs(FakeTransport.standard()).apply { ProfileFixtures.register(this) }
        launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true), transport)
        waitForTag("fst.player.available")
        val overview = titleIn("fst.player.overview")
        // Overview is the page's first row since Select moved to the toolbar (#590), so its title rests
        // above the landing line at the top of the page.
        val restTop = overview.top()
        // Lazily built grid items: the jump lands after composing the target.
        assertLands("top-songs", "Top Songs", titleIn("fst.player.top-songs"))
        // The instrument heading row is flush with its section.
        assertLands("instrument:Solo_Bass", "Bass", flush("fst.player.instrument.Solo_Bass"))
        // The first section clamps at the content's top (section-jump-landing R2) and is still current.
        jump("global")
        assertEquals("global's title clamps at the top of the page", restTop, overview.top(), 1f)
        assertTrue("entry names Global Statistics: ${entryLabel()}", entryLabel().endsWith("current section Global Statistics"))
    }

    private fun leaderboards() {
        val transport = RankingsFixtures.install(songs(FakeTransport.standard()), unranked = setOf("Solo_Bass"))
        launch(DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true), transport)
        waitForTag("fst.leaderboards")
        assertLands("instrument:Solo_Drums", "Drums", flush("fst.leaderboards.card.Solo_Drums"))
        assertLands("band:Band_Trios", "Trios", flush("fst.leaderboards.band-card.Band_Trios"))
    }

    private fun compete() {
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true), CompeteFixtures.transport())
        waitForTag("fst.compete.section.leaderboards")
        // The heading keeps 8 dp above its title inside the landed item; the title, not that space, lands (#587).
        assertLands("rivals", "Rivals", title("fst.compete.section.rivals"))
    }

    private fun settingsActivation() {
        launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), songs(FakeTransport.standard()))
        waitForTag("fst.settings.list")
        assertActivatesAtTheLandingLine("fst.settings.list", flush("fst.settings.section.show-instruments"), "Show Instruments")
    }

    private fun profileActivation() {
        val transport = songs(FakeTransport.standard()).apply { ProfileFixtures.register(this) }
        launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true), transport)
        waitForTag("fst.player.available")
        assertActivatesAtTheLandingLine("fst.player.available", titleIn("fst.player.top-songs"), "Top Songs")
    }

    private fun band(experimentalRanks: Boolean = false) {
        val transport = BandFixtures.install(songs(FakeTransport.standard()))
        launch(DebugLaunch(route = DebugLaunch.parseRoute("band:${BandFixtures.DUO_ID}:Band_Duets:${BandFixtures.DUO_KEY}"), stillBackground = true), transport, experimentalRanks)
        waitForTag("fst.band.members-section")
        // Experimental Ranks off: no Rank By row (#541). On: the heading row's own 8 dp inset is skipped too (#587).
        if (experimentalRanks) waitForTag("fst.band.rank-by")
        assertLands("statistics", "Statistics", title("fst.band.statistics-section"))
        assertLands("summary", "Summary", title("fst.band.summary-section"))
    }

    private fun launchSongDetail() {
        val transport = BandFixtures.install(songs(FakeTransport.standard()).apply { ProfileFixtures.register(this) })
        launch(DebugLaunch(route = SongDetailRoute("s-alpha"), profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true), transport)
        waitForTag("fst.song-detail.intensity")
    }

    /**
     * Issue #587: Song Detail's instrument header (12 dp above its row) and section headers (16 dp above
     * their titles) land their titles on the line, not that space.
     */
    private fun songDetail() {
        launchSongDetail()
        assertLands("instrument-Solo_Bass", "Bass", title("fst.song-detail.heading.Solo_Bass"))
        assertLands("band-Band_Duets", "Duos", titleIn("fst.song-detail.band-preview.Band_Duets"))
        assertLands("score-history", "Score History", titleIn("fst.song-detail.history"))
        // Back up to the first section: the landing line again.
        assertLands("intensity", "Intensity", titled("Intensity", "fst.song-detail.intensity"))
    }

    private fun songDetailActivation() {
        launchSongDetail()
        assertActivatesAtTheLandingLine("fst.song-detail.list", title("fst.song-detail.heading.Solo_Bass"), "Bass")
    }

    /** A section heading to measure: [tag] is composed once the jump lands, [top] its title's offset below the top bar in dp. */
    private class Heading(val tag: String, val top: () -> Float)

    // endregion

    // region Phone portrait (bottom sheet)

    @Test
    @Config(qualifiers = PHONE)
    fun settingsOnAPhone() = settings()

    @Test
    @Config(qualifiers = PHONE)
    fun playerOnAPhone() = profile()

    @Test
    @Config(qualifiers = PHONE)
    fun leaderboardsOnAPhone() = leaderboards()

    @Test
    @Config(qualifiers = PHONE)
    fun competeOnAPhone() = compete()

    @Test
    @Config(qualifiers = PHONE)
    fun bandOnAPhone() = band()

    @Test
    @Config(qualifiers = PHONE)
    fun bandWithRankByOnAPhone() = band(experimentalRanks = true)

    @Test
    @Config(qualifiers = PHONE, fontScale = 2f)
    fun bandWithRankByAtLargeText() = band(experimentalRanks = true)

    @Test
    @Config(qualifiers = PHONE)
    fun settingsActivationLineOnAPhone() = settingsActivation()

    @Test
    @Config(qualifiers = PHONE)
    fun playerActivationLineOnAPhone() = profileActivation()

    @Test
    @Config(qualifiers = PHONE)
    fun songDetailOnAPhone() = songDetail()

    @Test
    @Config(qualifiers = PHONE)
    fun songDetailActivationLineOnAPhone() = songDetailActivation()

    // endregion

    // region Large text, landscape and wide windows (top-bar menu)

    @Test
    @Config(qualifiers = PHONE, fontScale = 2f)
    fun settingsAtLargeText() = settings()

    @Test
    @Config(qualifiers = PHONE, fontScale = 2f)
    fun playerAtLargeText() = profile()

    @Test
    @Config(qualifiers = LANDSCAPE)
    fun settingsInPhoneLandscape() = settings()

    @Test
    @Config(qualifiers = LANDSCAPE)
    fun leaderboardsInPhoneLandscape() = leaderboards()

    @Test
    @Config(qualifiers = WIDE)
    fun settingsInAWideWindow() = settings()

    @Test
    @Config(qualifiers = WIDE)
    fun playerInAWideWindow() = profile()

    @Test
    @Config(qualifiers = WIDE)
    fun competeInAWideWindow() = compete()

    @Test
    @Config(qualifiers = WIDE)
    fun playerActivationLineInAWideWindow() = profileActivation()

    @Test
    @Config(qualifiers = WIDE)
    fun songDetailInAWideWindow() = songDetail()

    @Test
    @Config(qualifiers = PHONE, fontScale = 2f)
    fun songDetailAtLargeText() = songDetail()

    @Test
    @Config(qualifiers = LANDSCAPE)
    fun songDetailInPhoneLandscape() = songDetail()

    // endregion

    private companion object {
        const val OPEN = "fst.quick-links.open"
        const val ITEM = "fst.quick-links.item."
        const val CONTENT = "fst.nav.content"
        const val PHONE = "w411dp-h891dp-xxhdpi"
        const val LANDSCAPE = "w891dp-h411dp-xxhdpi"
        const val WIDE = "w1280dp-h800dp-mdpi"

        /** The web's default section offset (#51, iOS #12), pinned so a change to [QuickLinks.LANDING_OFFSET_DP] fails. */
        const val LANDING_DP = 32f
    }
}