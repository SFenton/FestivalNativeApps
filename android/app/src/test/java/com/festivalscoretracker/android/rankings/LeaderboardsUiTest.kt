package com.festivalscoretracker.android.rankings

import com.festivalscoretracker.android.testing.RankingsFixtures
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
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
import com.festivalscoretracker.android.data.rankings.LeaderboardPreferences
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.ui.common.spinnerShowsDuring
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import androidx.compose.ui.test.SemanticsMatcher
import androidx.datastore.preferences.core.booleanPreferencesKey
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import kotlinx.coroutines.CompletableDeferred
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

/** Shared harness for the Leaderboards journeys on Robolectric against synthetic rankings. */
abstract class LeaderboardsHarness {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    protected val transport: FakeTransport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
        unranked = setOf("Solo_Bass"),
    )
    protected val store = InMemoryPreferences()
    protected val selected = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player")

    /** Holds a matching request until the returned deferred completes (null = answer at once). */
    protected var hold: (HttpRequest) -> CompletableDeferred<Unit>? = { null }

    protected fun launch(route: String, profile: SelectedPlayer? = null) {
        val debug = DebugLaunch(route = DebugLaunch.parseRoute(route), profile = profile, stillBackground = true)
        val gated = object : HttpTransport {
            override suspend fun send(request: HttpRequest): HttpResult {
                hold(request)?.await()
                return transport.send(request)
            }
        }
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = gated, settingsStore = store)
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    protected fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    protected fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    protected fun waitForTag(tag: String) {
        rule.waitUntil(10_000) { settle(100); exists(tag) }
    }

    protected fun waitForText(text: String) {
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
    }

    protected fun waitForDescription(text: String) {
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithContentDescription(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
    }

    /** First node with a tag (the same account can appear on several overview cards). */
    protected fun node(tag: String): SemanticsNodeInteraction = rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0]

    protected fun click(tag: String) {
        node(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    protected fun scrollTo(list: String, tag: String) {
        rule.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        settle()
    }

    protected fun isClickable(tag: String) = node(tag).fetchSemanticsNode().config.getOrNull(SemanticsActions.OnClick) != null

    protected fun description(tag: String) = node(tag).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString()
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class LeaderboardsUiTest : LeaderboardsHarness() {
    private val lead = "fst.leaderboards.card.Solo_Guitar"

    @Test
    fun overviewCardsRankByAndViewAll() {
        launch("leaderboards")
        waitForTag("fst.rankings.row.${RankingsFixtures.accountId(1)}")
        assertTrue(exists(lead))
        // No selected player: no rank-history card and no history read.
        assertFalse(exists("fst.leaderboards.rank-history"))
        assertTrue(transport.requests.none { it.url.contains("/history") })
        assertEquals("#1. Synthetic Player 1. 49,999,000. 199 / 250 songs.", description("fst.rankings.row.${RankingsFixtures.accountId(1)}"))
        // Anonymous production rows read "Unknown User" and do nothing.
        val anonymous = "fst.rankings.row.anonymous-3-3-3"
        assertTrue(description(anonymous)!!.contains("Unknown User"))
        assertFalse(isClickable(anonymous))
        assertTrue(isClickable("fst.rankings.row.${RankingsFixtures.accountId(1)}"))
        // Twelve top-ten reads (nine charts + three band sizes), none of them account-scoped.
        assertEquals(12, transport.requests.count { it.url.contains("/api/rankings/") && it.url.contains("pageSize=10") })
        assertTrue(transport.requests.none { it.url.contains(RankingsFixtures.SELECTED) })

        click("fst.rankings.rank-by-menu")
        click("fst.rankings.rank-by.fcrate")
        rule.waitUntil(10_000) { settle(100); transport.requests.any { it.url.contains("rankBy=fcrate") } }
        waitForDescription("Rank By, FC Rate")
        assertEquals("fcrate", store.current[LeaderboardPreferences.KEY_RANK_BY])

        scrollTo("fst.leaderboards", "$lead.view-all")
        waitForText("View All Rankings (60)")
        click("$lead.view-all")
        waitForText("Lead Leaderboards")
        waitForTag("fst.full-rankings.population")
        waitForDescription("Page 1 of 3")
        assertTrue(transport.requests.last { it.url.contains("/api/rankings/Solo_Guitar") }.url.contains("rankBy=fcrate&page=1&pageSize=25"))
        click("fst.full-rankings.page-next")
        waitForDescription("Page 2 of 3")
        click("fst.full-rankings.page-last")
        waitForDescription("Page 3 of 3")
        click("fst.full-rankings.page-first")
        waitForDescription("Page 1 of 3")
        click("fst.full-rankings.instrument-menu")
        click("fst.full-rankings.instrument-menu.1")
        waitForText("Bass Leaderboards")
        click("fst.nav.back")
        waitForTag(lead)
    }

    @Test
    fun spotlightFooterAndYourPage() {
        launch("leaderboards", selected)
        waitForTag("fst.leaderboards.rank-history")
        rule.waitUntil(10_000) { settle(100); runCatching { scrollTo("fst.leaderboards", "$lead.spotlight") }.isSuccess }
        waitForTag("$lead.spotlight")
        assertTrue(description("$lead.spotlight")!!.startsWith("Your rank, #40. Synthetic Player 40."))
        scrollTo("fst.leaderboards", "fst.leaderboards.card.Solo_Bass.spotlight.unranked")
        waitForTag("fst.leaderboards.card.Solo_Bass.spotlight.unranked")
        scrollTo("fst.leaderboards", "$lead.spotlight")
        // The selected player's row opens Statistics, like the web.
        click("$lead.spotlight")
        rule.waitUntil(10_000) { settle(100); !exists(lead) }
    }

    @Test
    fun fullRankingsPinsTheSelectedRowOnEveryPage() {
        launch("fullRankings:Solo_Guitar", selected)
        val footer = "fst.full-rankings.spotlight-footer"
        waitForTag(footer)
        // Leaderboard-row R7: off this page, the pinned row jumps to the player's page.
        assertEquals("Jump to your position", clickLabel(footer))
        click(footer)
        waitForDescription("Page 2 of 3")
        waitForTag("fst.rankings.row.${RankingsFixtures.SELECTED}")
        // Issue #318: on the player's own page the row stays pinned (like the song boards) and opens Statistics.
        rule.waitUntil(5_000) { settle(100); clickLabel(footer) == "Open your statistics" }
        assertTrue(exists(footer))
        click(footer)
        rule.waitUntil(10_000) { settle(100); !exists("fst.full-rankings.list") }
    }

    @Test
    fun fullRankingsRowsLeaveTheScreenAboveTheFooter() {
        launch("fullRankings:Solo_Guitar", selected)
        waitForTag("fst.full-rankings.spotlight-footer")
        // Issue #115: rows fade out above the pinned rank and pager (like the Song Leaderboard),
        // so rows beneath them leave touch and TalkBack instead of showing through the pager.
        val list = node("fst.full-rankings.list").fetchSemanticsNode().boundsInRoot
        val footer = node("fst.full-rankings.bottom-bar").fetchSemanticsNode().boundsInRoot
        assertTrue("the list $list ends at the footer $footer", list.bottom <= footer.top + 1f)
        // One-line rows on a phone: rank, name, songs and rating share a 48 dp row.
        val row = node("fst.rankings.row.${RankingsFixtures.accountId(1)}").fetchSemanticsNode()
        assertTrue(with(rule.density) { row.size.height.toDp() } < 64.dp)
    }

    @Test
    fun pageChangesFadeThroughTheSpinnerLikeTheWeb() {
        launch("fullRankings:Solo_Guitar")
        waitForDescription("Page 1 of 3")
        assertFalse(exists("fst.full-rankings.loading"))
        // Issue #71: even a page served at once fades the old rows out and shows the spinner.
        rule.mainClock.autoAdvance = false
        node("fst.full-rankings.page-next").performSemanticsAction(SemanticsActions.OnClick)
        var sawSpinner = false
        repeat(80) {
            rule.mainClock.advanceTimeBy(32)
            shadowOf(Looper.getMainLooper()).idle()
            if (exists("fst.full-rankings.loading")) sawSpinner = true
        }
        rule.mainClock.autoAdvance = true
        assertTrue(sawSpinner)
        waitForDescription("Page 2 of 3")
        waitForTag("fst.rankings.row.${RankingsFixtures.accountId(26)}")
        rule.waitUntil(5_000) { settle(100); !exists("fst.full-rankings.loading") }
    }

    @Test
    fun bandRankingsPageChangesFadeThroughTheSpinner() {
        launch("bandRankings:Band_Trios")
        waitForDescription("Page 1 of 2")
        assertTrue(rule.spinnerShowsDuring("fst.band-rankings.loading") { node("fst.band-rankings.page-next").performSemanticsAction(SemanticsActions.OnClick) })
        waitForDescription("Page 2 of 2")
        rule.waitUntil(5_000) { settle(100); !exists("fst.band-rankings.loading") }
    }

    @Test
    fun rankHistoryChartSwitchFadesThroughTheSpinner() {
        launch("leaderboards", selected)
        waitForTag("fst.leaderboards.rank-history")
        waitForText(LocalDate.now().format(DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US)))
        assertTrue(rule.spinnerShowsDuring("fst.leaderboards.rank-history.loading") { node("fst.leaderboards.rank-history.picker.Solo_Bass").performSemanticsAction(SemanticsActions.OnClick) })
        waitForText("No rank history for Bass")
        rule.waitUntil(5_000) { settle(100); !exists("fst.leaderboards.rank-history.loading") }
    }

    /**
     * Changes Rank By with the new lead card held: the overview fades through its spinner, and
     * the old cards kept composed beneath it are hidden from TalkBack and ignore a tap where a
     * row was (load-transition R2, issue #178).
     */
    private fun assertOverviewRankByHidesTheOldCards(reduceMotion: Boolean) {
        if (reduceMotion) {
            runBlocking { store.updateData { it.toMutablePreferences().apply { this[booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION)] = true } } }
        }
        val fcRate = CompletableDeferred<Unit>()
        hold = { request -> fcRate.takeIf { request.url.contains("/api/rankings/Solo_Guitar") && request.url.contains("rankBy=fcrate") } }
        launch("leaderboards")
        val row = "fst.rankings.row.${RankingsFixtures.accountId(1)}"
        waitForTag(row)
        val place = node(row).fetchSemanticsNode().boundsInRoot.center
        click("fst.rankings.rank-by-menu")
        // The old rows stay up and fade with the page until the spinner shows: they never cut to
        // the new Rank By's empty loading rows first (issue #178).
        val keepsOldRows = { assertTrue("the old rows must fade out, not vanish, before the spinner", exists(row)) }
        assertTrue(rule.spinnerShowsDuring("fst.leaderboards.loading", beforeSpinner = keepsOldRows) { node("fst.rankings.rank-by.fcrate").performSemanticsAction(SemanticsActions.OnClick) })
        settle()
        assertTrue(exists("fst.leaderboards.loading"))
        // The merged tree is what TalkBack reads; the unmerged one still lists cleared descendants.
        assertTrue("the old cards must not be read under the spinner", rule.onAllNodesWithTag(row).fetchSemanticsNodes().isEmpty())
        rule.onRoot().performTouchInput { this.click(place) }
        settle()
        assertTrue("a tap where a row was must not open a profile", exists("fst.leaderboards.loading"))
        fcRate.complete(Unit)
        rule.waitUntil(10_000) { settle(100); !exists("fst.leaderboards.loading") }
        waitForTag(row)
        assertTrue(isClickable(row))
    }

    @Test
    fun overviewRankByFadesThroughTheSpinnerAndHidesTheOldCards() = assertOverviewRankByHidesTheOldCards(reduceMotion = false)

    @Test
    fun overviewRankByHidesTheOldCardsUnderReduceMotion() = assertOverviewRankByHidesTheOldCards(reduceMotion = true)

    @Test
    fun rankHistoryAndQuickLinksOnTheOverview() {
        launch("leaderboards", selected)
        waitForTag("fst.leaderboards.rank-history")
        // The chart carries the fixture history forward to today and lists the newest days.
        waitForText(LocalDate.now().format(DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US)))
        assertTrue(transport.requests.any { it.url.contains("/api/rankings/Solo_Guitar/${RankingsFixtures.SELECTED}/history?days=30") })
        click("fst.leaderboards.rank-history.picker.Solo_Bass")
        waitForText("No rank history for Bass")
        // Quick Links float with Rank By on phones and jump to a band card.
        click("fst.quick-links.open")
        waitForTag("fst.quick-links.sheet")
        click("fst.quick-links.item.band:Band_Trios")
        rule.waitUntil(10_000) { settle(100); !exists("fst.quick-links.sheet") }
        waitForTag("fst.leaderboards.band-card.Band_Trios")
        assertFalse(exists("fst.leaderboards.rank-history"))
    }

    @Test
    fun boardsRestoreTheRoutedPageAndFloatThePager() {
        launch("fullRankings:Solo_Guitar:2")
        waitForDescription("Page 2 of 3")
        assertTrue(transport.requests.any { it.url.contains("/api/rankings/Solo_Guitar?rankBy=totalscore&page=2&pageSize=25") })
        // Pickers are screen actions (floating toolbar on phones), not list content.
        assertTrue(exists("fst.full-rankings.instrument-menu"))
        assertTrue(exists("fst.rankings.rank-by-menu"))
        val pager = node("fst.full-rankings.pager").fetchSemanticsNode().boundsInRoot
        val list = node("fst.full-rankings.list").fetchSemanticsNode().boundsInRoot
        assertTrue("pager $pager is anchored to the bottom of $list", pager.bottom > list.bottom - list.height / 4)
        click("fst.rankings.rank-by-menu")
        click("fst.rankings.rank-by.fcrate")
        waitForDescription("Page 1 of 3")
        waitForText("60 ranked players")
    }

    @Test
    fun bandsHeaderOpensBandRankings() {
        launch("leaderboards")
        waitForTag("fst.rankings.row.${RankingsFixtures.accountId(1)}")
        scrollTo("fst.leaderboards", "fst.leaderboards.bands-link")
        click("fst.leaderboards.bands-link")
        waitForText("Duos Leaderboards")
    }

    @Test
    fun bandBoardsRestoreTheRoutedPage() {
        launch("bandRankings:Band_Duets:2")
        waitForDescription("Page 2 of 2")
    }

    @Test
    fun overviewRowsNameTheirTalkBackActions() {
        launch("leaderboards", selected)
        val other = "fst.rankings.row.${RankingsFixtures.accountId(1)}"
        waitForTag(other)
        // TalkBack says "Double-tap to open profile" rather than a bare "open" (issue #114).
        assertEquals("Open profile", clickLabel(other))
        val anonymous = node("fst.rankings.row.anonymous-3-3-3").fetchSemanticsNode().config
        assertEquals("Profile unavailable", anonymous.getOrNull(SemanticsProperties.StateDescription))
        rule.waitUntil(10_000) { settle(100); runCatching { scrollTo("fst.leaderboards", "$lead.spotlight") }.isSuccess }
        waitForTag("$lead.spotlight")
        assertEquals("Open your statistics", clickLabel("$lead.spotlight"))
        val band = "fst.band-rankings.row.${RankingsFixtures.accountId(1001)}:${RankingsFixtures.accountId(2001)}"
        scrollTo("fst.leaderboards", band)
        waitForTag(band)
        assertEquals("Open band", clickLabel(band))
        assertEquals(Role.Button, node(band).fetchSemanticsNode().config.getOrNull(SemanticsProperties.Role))
    }

    @Test
    fun failedCardRetriesInline() {
        var fail = true
        transport.onRaw("/api/rankings/Solo_Guitar") { request ->
            if (fail) {
                HttpResult(500, ByteArray(0))
            } else {
                HttpResult(200, RankingsFixtures.rankings("Solo_Guitar", "totalscore", 1, 10).toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
            }
        }
        launch("leaderboards")
        waitForTag("fst.service-status.inline")
        fail = false
        rule.onAllNodesWithText("Retry", useUnmergedTree = true)[0].performClick()
        waitForTag("fst.rankings.row.${RankingsFixtures.accountId(1)}")
    }

    @Test
    fun bandRankingsPagesSwitchSizeAndOpenBands() {
        launch("bandRankings:Band_Trios", selected)
        waitForText("Trios Leaderboards")
        waitForTag("fst.band-rankings.population")
        waitForDescription("Page 1 of 2")
        val second = "fst.band-rankings.row.${RankingsFixtures.SELECTED}:${RankingsFixtures.accountId(2002)}"
        assertTrue(description(second)!!.startsWith("Your rank, #2. Member 2A + Unknown User."))
        click("fst.band-rankings.page-next")
        waitForDescription("Page 2 of 2")
        click("fst.band-rankings.band-type-menu")
        click("fst.band-rankings.band-type-menu.2")
        waitForText("Quads Leaderboards")
        waitForDescription("Page 1 of 2")
        click("fst.band-rankings.rank-by-menu")
        click("fst.band-rankings.rank-by-menu.2")
        rule.waitUntil(10_000) { settle(100); transport.requests.any { it.url.contains("/api/rankings/bands/Band_Quad?rankBy=fcrate") } }
        val first = "fst.band-rankings.row.${RankingsFixtures.accountId(1001)}:${RankingsFixtures.accountId(2001)}"
        waitForTag(first)
        click(first)
        rule.waitUntil(10_000) { settle(100); !exists("fst.band-rankings.list") }
        assertTrue(transport.requests.none { it.url.contains("/api/bands/") })
    }

    @Test
    fun songLeaderboardPinsTheSelectedScoreRowLikeTheWeb() {
        transport.on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
            ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", rank = 30, total = 60)))
        }
        launch("songLeaderboard:s-alpha:Solo_Guitar", selected)
        // Web footer: only the player's row (no page-jump button, 7.9).
        waitForTag("fst.song-leaderboard.spotlight-footer")
        assertTrue(!exists("fst.song-leaderboard.spotlight-jump"))
        // The pinned row shares the board's columns, so its score lines up with the rows above (issue #37).
        val footerScore = scoreBounds("fst.song-leaderboard.spotlight-footer")
        val rowScores = rule.onAllNodes(hasTestTag("fst.score") and hasAnyAncestor(hasTestTag("fst.song-leaderboard.list")), useUnmergedTree = true)
            .fetchSemanticsNodes().map { it.boundsInRoot }.filter { it.width > 0f }
        assertTrue(rowScores.size > 1)
        for (bounds in rowScores) {
            assertEquals(footerScore.right, bounds.right, 0.5f)
            assertEquals(footerScore.width, bounds.width, 0.5f)
        }
    }

    @Test
    fun songLeaderboardKeepsItsHeaderPinnedScoreAndPagerWhilePaging() {
        transport.on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
            ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", rank = 30, total = 60)))
        }
        val nextPage = CompletableDeferred<Unit>()
        hold = { request -> nextPage.takeIf { request.url.contains("/api/leaderboard/s-alpha/Solo_Guitar") && request.url.contains("offset=25") } }
        launch("songLeaderboard:s-alpha:Solo_Guitar", selected)
        waitForDescription("Page 1 of 3")
        waitForTag("fst.song-leaderboard.spotlight-footer")
        click("fst.song-leaderboard.page-next")
        // Issue #93: only the rows swap to the spinner; the song header, instrument picker,
        // pinned score and pager stay put while the next page loads, as on the web.
        waitForTag("fst.song-leaderboard.loading")
        assertTrue(exists("fst.song-leaderboard.instrument"))
        assertTrue(exists("fst.song-leaderboard.spotlight-footer"))
        assertTrue(exists("fst.song-leaderboard.pager"))
        assertTrue(exists("fst.song-leaderboard.page-next"))
        nextPage.complete(Unit)
        waitForDescription("Page 2 of 3")
        rule.waitUntil(5_000) { settle(100); !exists("fst.song-leaderboard.loading") }
        assertTrue(exists("fst.song-leaderboard.pager"))
    }

    // region Pinned score reveal (issue #295)

    private val footerTag = "fst.song-leaderboard.spotlight-footer"

    private fun top(tag: String) = node(tag).fetchSemanticsNode().boundsInRoot.top

    private fun scoreRows() = rule.onAllNodes(
        SemanticsMatcher("score row") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.song-leaderboard.row.") == true },
        useUnmergedTree = true,
    ).fetchSemanticsNodes()

    /** Topmost score row of the shown page. */
    private fun firstRowTag(): String = scoreRows().filter { it.boundsInRoot.width > 0f }.minBy { it.boundsInRoot.top }.config[SemanticsProperties.TestTag]

    /**
     * Releases [gate] with the frame clock paused, steps frames until the page's rows are
     * composed, then returns how far (px) the first row and the pinned footer still sit below
     * their settled places [FADE_PROBE_MS] into the `fadeInUp` entrance.
     */
    private fun revealDrift(gate: CompletableDeferred<Unit>): Pair<Float, Float> {
        rule.mainClock.autoAdvance = false
        gate.complete(Unit)
        var frames = 0
        while (exists("fst.song-leaderboard.loading") || !exists(footerTag) || scoreRows().isEmpty()) {
            check(frames++ < 2_000) { "rows never revealed" }
            shadowOf(Looper.getMainLooper()).idle()
            rule.mainClock.advanceTimeByFrame()
        }
        val row = firstRowTag()
        rule.mainClock.advanceTimeBy(FADE_PROBE_MS)
        val rowMid = top(row)
        val footerMid = top(footerTag)
        rule.mainClock.advanceTimeBy(2_000)
        return (rowMid - top(row)) to (footerMid - top(footerTag))
    }

    /**
     * Up to one frame of the entrance (16 ms of 400 ms ≈ 10% of the 12 dp drift): the footer slot
     * may start its fade a frame after the list's rows.
     */
    private fun frameTolerance() = with(rule.density) { 1.2.dp.toPx() }

    @Test
    fun songLeaderboardPinnedScoreFadesInWithTheFirstRows() {
        transport.on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
            ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", rank = 30, total = 60)))
        }
        val firstPage = CompletableDeferred<Unit>()
        hold = { request -> firstPage.takeIf { request.url.contains("/api/leaderboard/s-alpha/Solo_Guitar") && !request.url.contains("offset=25") } }
        launch("songLeaderboard:s-alpha:Solo_Guitar", selected)
        rule.waitUntil(10_000) { settle(100); transport.requests.any { it.url.contains("/api/player/${RankingsFixtures.SELECTED}") } }
        settle()
        val (row, footer) = revealDrift(firstPage)
        assertTrue("the first row is still drifting up", row > 0.5f)
        assertEquals("the pinned score drifts and fades with it", row, footer, frameTolerance())
    }

    @Test
    fun songLeaderboardPagingReRevealsThePinnedScoreWithTheNewRows() {
        transport.on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
            ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", rank = 60, total = 60)))
        }
        val nextPage = CompletableDeferred<Unit>()
        hold = { request -> nextPage.takeIf { request.url.contains("/api/leaderboard/s-alpha/Solo_Guitar") && request.url.contains("offset=25") } }
        launch("songLeaderboard:s-alpha:Solo_Guitar", selected)
        waitForDescription("Page 1 of 3")
        waitForTag(footerTag)
        click("fst.song-leaderboard.page-next")
        waitForTag("fst.song-leaderboard.loading")
        val (row, footer) = revealDrift(nextPage)
        assertTrue("the new page's first row is still drifting up", row > 0.5f)
        assertEquals("the pinned score re-reveals with it", row, footer, frameTolerance())
    }

    @Test
    fun songLeaderboardPinnedScoreAppearsWithTheRowsUnderReduceMotion() {
        transport.on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
            ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", rank = 30, total = 60)))
        }
        runBlocking { store.updateData { it.toMutablePreferences().apply { this[booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION)] = true } } }
        val firstPage = CompletableDeferred<Unit>()
        hold = { request -> firstPage.takeIf { request.url.contains("/api/leaderboard/s-alpha/Solo_Guitar") && !request.url.contains("offset=25") } }
        launch("songLeaderboard:s-alpha:Solo_Guitar", selected)
        rule.waitUntil(10_000) { settle(100); transport.requests.any { it.url.contains("/api/player/${RankingsFixtures.SELECTED}") } }
        settle()
        val (row, footer) = revealDrift(firstPage)
        assertEquals(0f, row, 0.5f)
        assertEquals(0f, footer, 0.5f)
    }

    /**
     * Pages from page 1 (selected score pinned) to a held page 2 and checks the stale pinned row
     * is hidden from TalkBack and ignores a tap at its old place while the spinner shows (issue #149).
     */
    private fun assertStalePinnedRowHiddenWhilePaging(reduceMotion: Boolean) {
        transport.on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
            ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", rank = 30, total = 60)))
        }
        if (reduceMotion) {
            runBlocking { store.updateData { it.toMutablePreferences().apply { this[booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION)] = true } } }
        }
        val nextPage = CompletableDeferred<Unit>()
        hold = { request -> nextPage.takeIf { request.url.contains("/api/leaderboard/s-alpha/Solo_Guitar") && request.url.contains("offset=25") } }
        launch("songLeaderboard:s-alpha:Solo_Guitar", selected)
        waitForDescription("Page 1 of 3")
        waitForTag(footerTag)
        val pinned = node(footerTag).fetchSemanticsNode().boundsInRoot.center
        assertTrue(rule.onAllNodesWithTag(footerTag).fetchSemanticsNodes().isNotEmpty())
        click("fst.song-leaderboard.page-next")
        waitForTag("fst.song-leaderboard.loading")
        settle()
        // The merged tree is what TalkBack reads; the unmerged one still lists cleared descendants.
        assertTrue("page 1's pinned row must not show under the spinner", rule.onAllNodesWithTag(footerTag).fetchSemanticsNodes().isEmpty())
        rule.onRoot().performTouchInput { this.click(pinned) }
        settle()
        assertTrue("a tap where the pinned row was must not open a player", exists("fst.song-leaderboard.loading"))
        nextPage.complete(Unit)
        waitForDescription("Page 2 of 3")
        rule.waitUntil(5_000) { settle(100); !exists("fst.song-leaderboard.loading") }
        assertTrue("the pinned score returns with the new page", exists(footerTag))
    }

    @Test
    fun songLeaderboardHidesTheStalePinnedScoreWhileThePageLoads() = assertStalePinnedRowHiddenWhilePaging(reduceMotion = false)

    @Test
    fun songLeaderboardHidesTheStalePinnedScoreWhileThePageLoadsUnderReduceMotion() = assertStalePinnedRowHiddenWhilePaging(reduceMotion = true)

    // endregion

    private fun scoreBounds(ancestor: String) = rule.onAllNodes(hasTestTag("fst.score") and hasAnyAncestor(hasTestTag(ancestor)), useUnmergedTree = true)
        .fetchSemanticsNodes().single().boundsInRoot

    @Test
    fun songLeaderboardRowsOpenPlayers() {
        launch("songLeaderboard:s-alpha:Solo_Guitar")
        waitForDescription("Page 1 of 3")
        val row = "fst.song-leaderboard.row.${Fixtures.ACCOUNT_A.dropLast(2)}10"
        waitForTag(row)
        click(row)
        rule.waitUntil(10_000) { settle(100); !exists("fst.song-leaderboard.list") }
    }

    // region Song leaderboard states (issue #104)

    private fun clickLabel(tag: String) = node(tag).fetchSemanticsNode().config.getOrNull(SemanticsActions.OnClick)?.label

    @Test
    fun songLeaderboardInstrumentSwitcherIsA48dpDropDownThatChecksTheCurrentChart() {
        launch("songLeaderboard:s-alpha:Solo_Guitar")
        waitForTag("fst.song-leaderboard.instrument")
        val switcher = node("fst.song-leaderboard.instrument").fetchSemanticsNode()
        assertEquals(Role.DropdownList, switcher.config.getOrNull(SemanticsProperties.Role))
        assertEquals("Switch instrument", switcher.config.getOrNull(SemanticsActions.OnClick)?.label)
        assertTrue(with(rule.density) { switcher.size.height.toDp() } >= 48.dp)
        click("fst.song-leaderboard.instrument")
        waitForTag("fst.song-leaderboard.instrument.Solo_Bass")
        assertEquals(true, node("fst.song-leaderboard.instrument.Solo_Guitar").fetchSemanticsNode().config.getOrNull(SemanticsProperties.Selected))
        assertEquals(false, node("fst.song-leaderboard.instrument.Solo_Bass").fetchSemanticsNode().config.getOrNull(SemanticsProperties.Selected))
    }

    @Test
    fun songLeaderboardWithOneChartShowsThePlainInstrument() {
        // s-gamma only charts drums: the instrument is text, not a disabled control.
        launch("songLeaderboard:s-gamma:Solo_Drums")
        waitForTag("fst.song-leaderboard.instrument")
        waitForDescription("Page 1 of 3")
        assertFalse(isClickable("fst.song-leaderboard.instrument"))
        assertEquals(null, node("fst.song-leaderboard.instrument").fetchSemanticsNode().config.getOrNull(SemanticsProperties.Role))
    }

    @Test
    fun songLeaderboardSelectedRowOpensStatisticsAndOthersOpenProfiles() {
        val mine = "${Fixtures.ACCOUNT_A.dropLast(2)}12"
        launch("songLeaderboard:s-alpha:Solo_Guitar", SelectedPlayer(mine, "Synthetic Player 3"))
        waitForTag("fst.song-leaderboard.row.$mine")
        assertEquals("Open your statistics", clickLabel("fst.song-leaderboard.row.$mine"))
        assertEquals("Open profile", clickLabel("fst.song-leaderboard.row.${Fixtures.ACCOUNT_A.dropLast(2)}10"))
        // No score index for this player: highlighted in place with nothing pinned.
        assertFalse(exists("fst.song-leaderboard.spotlight-footer"))
    }

    /** Ranks [RankingsFixtures.SELECTED] 30th (page 2) on the Guitar board and in its score index. */
    private fun selectedThirtieth() {
        transport.on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
            ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", rank = 30, total = 60)))
        }
        transport.on("/api/leaderboard/s-alpha/Solo_Guitar", headers = mapOf("X-FST-Publication-Id" to "7")) { request ->
            val offset = Regex("offset=(\\d+)").find(request.url)?.groupValues?.get(1)?.toInt() ?: 0
            val board = Fixtures.leaderboard("s-alpha", rows = minOf(25, 60 - offset), total = 60, startRank = offset + 1)
            if (offset == 25) board.replace("\"accountId\":\"${Fixtures.ACCOUNT_A.dropLast(2)}14\"", "\"accountId\":\"${RankingsFixtures.SELECTED}\"") else board
        }
    }

    /** Whether a row sits wholly between the list's top and the pinned footer/pager. */
    private fun inView(tag: String): Boolean {
        val row = node(tag).fetchSemanticsNode().boundsInRoot
        return row.top >= node("fst.song-leaderboard.list").fetchSemanticsNode().boundsInRoot.top &&
            row.bottom <= node("fst.song-leaderboard.bottom-bar").fetchSemanticsNode().boundsInRoot.top
    }

    @Test
    fun songLeaderboardPinnedFooterJumpsToThePlayersPageThenOpensStatistics() {
        selectedThirtieth()
        launch("songLeaderboard:s-alpha:Solo_Guitar", selected)
        waitForDescription("Page 1 of 3")
        waitForTag(footerTag)
        // Leaderboard-row R7 (issue #307): off this page, the pinned row jumps to its page.
        assertEquals("Jump to your position", clickLabel(footerTag))
        click(footerTag)
        waitForDescription("Page 2 of 3")
        val row = "fst.song-leaderboard.row.${RankingsFixtures.SELECTED}"
        waitForTag(row)
        rule.waitUntil(10_000) { settle(100); inView(row) }
        assertEquals("Open your statistics", clickLabel(row))
        // Now on screen, the pinned copy opens Statistics like the row itself.
        assertEquals("Open your statistics", clickLabel(footerTag))
        click(footerTag)
        rule.waitUntil(10_000) { settle(100); !exists("fst.song-leaderboard.list") }
    }

    @Test
    fun songLeaderboardOpenedForThePlayerRevealsTheirRow() {
        selectedThirtieth()
        launch("songLeaderboard:s-alpha:Solo_Guitar:2:reveal", selected)
        waitForDescription("Page 2 of 3")
        val row = "fst.song-leaderboard.row.${RankingsFixtures.SELECTED}"
        waitForTag(row)
        rule.waitUntil(10_000) { settle(100); inView(row) }
        assertEquals("Open your statistics", clickLabel(footerTag))
    }

    @Test
    fun songLeaderboardAnonymousRowsAreReadButNotInteractive() {
        transport.on("/api/leaderboard/s-alpha/Solo_Guitar", headers = mapOf("X-FST-Publication-Id" to "7")) {
            Fixtures.leaderboard("s-alpha", rows = 2, total = 2).replaceFirst("\"accountId\":\"${Fixtures.ACCOUNT_A.dropLast(2)}10\"", "\"accountId\":\"\"")
        }
        launch("songLeaderboard:s-alpha:Solo_Guitar")
        waitForTag("fst.song-leaderboard.row.rank-1")
        assertFalse(isClickable("fst.song-leaderboard.row.rank-1"))
        assertEquals("Profile unavailable", node("fst.song-leaderboard.row.rank-1").fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription))
        assertTrue(isClickable("fst.song-leaderboard.row.${Fixtures.ACCOUNT_A.dropLast(2)}11"))
    }

    @Test
    fun songLeaderboardShowsAnEmptyBoard() {
        transport.on("/api/leaderboard/s-alpha/Solo_Guitar", headers = mapOf("X-FST-Publication-Id" to "7")) {
            Fixtures.leaderboard("s-alpha", rows = 0, total = 0)
        }
        launch("songLeaderboard:s-alpha:Solo_Guitar")
        waitForText("No scores yet")
        assertFalse(exists("fst.song-leaderboard.loading"))
        assertFalse(isEnabled("fst.song-leaderboard.page-next"))
    }

    @Test
    fun songLeaderboardFailureOffersRetry() {
        var fail = true
        transport.onRaw("/api/leaderboard/s-alpha/Solo_Guitar") { _ ->
            if (fail) HttpResult(500, "{}".toByteArray())
            else HttpResult(200, Fixtures.leaderboard("s-alpha", rows = 25, total = 60).toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
        }
        launch("songLeaderboard:s-alpha:Solo_Guitar")
        waitForText("Leaderboard unavailable")
        assertFalse(exists("fst.song-leaderboard.list"))
        fail = false
        click("fst.service-status.retry")
        waitForDescription("Page 1 of 3")
        assertFalse(exists("fst.service-status.retry"))
    }

    @Test
    fun songLeaderboardCorrectsAnOutOfRangePageAndDisablesBoundaryButtons() {
        launch("songLeaderboard:s-alpha:Solo_Guitar:9")
        waitForDescription("Page 3 of 3")
        assertFalse(isEnabled("fst.song-leaderboard.page-next"))
        assertFalse(isEnabled("fst.song-leaderboard.page-last"))
        assertTrue(isEnabled("fst.song-leaderboard.page-first"))
        click("fst.song-leaderboard.page-first")
        waitForDescription("Page 1 of 3")
        assertFalse(isEnabled("fst.song-leaderboard.page-first"))
        assertFalse(isEnabled("fst.song-leaderboard.page-previous"))
        assertTrue(isEnabled("fst.song-leaderboard.page-next"))
    }

    private fun isEnabled(tag: String) = node(tag).fetchSemanticsNode().config.getOrNull(SemanticsProperties.Disabled) == null

    // endregion
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w240dp-h800dp-mdpi")
class FullRankingsNarrowUiTest : LeaderboardsHarness() {
    /**
     * Issue #115: in a pane too narrow for the name beside the other columns (the rows pane
     * beside a half-open fold's hinge), rows stack rather than squeeze the name to nothing.
     */
    @Test
    fun narrowRowsStackSoNamesStayReadable() {
        launch("fullRankings:Solo_Guitar")
        waitForDescription("Page 1 of 3")
        val tag = "fst.rankings.row.${RankingsFixtures.accountId(1)}"
        waitForTag(tag)
        rule.waitUntil(5_000) { settle(100); with(rule.density) { node(tag).fetchSemanticsNode().size.height.toDp() } > 64.dp }
        assertEquals("#1. Synthetic Player 1. 49,999,000. 199 / 250 songs.", description(tag))
    }
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1600dp-h900dp-mdpi")
class FullRankingsDesktopUiTest : LeaderboardsHarness() {
    /** Issue #115: like the web page container, the board stops at 1100 dp and centres. */
    @Test
    fun desktopBoardIsCappedAndCentred() {
        launch("fullRankings:Solo_Drums")
        waitForDescription("Page 1 of 3")
        val list = node("fst.full-rankings.list").fetchSemanticsNode().boundsInRoot
        val width = with(rule.density) { list.width.toDp() }
        assertEquals(1100f, width.value, 1f)
        val root = rule.onRoot().fetchSemanticsNode().boundsInRoot
        assertTrue("right margin ${root.right - list.right}", root.right - list.right > with(rule.density) { 100.dp.toPx() })
        // The pager stays centred under the board.
        val pager = node("fst.full-rankings.pager").fetchSemanticsNode().boundsInRoot
        assertEquals(list.center.x, pager.center.x, with(rule.density) { 2.dp.toPx() })
    }

    /** Issue #149: the pinned "your rank" row spans the capped board, lining up with its rows. */
    @Test
    fun desktopPinnedRankSpansTheBoard() {
        launch("fullRankings:Solo_Guitar", selected)
        waitForTag("fst.full-rankings.spotlight-footer")
        val tag = "fst.rankings.row.${RankingsFixtures.accountId(1)}"
        waitForTag(tag)
        val row = node(tag).fetchSemanticsNode().boundsInRoot
        val footer = node("fst.full-rankings.spotlight-footer").fetchSemanticsNode().boundsInRoot
        assertEquals(row.left, footer.left, 0.5f)
        assertEquals(row.right, footer.right, 0.5f)
    }
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class FullRankingsTitleIconUiTest : LeaderboardsHarness() {
    private fun bounds(tag: String) = node(tag).fetchSemanticsNode().boundsInRoot

    /** Asserts the chart icon sits in the top app bar, left of the title and centred on it, never taller than it. */
    private fun assertTitleIcon(wireId: String) {
        val tag = "fst.full-rankings.title-icon.$wireId"
        waitForTag(tag)
        rule.onNode(hasTestTag(tag) and hasAnyAncestor(hasTestTag("fst.nav.top-bar")), useUnmergedTree = true).assertExists()
        // Decorative: the title already names the chart, so TalkBack reads it once.
        assertEquals(null, description(tag))
        val icon = bounds(tag)
        val title = bounds("fst.nav.title")
        val tolerance = with(rule.density) { 2.dp.toPx() }
        assertTrue("icon ${icon.right} before title ${title.left}", icon.right <= title.left)
        assertTrue("icon ${icon.height} within title ${title.height}", icon.height <= title.height + tolerance)
        assertEquals(title.center.y, icon.center.y, tolerance)
    }

    /** Issue #294: the instrument's icon leads the title and follows the instrument picker. */
    @Test
    fun titleLeadsWithTheInstrumentIcon() {
        launch("fullRankings:Solo_Guitar")
        waitForText("Lead Leaderboards")
        assertTitleIcon("Solo_Guitar")
        // The title's line (M3 Title Large, 28 sp) at font scale 1.0.
        assertEquals(bounds("fst.nav.title").height, bounds("fst.full-rankings.title-icon.Solo_Guitar").height, with(rule.density) { 1.dp.toPx() })
        assertEquals(28f, with(rule.density) { bounds("fst.full-rankings.title-icon.Solo_Guitar").height.toDp() }.value, 1f)
        click("fst.full-rankings.instrument-menu")
        click("fst.full-rankings.instrument-menu.1")
        waitForText("Bass Leaderboards")
        assertTitleIcon("Solo_Bass")
        assertFalse(exists("fst.full-rankings.title-icon.Solo_Guitar"))
    }

    /** Issue #294: at font scale 2.0 the icon grows with the title instead of staying 28 dp. */
    @Test
    @Config(fontScale = 2f)
    fun titleIconScalesWithTheFont() {
        launch("fullRankings:Solo_Guitar")
        waitForText("Lead Leaderboards")
        assertTitleIcon("Solo_Guitar")
        assertTrue(with(rule.density) { bounds("fst.full-rankings.title-icon.Solo_Guitar").height.toDp() } > 36.dp)
    }
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-xhdpi")
class LeaderboardsExpandedUiTest : LeaderboardsHarness() {
    @Test
    fun expandedOverviewUsesAGrid() {
        launch("leaderboards")
        waitForTag("fst.leaderboards.card.Solo_Bass")
        val lead = node("fst.leaderboards.card.Solo_Guitar").fetchSemanticsNode().boundsInRoot
        val bass = node("fst.leaderboards.card.Solo_Bass").fetchSemanticsNode().boundsInRoot
        assertEquals(lead.top, bass.top, 1f)
        assertTrue(bass.left > lead.right)
    }

    @Test
    fun expandedBoardsKeepThePagerAnchoredAndPickersInTheTopBar() {
        launch("fullRankings:Solo_Drums")
        waitForDescription("Page 1 of 3")
        assertTrue(exists("fst.full-rankings.bottom-bar"))
        assertFalse(exists("fst.full-rankings.supporting-pane"))
        val bar = node("fst.nav.top-bar").fetchSemanticsNode().boundsInRoot
        val picker = node("fst.full-rankings.instrument-menu").fetchSemanticsNode().boundsInRoot
        assertTrue(picker.top >= bar.top && picker.bottom <= bar.bottom)
    }

    @Test
    fun expandedSongLeaderboardShowsStarImages() {
        launch("songLeaderboard:s-alpha:Solo_Guitar")
        waitForDescription("Page 1 of 3")
        rule.waitUntil(10_000) { settle(100); exists("fst.stars") }
    }

    /**
     * Issue #149: on a wide window the pinned score row spans the rows' card, so its season,
     * score, accuracy and stars columns sit under the rows' (the footer used to stop at 720 dp,
     * centred, while the rows filled the window).
     */
    @Test
    fun expandedSongLeaderboardPinnedRowLinesUpWithTheRows() {
        transport.on("/api/player/${RankingsFixtures.SELECTED}", headers = mapOf("X-FST-Publication-Id" to "7")) {
            ProfileFixtures.profile(RankingsFixtures.SELECTED, "Selected Player", listOf(ProfileFixtures.score("s-alpha", "01", rank = 30, total = 60)))
        }
        launch("songLeaderboard:s-alpha:Solo_Guitar", selected)
        waitForTag("fst.song-leaderboard.spotlight-footer")
        rule.waitUntil(10_000) { settle(100); exists("fst.stars") }
        val rowTag = SemanticsMatcher("score row") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.song-leaderboard.row.") == true }
        // The pinned row's own box carries the spotlight tag (`SelectedScoreFooterRow`).
        val footer = rule.onAllNodesWithTag("fst.song-leaderboard.spotlight-footer", useUnmergedTree = true)
            .fetchSemanticsNodes().single().boundsInRoot
        val row = rule.onAllNodes(rowTag and hasAnyAncestor(hasTestTag("fst.song-leaderboard.list")), useUnmergedTree = true)
            .fetchSemanticsNodes().map { it.boundsInRoot }.first { it.width > 0f }
        assertTrue("the board is wider than the old 720 dp footer cap", with(rule.density) { row.width.toDp() } > 900.dp)
        assertEquals(row.left, footer.left, 0.5f)
        assertEquals(row.right, footer.right, 0.5f)
        val footerScore = rule.onAllNodes(hasTestTag("fst.score") and hasAnyAncestor(hasTestTag("fst.song-leaderboard.spotlight-footer")), useUnmergedTree = true)
            .fetchSemanticsNodes().single().boundsInRoot
        val rowScores = rule.onAllNodes(hasTestTag("fst.score") and hasAnyAncestor(hasTestTag("fst.song-leaderboard.list")), useUnmergedTree = true)
            .fetchSemanticsNodes().map { it.boundsInRoot }.filter { it.width > 0f }
        assertTrue(rowScores.size > 1)
        for (bounds in rowScores) assertEquals(footerScore.right, bounds.right, 0.5f)
        // The pager keeps its own width, centred under the board.
        val pager = node("fst.song-leaderboard.pager").fetchSemanticsNode().boundsInRoot
        assertTrue(pager.width < row.width)
        assertEquals(row.center.x, pager.center.x, with(rule.density) { 2.dp.toPx() })
    }
}

/** How far into a row's `fadeInUp` entrance (400 ms) the reveal tests probe the drift. */
private const val FADE_PROBE_MS = 120L
