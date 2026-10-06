package com.festivalscoretracker.android.bands

import androidx.compose.ui.semantics.getOrNull
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.data.HttpRequest
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.common.spinnerShowsDuring
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlinx.coroutines.CompletableDeferred
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Whole-shell Bands journeys on Robolectric against synthetic band fixtures. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class BandsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport = BandFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    )
    private val player = SelectedPlayer(BandFixtures.PLAYER, "Synthetic Player")
    private val duoRoute = "band:${BandFixtures.DUO_ID}:Band_Duets:${BandFixtures.DUO_KEY}"

    /** Holds a matching request until the returned deferred completes (null = answer at once). */
    private var hold: (HttpRequest) -> CompletableDeferred<Unit>? = { null }

    private lateinit var container: AppContainer

    private fun launch(route: String, profile: SelectedPlayer? = null) {
        val debug = DebugLaunch(route = DebugLaunch.parseRoute(route), profile = profile, stillBackground = true)
        val gated = object : HttpTransport {
            override suspend fun send(request: HttpRequest): HttpResult {
                hold(request)?.await()
                return transport.send(request)
            }
        }
        container = AppContainer(rule.activity, OkHttpClient(), debug, transport = gated, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        settle()
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
            rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun click(tag: String) {
        rule.onNodeWithTag(tag, useUnmergedTree = true).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    private fun scrollTo(list: String, tag: String) {
        rule.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        settle()
    }

    private fun described(description: String) =
        rule.onAllNodesWithContentDescription(description, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    /**
     * Pages 1 → 2 with page 2's request held, checks the pager stays below the spinner, then taps
     * it again for page 3: page 3 must commit while page 2 is still pending, and the late page 2
     * must never show (issue #149, load-transition R4: a newer selection supersedes pending work).
     *
     * @param route Debug route of the paged list.
     * @param prefix Test-tag prefix (`<prefix>.list`, `.loading`, `.page-next`).
     * @param isPage2 Matches page 2's request URL.
     * @param rows A row tag on pages 1, 2 and 3.
     * @param pagerInList Whether the pager scrolls with the list (false: anchored below it).
     */
    private fun assertPagerSupersedesAPendingPage(route: String, prefix: String, isPage2: (String) -> Boolean, rows: Triple<String, String, String>, pagerInList: Boolean = true) {
        fun showPager() { if (pagerInList) scrollTo("$prefix.list", "$prefix.page-next") }
        BandFixtures.install(transport, bandCount = 80, boardTotal = 80)
        val page2 = CompletableDeferred<Unit>()
        hold = { request -> page2.takeIf { isPage2(request.url) } }
        launch(route)
        waitForTag(rows.first)
        showPager()
        assertTrue(described("Page 1 of 4"))
        click("$prefix.page-next")
        waitForTag("$prefix.loading")
        settle()
        // The pager stays below the spinner, on the requested page, and can still be used.
        showPager()
        rule.onNodeWithTag("$prefix.page-next", useUnmergedTree = true).assertIsDisplayed()
        assertTrue("the pager shows the requested page while it loads", described("Page 2 of 4"))
        click("$prefix.page-next")
        rule.waitUntil(10_000) { settle(100); !exists("$prefix.loading") }
        assertTrue("page 3 committed while page 2 was still pending", !page2.isCompleted)
        scrollTo("$prefix.list", rows.third)
        page2.complete(Unit)
        settle()
        settle()
        assertTrue(!exists("$prefix.loading"))
        assertTrue("a late page 2 never replaces page 3", !exists(rows.second))
        scrollTo("$prefix.list", rows.third)
        showPager()
        assertTrue(described("Page 3 of 4"))
    }

    // region Landing

    @Test
    fun bandsWithoutAnIdShowsBandNotFound() {
        launch("bands")
        waitForTag("fst.bands.not-found")
        rule.onNodeWithText("Band not found").assertIsDisplayed()
        assertTrue(transport.requests.none { it.url.contains("/api/bands") })
    }

    @Test
    fun playerBandsOpensBandDetail() {
        launch("playerBands:${player.accountId}", player)
        waitForTag("fst.player-bands.screen")
        waitForTag("fst.player-bands.row.${BandFixtures.DUO_ID}")
        rule.onNodeWithText("All Bands · 30 bands").assertIsDisplayed()
        click("fst.player-bands.row.${BandFixtures.DUO_ID}")
        waitForTag("fst.band.members-section")
    }

    // endregion

    // region Player bands

    @Test
    fun playerBandsGroupsPagingAndEmpty() {
        launch("playerBands:${BandFixtures.PLAYER}")
        waitForTag("fst.player-bands.row.${BandFixtures.DUO_ID}")
        // Name comes from the account's own member row when the route carries none.
        rule.onNodeWithText("Synthetic Lead's Bands").assertIsDisplayed()
        scrollTo("fst.player-bands.list", "fst.player-bands.page-next")
        click("fst.player-bands.page-next")
        waitForTag("fst.player-bands.row.band-25")
        assertTrue(transport.requests.last().url.contains("page=2"))
        click("fst.player-bands.page-first")
        click("fst.player-bands.group.duos")
        waitForTag("fst.player-bands.empty")
        click("fst.player-bands.group.quads")
        waitForTag("fst.player-bands.row.band-1")
        rule.onNodeWithText("Quads · 2 bands").assertIsDisplayed()
        assertEquals(false, exists("fst.player-bands.page-next"))
    }

    @Test
    fun playerBandsGroupChangeFadesThroughTheSpinner() {
        launch("playerBands:${BandFixtures.PLAYER}")
        waitForTag("fst.player-bands.row.${BandFixtures.DUO_ID}")
        // Issue #71: the old group's cards fade out and the spinner shows before the new group.
        assertTrue(rule.spinnerShowsDuring("fst.player-bands.loading") { rule.onNodeWithTag("fst.player-bands.group.quads", useUnmergedTree = true).performSemanticsAction(SemanticsActions.OnClick) })
        waitForTag("fst.player-bands.row.band-1")
        rule.waitUntil(10_000) { settle(100); !exists("fst.player-bands.loading") }
    }

    @Test
    fun playerBandsRouteOpensOnItsGroup() {
        launch("playerBands:${BandFixtures.PLAYER}:quads")
        waitForTag("fst.player-bands.row.band-1")
        rule.onNodeWithText("Quads · 2 bands").assertIsDisplayed()
        assertTrue(transport.sent("/api/player/${BandFixtures.PLAYER}/bands").all { it.url.contains("group=quads") })
    }

    @Test
    fun playerBandsPagerSupersedesAPendingPage() = assertPagerSupersedesAPendingPage(
        route = "playerBands:${BandFixtures.PLAYER}",
        prefix = "fst.player-bands",
        isPage2 = { "/api/player/${BandFixtures.PLAYER}/bands" in it && Regex("[?&]page=2(&|$)").containsMatchIn(it) },
        rows = Triple("fst.player-bands.row.${BandFixtures.DUO_ID}", "fst.player-bands.row.band-25", "fst.player-bands.row.band-50"),
    )

    @Test
    fun playerBandsFailureShowsRetry() {
        transport.on("/api/player/${BandFixtures.PLAYER}/bands", status = 500) { "{}" }
        launch("playerBands:${BandFixtures.PLAYER}")
        waitForTag("fst.player-bands.error")
        waitForTag("fst.service-status.retry")
    }

    @Test
    fun invalidPlayerAccountShowsNotFound() {
        launch("playerBands:bad.id")
        waitForTag("fst.player-bands.invalid")
    }

    private fun cardLeft(id: String) = rule.onNodeWithTag("fst.player-bands.row.$id").fetchSemanticsNode().boundsInRoot.left

    @Test
    @Config(qualifiers = "w900dp-h1200dp-xhdpi")
    fun wideWindowShowsTwoCardColumns() {
        launch("playerBands:${BandFixtures.PLAYER}")
        waitForTag("fst.player-bands.row.band-1")
        assertTrue(cardLeft("band-1") > cardLeft(BandFixtures.DUO_ID))
    }

    @Test
    @Config(qualifiers = "w900dp-h1200dp-xhdpi")
    fun largeTextUsesOneCardColumn() {
        RuntimeEnvironment.setFontScale(2f)
        launch("playerBands:${BandFixtures.PLAYER}")
        waitForTag("fst.player-bands.row.band-1")
        assertEquals(cardLeft(BandFixtures.DUO_ID), cardLeft("band-1"), 0.5f)
    }

    // endregion

    // region Band detail

    @Test
    fun bandDetailShowsSectionsAndLinks() {
        launch(duoRoute)
        waitForTag("fst.band.members-section")
        rule.onNodeWithText("Synthetic Lead + Synthetic Bass").assertIsDisplayed()
        rule.onNodeWithText("Duos · 29 appearances").assertIsDisplayed()
        assertTrue(exists("fst.band.member.${Fixtures.ACCOUNT_A}"))
        assertTrue(exists("fst.band.stat.rank"))
        rule.onNodeWithTag("fst.band.stat.rank").assert(hasContentDescription("Total Score Rank", substring = true))
        click("fst.band.rank-by")
        rule.onNodeWithTag("fst.band.rank-by.totalscore").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Selected"))
        rule.onNodeWithTag("fst.band.rank-by.fcrate").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Not selected"))
        click("fst.band.rank-by.fcrate")
        rule.onNodeWithTag("fst.band.stat.rank").assert(hasContentDescription("FC Rate Rank", substring = true))
        click("fst.band.rank-by")
        rule.onNodeWithTag("fst.band.rank-by.fcrate").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Selected"))
        // Choosing the current metric again only closes the menu.
        click("fst.band.rank-by.fcrate")
        assertTrue(!exists("fst.band.rank-by.totalscore"))
        rule.onNodeWithTag("fst.band.rank-by").assert(hasContentDescription("Rank by FC Rate"))
        waitForTag("fst.band.history-chart")
        assertTrue(exists("fst.band.history-row.2024-01-03"))
        waitForTag("fst.band.song-row.s-alpha")
        assertTrue(exists("fst.band.song-row.s-missing"))
        rule.onNodeWithTag("fst.band.song-row.s-missing").assert(hasContentDescription("Unknown Song", substring = true))
        click("fst.band.song-row.s-alpha")
        waitForTag("fst.nav.back")
        assertTrue(transport.requests.none { it.url.contains("/api/bands/") })
    }

    @Test
    fun bandMemberOpensPlayerAndStatLinksRankings() {
        launch(duoRoute)
        waitForTag("fst.band.member.${Fixtures.ACCOUNT_A}")
        click("fst.band.member.${Fixtures.ACCOUNT_A}")
        waitForTag("fst.player")
    }

    @Test
    fun bareBandIdIsUnresolvedWithoutRequests() {
        launch("band:${BandFixtures.DUO_ID}")
        waitForTag("fst.band.unresolved")
        assertTrue(transport.requests.none { it.url.contains("/rankings/bands") })
    }

    @Test
    fun unrankedBandAndSectionFailures() {
        transport.onRaw("/api/rankings/bands/Band_Duets/${BandFixtures.DUO_KEY}/songs") { HttpResult(500, ByteArray(0)) }
        transport.on("/api/rankings/bands/Band_Duets/${BandFixtures.DUO_KEY}/history") { BandFixtures.history(status = "stale", empty = true) }
        launch(duoRoute)
        waitForTag("fst.band.history-empty")
        rule.onNodeWithText("behind the latest", substring = true).assertExists()
        waitForTag("fst.service-status.inline")
    }

    @Test
    fun unknownTeamShowsNotFound() {
        launch("band:x:Band_Duets:${Fixtures.ACCOUNT_B}")
        waitForTag("fst.band.error")
    }

    @Test
    fun bandDetailQuickLinksJumpBetweenSections() {
        launch(duoRoute)
        waitForTag("fst.band.members-section")
        waitForTag("fst.quick-links.open")
        click("fst.quick-links.open")
        waitForTag("fst.quick-links.sheet")
        listOf("members", "summary", "statistics", "rank-history", "songs").forEach { waitForTag("fst.quick-links.item.$it") }
        click("fst.quick-links.item.songs")
        rule.waitUntil(10_000) { settle(100); !exists("fst.quick-links.sheet") }
        // The page jumped: the header's members section is off screen, the songs section on it.
        rule.onNodeWithTag("fst.band.songs-section", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithTag("fst.band.members-section", useUnmergedTree = true).assertIsNotDisplayed()
        click("fst.quick-links.open")
        waitForTag("fst.quick-links.item.members")
        click("fst.quick-links.item.members")
        rule.waitUntil(10_000) { settle(100); !exists("fst.quick-links.sheet") }
        rule.onNodeWithTag("fst.band.members-section", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2f)
    fun largeTextReflowsBandDetail() {
        launch(duoRoute)
        waitForTag("fst.band.members-section")
        // Heading above Rank By rather than beside it.
        settle(1_000)
        val heading = rule.onNodeWithTag("fst.band.statistics-section", useUnmergedTree = true).fetchSemanticsNode().let { it.positionInRoot.y + it.size.height }
        val rankBy = rule.onNodeWithTag("fst.band.rank-by").fetchSemanticsNode().positionInRoot.y
        assertTrue(rankBy >= heading)
        // One stat tile per row: each tile spans the content width, so values are never clipped.
        val rank = rule.onNodeWithTag("fst.band.stat.rank").fetchSemanticsNode().let { it.positionInRoot.x to it.size.width }
        val tiles = rule.onAllNodes(SemanticsMatcher("band stat tile") { it.config.getOrElseNullable(SemanticsProperties.TestTag) { null }?.startsWith("fst.band.stat.") == true })
            .fetchSemanticsNodes().map { it.positionInRoot.x to it.size.width }
        assertTrue(tiles.size > 1)
        assertTrue("$tiles", tiles.all { it == rank })
        // Member names get the card's full width; the instrument icons wrap under them.
        rule.onNodeWithTag("fst.band.member.${Fixtures.ACCOUNT_A}").assertIsDisplayed()
        // Song rows put the percentile and rank under the title instead of beside it.
        waitForTag("fst.band.song-row.s-alpha")
        rule.onNodeWithTag("fst.band.song-row.s-alpha").performScrollTo().assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-mdpi")
    fun expandedBandDetailSplitsIntoPanes() {
        launch(duoRoute)
        waitForTag("fst.band.pane.leading")
        assertTrue(exists("fst.band.pane.trailing"))
        waitForTag("fst.band.history-chart")
        // Both panes show every section: no Quick Links.
        assertTrue(!exists("fst.quick-links.open"))
    }

    // endregion

    // region Song band leaderboard

    @Test
    fun songBandLeaderboardSwitchesSizesAndOpensBands() {
        launch("songBandLeaderboard:s-alpha:Band_Duets")
        waitForTag("fst.song-band-leaderboard.row.band-1:1")
        // Web AccuracyDisplay: the full combo is the gold accuracy pill, not an "FC" chip (7.11).
        rule.onNodeWithContentDescription("Full combo, accuracy 100%", useUnmergedTree = true).assertExists()
        assertTrue(rule.onAllNodesWithText("FC", useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        assertTrue(rule.onAllNodesWithContentDescription("Accuracy 97.5%", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        waitForTag("fst.song-band-leaderboard.song")
        // Issue #315: the shared song header (one heading stop that opens Song Detail).
        rule.onNodeWithTag("fst.song-band-leaderboard.song").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading)).assertHasClickAction()
        // The pager floats in the bottom bar, outside the list (shared RankingsBoardLayout, issue #307).
        click("fst.song-band-leaderboard.page-last")
        waitForTag("fst.song-band-leaderboard.row.band-26:26")
        // The band size is the header's drop-down, like the solo board's instrument (issue #317).
        switchBandSize("Band_Quad")
        waitForTag("fst.song-band-leaderboard.empty")
        assertEquals("Quads", sizeLabel())
        assertTrue("the song header stays when the size changes", exists("fst.song-band-leaderboard.song"))
        switchBandSize("Band_Trios")
        waitForTag("fst.song-band-leaderboard.row.band-1:1")
        click("fst.song-band-leaderboard.row.band-1:1")
        waitForTag("fst.band.screen")
    }

    /** Opens the header's band-size drop-down and picks [wireId]. */
    private fun switchBandSize(wireId: String) {
        rule.onNodeWithTag("fst.song-band-leaderboard.list").performScrollToIndex(0)
        click("fst.song-band-leaderboard.band-type")
        waitForTag("fst.song-band-leaderboard.band-type-menu")
        click("fst.song-band-leaderboard.band-type.$wireId")
    }

    /** The visible band size in the header's switcher (the merged anchor TalkBack reads). */
    private fun sizeLabel(): String =
        rule.onNodeWithTag("fst.song-band-leaderboard.band-type").fetchSemanticsNode()
            .config.getOrNull(SemanticsProperties.Text)?.joinToString().orEmpty()

    private fun barTitle(): String =
        rule.onNodeWithTag("fst.nav.title", useUnmergedTree = true).fetchSemanticsNode()
            .config.getOrNull(SemanticsProperties.Text)?.joinToString().orEmpty()

    @Test
    fun songBandLeaderboardUsesTheSoloSongHeaderAndScrollAwayTitle() {
        launch("songBandLeaderboard:s-alpha:Band_Duets")
        waitForTag("fst.song-band-leaderboard.row.band-1:1")
        // Issue #317: the solo board's song header (one heading: title and artist), with the band
        // size where the instrument goes, and no "<Band> Leaderboard" bar title.
        rule.onNode(hasTestTag("fst.song-band-leaderboard.song")).assertIsDisplayed()
        rule.onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading) and hasText("Alpha Tune", substring = true)).assertExists()
        assertEquals("Duos", sizeLabel())
        val anchor = rule.onNodeWithTag("fst.song-band-leaderboard.band-type").fetchSemanticsNode().config
        assertEquals(Role.DropdownList, anchor.getOrNull(SemanticsProperties.Role))
        assertEquals("Switch band size", anchor.getOrNull(SemanticsActions.OnClick)?.label)
        assertTrue(rule.onAllNodesWithText("Duos Leaderboard", substring = true, useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        assertEquals("", barTitle())
        // Once the header scrolls away the bar takes the song title, as on the solo board.
        rule.onNodeWithTag("fst.song-band-leaderboard.list").performScrollToNode(hasTestTag("fst.song-band-leaderboard.row.band-20:20"))
        settle()
        rule.waitUntil(5_000) { settle(100); barTitle() == "Alpha Tune" }
    }

    @Test
    fun songBandLeaderboardShowsTheSongsStaticCover() {
        // With album art (the class default strips it), the board pushes the song's static cover.
        transport.on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson }
        launch("songBandLeaderboard:s-alpha:Band_Duets")
        waitForTag("fst.song-band-leaderboard.row.band-1:1")
        val cover = container.api.artworkUrl("alpha-512.jpg")
        assertTrue(cover != null)
        rule.waitUntil(5_000) { settle(100); container.background.focus.value == cover }
    }

    @Test
    fun songBandLeaderboardFailureKeepsTheSongHeader() {
        transport.onRaw("/api/leaderboard/s-alpha/bands/Band_Duets") { HttpResult(500, ByteArray(0)) }
        launch("songBandLeaderboard:s-alpha")
        waitForTag("fst.song-band-leaderboard.error")
        waitForTag("fst.song-band-leaderboard.song")
        assertTrue(exists("fst.song-band-leaderboard.band-type"))
        // The header's title opens the song (web `onTitleClick`, issue #315).
        click("fst.song-band-leaderboard.song")
        waitForTag("fst.song-detail.header")
    }

    // region Selected band (leaderboard-row R7, issue #307)

    private fun clickLabel(tag: String) =
        rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config.getOrNull(SemanticsActions.OnClick)?.label

    private fun bounds(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0].fetchSemanticsNode().boundsInRoot

    /** Whether a row sits wholly in the list's area above the pinned footer and pager. */
    private fun inView(tag: String): Boolean {
        val row = bounds(tag)
        return row.top >= bounds("fst.song-band-leaderboard.list").top && row.bottom <= bounds("fst.song-band-leaderboard.bottom-bar").top
    }

    /** Puts the selected player's Duos band at [rank] on a 60-band board. */
    private fun selectedDuoAt(rank: Int) {
        transport.on("/api/leaderboard/s-alpha/bands/Band_Duets", headers = mapOf("X-FST-Publication-Id" to "7")) { request ->
            val top = Regex("top=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            val offset = Regex("offset=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            BandFixtures.songBoard("s-alpha", "Band_Duets", 60, offset, top, rank.takeIf { "accountId=${BandFixtures.PLAYER}" in request.url })
        }
    }

    @Test
    fun songBandLeaderboardPinsTheSelectedBandWhichOpensItWhenOnScreen() {
        launch("songBandLeaderboard:s-alpha:Band_Duets", player)
        waitForTag("fst.song-band-leaderboard.spotlight-footer")
        // Read with the allowlisted `accountId=` query only (no selected-profile headers).
        assertTrue(transport.sent("/api/leaderboard/s-alpha/bands/Band_Duets").all { "accountId=${BandFixtures.PLAYER}" in it.url })
        assertTrue(transport.requests.none { request -> request.headers.keys.any { it.startsWith("X-FST-Selected", ignoreCase = true) } })
        // Rank 12 is on page 1: the footer opens the Band page, like the in-place row.
        assertEquals("Open band", clickLabel("fst.song-band-leaderboard.spotlight-footer"))
        click("fst.song-band-leaderboard.spotlight-footer")
        waitForTag("fst.band.screen")
    }

    @Test
    fun songBandLeaderboardWithoutAPlayerPinsNothing() {
        launch("songBandLeaderboard:s-alpha:Band_Duets")
        waitForTag("fst.song-band-leaderboard.row.band-1:1")
        assertTrue(!exists("fst.song-band-leaderboard.spotlight-footer"))
        assertTrue(transport.sent("/api/leaderboard/s-alpha/bands/Band_Duets").none { "accountId" in it.url })
    }

    @Test
    fun songBandLeaderboardFooterJumpsToTheBandsPageAndRevealsIt() {
        selectedDuoAt(40)
        launch("songBandLeaderboard:s-alpha:Band_Duets", player)
        waitForTag("fst.song-band-leaderboard.spotlight-footer")
        assertEquals("Jump to your band's position", clickLabel("fst.song-band-leaderboard.spotlight-footer"))
        click("fst.song-band-leaderboard.spotlight-footer")
        waitForTag("fst.song-band-leaderboard.row.band-40:40")
        rule.waitUntil(10_000) { settle(100); inView("fst.song-band-leaderboard.row.band-40:40") }
        assertTrue(transport.sent("/api/leaderboard/s-alpha/bands/Band_Duets").any { "offset=25" in it.url })
        // Now on screen: the same footer opens the Band page.
        assertEquals("Open band", clickLabel("fst.song-band-leaderboard.spotlight-footer"))
    }

    @Test
    fun songBandLeaderboardHidesTheStalePinnedBandWhileThePageLoads() {
        // Same rule as the solo board's pinned score (load-transition R2, issue #149).
        val footerTag = "fst.song-band-leaderboard.spotlight-footer"
        selectedDuoAt(12)
        val nextPage = CompletableDeferred<Unit>()
        hold = { request -> nextPage.takeIf { "/api/leaderboard/s-alpha/bands/Band_Duets" in request.url && "offset=25" in request.url } }
        launch("songBandLeaderboard:s-alpha:Band_Duets", player)
        waitForTag(footerTag)
        val pinned = rule.onNodeWithTag(footerTag).fetchSemanticsNode().boundsInRoot.center
        click("fst.song-band-leaderboard.page-next")
        waitForTag("fst.song-band-leaderboard.loading")
        settle()
        // The merged tree is what TalkBack reads.
        assertTrue("page 1's pinned band must not show under the spinner", rule.onAllNodesWithTag(footerTag).fetchSemanticsNodes().isEmpty())
        rule.onRoot().performTouchInput { this.click(pinned) }
        settle()
        assertTrue("a tap where the pinned band was must not open it", exists("fst.song-band-leaderboard.loading") && !exists("fst.band.screen"))
        nextPage.complete(Unit)
        rule.waitUntil(10_000) { settle(100); !exists("fst.song-band-leaderboard.loading") }
        assertTrue("the pinned band returns with the new page", rule.onAllNodesWithTag(footerTag).fetchSemanticsNodes().isNotEmpty())
    }

    @Test
    fun songBandLeaderboardOpenedForTheBandRevealsItsRow() {
        selectedDuoAt(47)
        launch("songBandLeaderboard:s-alpha:Band_Duets:2:reveal", player)
        waitForTag("fst.song-band-leaderboard.row.band-47:47")
        rule.waitUntil(10_000) { settle(100); inView("fst.song-band-leaderboard.row.band-47:47") }
        assertEquals("Open band", clickLabel("fst.song-band-leaderboard.spotlight-footer"))
    }

    // endregion
    @Test
    fun songBandLeaderboardPagerSupersedesAPendingPage() = assertPagerSupersedesAPendingPage(
        route = "songBandLeaderboard:s-alpha:Band_Duets",
        prefix = "fst.song-band-leaderboard",
        isPage2 = { "/api/leaderboard/s-alpha/bands/Band_Duets" in it && Regex("[?&]offset=25(&|$)").containsMatchIn(it) },
        rows = Triple("fst.song-band-leaderboard.row.band-1:1", "fst.song-band-leaderboard.row.band-26:26", "fst.song-band-leaderboard.row.band-51:51"),
        pagerInList = false,
    )

    // endregion

    @Test
    fun debugRoutesParseBandShapes() {
        val band = DebugLaunch.parseRoute("band:id:Band_Trios:a:b:c") as com.festivalscoretracker.android.core.nav.BandRoute
        assertEquals("a:b:c", band.teamKey)
        assertEquals("Band_Trios", band.bandType)
        val bare = DebugLaunch.parseRoute("band:id") as com.festivalscoretracker.android.core.nav.BandRoute
        assertEquals(null, bare.teamKey)
        val board = DebugLaunch.parseRoute("songBandLeaderboard:s-1") as com.festivalscoretracker.android.core.nav.SongBandLeaderboardRoute
        assertEquals("Band_Duets", board.bandType)
        assertEquals(null, DebugLaunch.parseRoute("songBandLeaderboard"))
        val jump = DebugLaunch.parseRoute("songBandLeaderboard:s-1:Band_Trios:3:reveal") as com.festivalscoretracker.android.core.nav.SongBandLeaderboardRoute
        assertEquals(3, jump.page)
        assertTrue(jump.navToBand)
        assertEquals(1, board.page)
    }
}
