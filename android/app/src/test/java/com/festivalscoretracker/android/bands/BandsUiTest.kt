package com.festivalscoretracker.android.bands

import androidx.compose.ui.semantics.getOrNull
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasTestTag
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

    private fun launch(route: String, profile: SelectedPlayer? = null) {
        val debug = DebugLaunch(route = DebugLaunch.parseRoute(route), profile = profile, stillBackground = true)
        val gated = object : HttpTransport {
            override suspend fun send(request: HttpRequest): HttpResult {
                hold(request)?.await()
                return transport.send(request)
            }
        }
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = gated, settingsStore = InMemoryPreferences())
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
        rule.onNodeWithText("Duos · 30 entries").assertIsDisplayed()
        // Web AccuracyDisplay: the full combo is the gold accuracy pill, not an "FC" chip (7.11).
        rule.onNodeWithContentDescription("Full combo, accuracy 100%", useUnmergedTree = true).assertExists()
        assertTrue(rule.onAllNodesWithText("FC", useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        assertTrue(rule.onAllNodesWithContentDescription("Accuracy 97.5%", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        waitForTag("fst.song-band-leaderboard.song")
        // The pager floats in the bottom bar, outside the list (shared RankingsBoardLayout, issue #307).
        click("fst.song-band-leaderboard.page-last")
        waitForTag("fst.song-band-leaderboard.row.band-26:26")
        rule.onNodeWithTag("fst.song-band-leaderboard.list").performScrollToNode(hasTestTag("fst.song-band-leaderboard.band-type.Band_Quad"))
        click("fst.song-band-leaderboard.band-type.Band_Quad")
        waitForTag("fst.song-band-leaderboard.empty")
        click("fst.song-band-leaderboard.band-type.Band_Trios")
        waitForTag("fst.song-band-leaderboard.row.band-1:1")
        click("fst.song-band-leaderboard.row.band-1:1")
        waitForTag("fst.band.screen")
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

    @Test
    fun songBandLeaderboardFailureAndSongLink() {
        transport.onRaw("/api/leaderboard/s-alpha/bands/Band_Duets") { HttpResult(500, ByteArray(0)) }
        launch("songBandLeaderboard:s-alpha")
        waitForTag("fst.song-band-leaderboard.error")
        waitForTag("fst.song-band-leaderboard.song")
        click("fst.song-band-leaderboard.song")
        waitForTag("fst.nav.back")
    }

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
