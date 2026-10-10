package com.festivalscoretracker.android.ui.quicklinks

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasTestTag
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
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
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
 * lazy lists (Settings, Leaderboards), staggered grids (player page, Compete) and a plain scrolling
 * column (Band). Pages whose heading carries its own top padding inside the section show the title that
 * much lower (Compete's 8 dp).
 */
@RunWith(AndroidJUnit4::class)
class QuickLinksLandingUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Helpers

    private fun launch(debug: DebugLaunch, transport: HttpTransport) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
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

    /**
     * Opens Quick Links, chooses [id] and returns how far [sectionTag]'s top landed below [pageTag]'s top
     * (the page's scrolling viewport, which starts at the top app bar's bottom edge), in dp.
     */
    private fun jump(id: String, pageTag: String, sectionTag: String): Float {
        tap(OPEN)
        tap("$ITEM$id")
        waitGone("$ITEM$id")
        settle(1_000)
        waitForTag(sectionTag)
        val page = node(pageTag).getUnclippedBoundsInRoot().top
        val section = node(sectionTag).getUnclippedBoundsInRoot().top
        return (section - page).value
    }

    private fun assertLands(id: String, title: String, sectionTag: String, extraDp: Float = 0f) {
        val offset = jump(id, CONTENT, sectionTag)
        assertEquals("$id lands $LANDING_DP dp below the top bar", LANDING_DP + extraDp, offset, 1f)
        assertTrue("entry names the landed section $title: ${entryLabel()}", entryLabel().endsWith("current section $title"))
    }

    private fun scrollBy(listTag: String, dp: Float) {
        val px = with(rule.density) { dp.dp.toPx() }
        node(listTag).performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, px) }
        settle(1_000)
    }

    private fun top(sectionTag: String): Float = (node(sectionTag).getUnclippedBoundsInRoot().top - node(CONTENT).getUnclippedBoundsInRoot().top).value

    /**
     * Without a jump, a section is current once its top scrolls past the landing line (the activation
     * line is the landing line): current at 20 dp below the top bar, not yet at 44 dp.
     */
    private fun assertActivatesAtTheLandingLine(listTag: String, sectionTag: String, title: String) {
        node(listTag).performScrollToNode(hasTestTag(sectionTag))
        settle(1_000)
        scrollBy(listTag, top(sectionTag) - 20f)
        assertEquals(20f, top(sectionTag), 1f)
        assertTrue("$title is current 12 dp past the landing line: ${entryLabel()}", entryLabel().endsWith("current section $title"))
        scrollBy(listTag, -24f)
        assertEquals(44f, top(sectionTag), 1f)
        assertFalse("$title is not current 12 dp short of the landing line: ${entryLabel()}", entryLabel().endsWith("current section $title"))
    }

    private fun settings() {
        launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), songs(FakeTransport.standard()))
        waitForTag("fst.settings.list")
        assertLands("show-instruments", "Show Instruments", "fst.settings.section.show-instruments")
        assertLands("accessibility", "Accessibility", "fst.settings.section.accessibility")
        // Back up to a section above: the landing line again, not the list's top.
        assertLands("item-shop", "Item Shop", "fst.settings.section.item-shop")
    }

    private fun profile() {
        val transport = songs(FakeTransport.standard()).apply { ProfileFixtures.register(this) }
        launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true), transport)
        waitForTag("fst.player.available")
        // Lazily built staggered-grid items: the jump lands after composing the target.
        assertLands("top-songs", "Top Songs", "fst.player.top-songs")
        assertLands("instrument:Solo_Bass", "Bass", "fst.player.instrument.Solo_Bass")
    }

    private fun leaderboards() {
        val transport = RankingsFixtures.install(songs(FakeTransport.standard()), unranked = setOf("Solo_Bass"))
        launch(DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true), transport)
        waitForTag("fst.leaderboards")
        assertLands("instrument:Solo_Drums", "Drums", "fst.leaderboards.card.Solo_Drums")
        assertLands("band:Band_Trios", "Trios", "fst.leaderboards.band-card.Band_Trios")
    }

    private fun compete() {
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true), CompeteFixtures.transport())
        waitForTag("fst.compete.section.leaderboards")
        // The heading keeps its 8 dp top padding inside the landed item.
        assertLands("rivals", "Rivals", "fst.compete.section.rivals", extraDp = 8f)
    }

    private fun settingsActivation() {
        launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), songs(FakeTransport.standard()))
        waitForTag("fst.settings.list")
        assertActivatesAtTheLandingLine("fst.settings.list", "fst.settings.section.show-instruments", "Show Instruments")
    }

    private fun profileActivation() {
        val transport = songs(FakeTransport.standard()).apply { ProfileFixtures.register(this) }
        launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true), transport)
        waitForTag("fst.player.available")
        assertActivatesAtTheLandingLine("fst.player.available", "fst.player.top-songs", "Top Songs")
    }

    private fun band() {
        val transport = BandFixtures.install(songs(FakeTransport.standard()))
        launch(DebugLaunch(route = DebugLaunch.parseRoute("band:${BandFixtures.DUO_ID}:Band_Duets:${BandFixtures.DUO_KEY}"), stillBackground = true), transport)
        waitForTag("fst.band.members-section")
        // Experimental Ranks is off, so the heading has no Rank By row and lands like Summary (#541).
        assertLands("statistics", "Statistics", "fst.band.statistics-section")
        assertLands("summary", "Summary", "fst.band.summary-section")
    }

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
    fun settingsActivationLineOnAPhone() = settingsActivation()

    @Test
    @Config(qualifiers = PHONE)
    fun playerActivationLineOnAPhone() = profileActivation()

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