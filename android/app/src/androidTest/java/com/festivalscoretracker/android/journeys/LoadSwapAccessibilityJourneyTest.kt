package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import kotlinx.coroutines.CompletableDeferred
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The shared load **and reload** swap (`ui/common/LoadSwap.kt`, issue #71; accessibility backfill
 * #431) on a device, with ATF on every interaction. Each reload's fixture read is held open so the
 * spinner state can be inspected:
 * - Full Rankings page change (animations on) and Rank By change (200% text): the spinner is one
 *   TalkBack stop, "Loading rankings", exposed as indeterminate progress; no stale row stays in the
 *   accessibility tree (`load-transition` R2); the pager and Rank By stay readable, usable and at
 *   least 48 dp (R4), and the pager keeps reading the last page count ("Page 1 of 3", not a
 *   placeholder "of 1", through a Rank By switch); TalkBack reads the spinner before the pager, and the new rows before the
 *   pager once they commit. A page-only reload keeps the pinned "your score" row readable (R2, #190).
 * - The same page reload with the in-app Reduce Motion setting (R6).
 * - Band Rankings band-size change (animations on) and Rank By change (200% text): the spinner is
 *   one indeterminate "Loading band rankings" stop read before the pager, no stale band row stays
 *   in the tree, the pager keeps "Page 1 of 2" with a usable Next, the pager and both pickers stay
 *   at least 48 dp and the pickers speak their new choice; the new rows are read before the pager.
 * - Leaderboards overview Rank By change: the cards that keep loading under the spinner are silent
 *   to TalkBack (R2, #178), the spinner reads "Loading leaderboards" and Rank By its new choice.
 *
 * `device.py test com.festivalscoretracker.android.journeys.LoadSwapAccessibilityJourneyTest --avd …`
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class LoadSwapAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player")
    private val holds = CopyOnWriteArrayList<Pair<(String) -> Boolean, CompletableDeferred<Unit>>>()
    private val transport: FakeTransport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            beforeRespond = { request -> holds.firstOrNull { (matches, _) -> matches(request.url) }?.second?.await() }
        },
    )
    private val board = "fst.full-rankings"
    private val boardSpinner = "$board.loading"
    private val rowPrefix = "fst.rankings.row."
    private val bands = "fst.band-rankings"
    private val bandRowPrefix = "$bands.row."
    private var savedAnimatorScale: String? = null

    // region Helpers

    private fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            android.os.ParcelFileDescriptor.AutoCloseInputStream(fd).bufferedReader().readText().trim()
        }

    @Before
    fun saveAnimatorScale() {
        savedAnimatorScale = shell("settings get global animator_duration_scale")
    }

    @After
    fun restoreAnimatorScale() {
        holds.forEach { it.second.complete(Unit) }
        val saved = savedAnimatorScale
        shell(if (saved == null || saved == "null" || saved.isEmpty()) "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $saved")
    }

    /**
     * Hold every read whose URL matches until the returned gate completes.
     *
     * @param matches URL predicate.
     * @return Gate.
     */
    private fun hold(matches: (String) -> Boolean): CompletableDeferred<Unit> = CompletableDeferred<Unit>().also { holds += matches to it }

    /** A Full Rankings page read for [page] (any metric). */
    private fun boardPage(page: Int): (String) -> Boolean = { url ->
        url.contains("/api/rankings/Solo_Guitar?") && Regex("[?&]page=$page(&|$)").containsMatchIn(url)
    }

    private fun rowTag(rank: Int) = "$rowPrefix${RankingsFixtures.accountId(rank)}"

    /** Visible accessibility nodes whose resource id starts with [prefix]. */
    private fun visibleNodes(prefix: String): List<AccessibilityNodeInfo> {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        val out = mutableListOf<AccessibilityNodeInfo>()
        fun walk(n: AccessibilityNodeInfo?) {
            n ?: return
            if (n.viewIdResourceName?.startsWith(prefix) == true && n.isVisibleToUser) out += n
            for (i in 0 until n.childCount) walk(n.getChild(i))
        }
        walk(automation.rootInActiveWindow)
        return out
    }

    private fun screenBox(n: AccessibilityNodeInfo) = android.graphics.Rect().also(n::getBoundsInScreen)

    private fun minTargetPx() = with(rule.density) { 48.dp.toPx() } - 1

    /** Assert the control [tag] is on screen, readable, at least 48 × 48 dp and, when [enabled], usable. */
    private fun assertTarget(tag: String, enabled: Boolean = false) {
        val node = visibleNodes(tag).firstOrNull { it.viewIdResourceName == tag }
        assertTrue("$tag is not readable", node != null)
        val box = screenBox(node!!)
        assertTrue("$tag is ${box.width()}×${box.height()} px, under 48 dp", box.width() >= minTargetPx() && box.height() >= minTargetPx())
        if (enabled) assertTrue("$tag is disabled while the board loads", node.isEnabled)
    }

    /**
     * Assert the swap's spinner state: one indeterminate progress stop named [label] under [tag],
     * no node of [hidden] in the accessibility tree, and the spinner read before [after].
     *
     * @param screen Reading-order log name.
     * @param tag Spinner test tag.
     * @param label Spinner's accessible name.
     * @param hidden Resource-id prefix of stale content that must not be readable.
     * @param stale A stale node that must have left the tree.
     * @param after Reading-order label prefix that follows the spinner, or null.
     * @return The reading order.
     */
    private fun assertSpinner(screen: String, tag: String, label: String, hidden: String, stale: String, after: String?): List<String> {
        h.waitForTag(tag)
        h.awaitAccessibilityTree(present = tag, absent = stale)
        val spinner = rule.onAllNodes(hasContentDescription(label) and hasAnyAncestor(hasTestTag(tag)), useUnmergedTree = true).fetchSemanticsNodes()
        assertEquals("one \"$label\" node", 1, spinner.size)
        assertEquals("spinner is not indeterminate progress", ProgressBarRangeInfo.Indeterminate, spinner.single().config.getOrNull(SemanticsProperties.ProgressBarRangeInfo))
        val leaked = visibleNodes(hidden).filter { it.viewIdResourceName != tag }.map { it.viewIdResourceName }
        assertTrue("stale content readable under the spinner: $leaked", leaked.isEmpty())
        val order = h.readingOrder(screen, fresh = true)
        assertEquals("the spinner is not one stop in $order", 1, order.count { it.startsWith(label) })
        if (after != null) {
            val next = order.indexOfFirst { it.startsWith(after) }
            assertTrue("$after not read while loading: $order", next >= 0)
            assertTrue("spinner not read before $after: $order", order.indexOfFirst { it.startsWith(label) } < next)
        }
        return order
    }

    /**
     * Controls outside a paged board's swap stay readable, full size and usable while it reloads,
     * and the pager keeps the last page count, even through a chart, band size or Rank By switch
     * (load-transition R4; "Page 1 of 1" with a disabled Next before #431).
     *
     * @param prefix Board id prefix (`fst.full-rankings`, `fst.band-rankings`).
     * @param pages The last loaded board's page count.
     * @param menus Top-bar pickers that must stay usable.
     */
    private fun assertPagerKept(prefix: String, pages: Int, menus: List<String>) {
        assertTarget("$prefix.page-previous")
        assertTarget("$prefix.page-next", enabled = true)
        menus.forEach { assertTarget(it, enabled = true) }
        val info = visibleNodes("$prefix.page-info").first { it.viewIdResourceName == "$prefix.page-info" }
        assertTrue("pager lost its page count while loading: ${info.contentDescription}", info.contentDescription?.endsWith(" of $pages") == true)
    }

    /** Full Rankings spinner for a reload away from the shown row [staleRank]. */
    private fun assertBoardSpinner(screen: String, staleRank: Int) {
        assertSpinner(screen, boardSpinner, "Loading rankings", rowPrefix, rowTag(staleRank), after = "Page ")
        assertPagerKept(board, pages = 3, menus = listOf("fst.rankings.rank-by-menu"))
    }

    /**
     * Full Rankings settled with the row ranked [rank] on screen (row 1 on page 1; on the
     * selected player's page their row, which the reveal scrolls to): no spinner, rows read
     * before the pager.
     */
    private fun assertBoardSettled(screen: String, rank: Int) {
        h.waitForTag(rowTag(rank))
        h.waitGone(boardSpinner)
        h.awaitAccessibilityTree(present = rowTag(rank), absent = boardSpinner)
        val order = h.readingOrder(screen, fresh = true)
        assertTrue("spinner still read after the reload: $order", order.none { it.startsWith("Loading rankings") })
        val row = order.indexOfFirst { it.contains("Synthetic Player $rank.") }
        val pager = order.indexOfFirst { it.startsWith("Page ") }
        assertTrue("row $rank not read: $order", row >= 0)
        assertTrue("rows not read before the pager: $order", pager > row)
    }

    private fun populationHeight(prefix: String = board): Float = rule.onAllNodes(hasTestTag("$prefix.population"), useUnmergedTree = true).fetchSemanticsNodes().first().size.height.toFloat()

    /** Band Rankings row tag for [rank] (the fixture's rank 2 includes the selected player). */
    private fun bandRowTag(rank: Int): String {
        val first = if (rank == 2) RankingsFixtures.SELECTED else RankingsFixtures.accountId(1000 + rank)
        return "$bandRowPrefix$first:${RankingsFixtures.accountId(2000 + rank)}"
    }

    /** Band Rankings spinner for a reload away from row 1; the board has two pages (30 bands). */
    private fun assertBandSpinner(screen: String) {
        assertSpinner(screen, "$bands.loading", "Loading band rankings", bandRowPrefix, bandRowTag(1), after = "Page ")
        assertPagerKept(bands, pages = 2, menus = listOf("$bands.band-type-menu", "$bands.rank-by-menu"))
    }

    /** Band Rankings settled on page 1: no spinner, the committed rows read before the pager. */
    private fun assertBandsSettled(screen: String) {
        h.waitForTag(bandRowTag(1))
        h.waitGone("$bands.loading")
        h.awaitAccessibilityTree(present = bandRowTag(1), absent = "$bands.loading")
        val order = h.readingOrder(screen, fresh = true)
        assertTrue("spinner still read after the reload: $order", order.none { it.startsWith("Loading band rankings") })
        val row = order.indexOfFirst { it.contains("Member 1A") }
        val pager = order.indexOfFirst { it.startsWith("Page ") }
        assertTrue("band row 1 not read: $order", row >= 0)
        assertTrue("rows not read before the pager: $order", pager > row)
        assertTrue("pager count changed: $order", order[pager].startsWith("Page 1 of 2"))
    }

    /** Preferences with Experimental Ranks on, so Rank By offers more than Total Score (#541). */
    private fun experimentalRanks() = MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.EXPERIMENTAL_RANKS) to true))

    /** The top-bar picker [tag]'s spoken name. */
    private fun spoken(tag: String): String? = visibleNodes(tag).first { it.viewIdResourceName == tag }.contentDescription?.toString()

    // endregion

    /**
     * Animations on (animator duration scale 1): a page reload, then a Rank By reload at 200% text.
     */
    @Test
    fun fullRankingsReloadReadsOneSpinnerBesideUsableControls() {
        shell("settings put global animator_duration_scale 1")
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("fullRankings:Solo_Guitar"), profile = player, stillBackground = true), transport, experimentalRanks(), fontScale = { scale })
        h.waitForTag("$board.spotlight-footer")
        assertBoardSettled("full-rankings", rank = 1)
        val populationAt1 = populationHeight()

        // Page reload: rows swap to the spinner; the pinned "your score" row and pager stay readable.
        val page2 = hold(boardPage(2))
        h.tap("$board.page-next")
        assertBoardSpinner("full-rankings-page-loading", staleRank = 1)
        assertTrue("pinned score left TalkBack on a page-only reload", visibleNodes("$board.spotlight-footer").isNotEmpty())
        page2.complete(Unit)
        assertBoardSettled("full-rankings-page-2", rank = RankingsFixtures.SELECTED_RANK)
        h.tap("$board.page-previous")
        assertBoardSettled("full-rankings-page-1", rank = 1)

        // 200% text: the same contract while Rank By reloads the board.
        scale = 2f
        rule.waitForIdle()
        assertTrue("2.0× text did not apply", populationHeight() > populationAt1 * 1.5f)
        val adjusted = hold { it.contains("/api/rankings/Solo_Guitar?") && it.contains("rankBy=adjusted") }
        h.tap("fst.rankings.rank-by-menu")
        h.tap("fst.rankings.rank-by.adjusted")
        assertBoardSpinner("full-rankings-rank-by-loading-2x", staleRank = 1)
        // The picker already speaks the new choice while its board loads.
        val rankBy = visibleNodes("fst.rankings.rank-by-menu").first { it.viewIdResourceName == "fst.rankings.rank-by-menu" }
        assertEquals("Rank By, Adjusted", rankBy.contentDescription?.toString())
        adjusted.complete(Unit)
        assertBoardSettled("full-rankings-adjusted-2x", rank = 1)
        h.assertAccessible()
    }

    /** The in-app Reduce Motion setting: the same spinner contract with no fades (load-transition R6). */
    @Test
    fun fullRankingsReloadUnderReduceMotion() {
        val preferences = MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to true, booleanPreferencesKey(SettingsRegistry.EXPERIMENTAL_RANKS) to true))
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("fullRankings:Solo_Guitar"), profile = player, stillBackground = true), transport, preferences)
        h.waitForTag("$board.spotlight-footer")
        assertBoardSettled("full-rankings-reduce-motion", rank = 1)
        val page2 = hold(boardPage(2))
        h.tap("$board.page-next")
        assertBoardSpinner("full-rankings-reduce-motion-loading", staleRank = 1)
        page2.complete(Unit)
        assertBoardSettled("full-rankings-reduce-motion-page-2", rank = RankingsFixtures.SELECTED_RANK)
        h.assertAccessible()
    }

    /**
     * Band Rankings (animations on): a band-size reload, then a Rank By reload at 200% text. Its
     * pager count is the same view-model state as Full Rankings' (#431), so both switches keep
     * "Page 1 of 2" and a usable Next while the new board loads.
     */
    @Test
    fun bandRankingsReloadsReadOneSpinnerAndKeepThePageCount() {
        shell("settings put global animator_duration_scale 1")
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("bandRankings:Band_Duets"), profile = player, stillBackground = true), transport, experimentalRanks(), fontScale = { scale })
        h.waitForTag("$bands.population")
        assertBandsSettled("band-rankings")
        val populationAt1 = populationHeight(bands)

        // Band size reload: the rows swap to the spinner; the pager and both pickers stay usable.
        val trios = hold { it.contains("/api/rankings/bands/Band_Trios?") && !it.contains("rankBy=fcrate") }
        h.tap("$bands.band-type-menu")
        h.tap("$bands.band-type-menu.1")
        assertBandSpinner("band-rankings-band-size-loading")
        assertEquals("Band Size, Trios", spoken("$bands.band-type-menu"))
        trios.complete(Unit)
        assertBandsSettled("band-rankings-trios")

        // 200% text: the same contract while Rank By reloads the board.
        scale = 2f
        rule.waitForIdle()
        assertTrue("2.0× text did not apply", populationHeight(bands) > populationAt1 * 1.5f)
        val fcRate = hold { it.contains("/api/rankings/bands/Band_Trios?") && it.contains("rankBy=fcrate") }
        h.tap("$bands.rank-by-menu")
        h.tap("$bands.rank-by-menu.3")
        assertBandSpinner("band-rankings-rank-by-loading-2x")
        assertEquals("Rank By, FC Rate", spoken("$bands.rank-by-menu"))
        fcRate.complete(Unit)
        assertBandsSettled("band-rankings-fc-rate-2x")
        h.assertAccessible()
    }

    /** Leaderboards overview Rank By reload: the cards loading under the spinner stay silent. */
    @Test
    fun leaderboardsRankByReloadHidesTheLoadingCards() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = player, stillBackground = true), transport, experimentalRanks())
        h.waitForTag("fst.leaderboards.rank-history")
        h.waitGone("fst.leaderboards.loading")
        h.awaitAccessibilityTree(present = "fst.leaderboards.rank-history", absent = "fst.leaderboards.loading")
        h.readingOrder("leaderboards")

        val adjusted = hold { it.contains("/api/rankings/") && it.contains("rankBy=adjusted") }
        h.tap("fst.rankings.rank-by-menu")
        h.tap("fst.rankings.rank-by.adjusted")
        assertSpinner("leaderboards-rank-by-loading", "fst.leaderboards.loading", "Loading leaderboards", "fst.leaderboards", "fst.leaderboards.rank-history", after = null)
        assertTarget("fst.rankings.rank-by-menu")
        val rankBy = visibleNodes("fst.rankings.rank-by-menu").first { it.viewIdResourceName == "fst.rankings.rank-by-menu" }
        assertEquals("Rank By, Adjusted", rankBy.contentDescription?.toString())
        adjusted.complete(Unit)

        h.waitGone("fst.leaderboards.loading")
        h.awaitAccessibilityTree(present = "fst.leaderboards.rank-history", absent = "fst.leaderboards.loading")
        val order = h.readingOrder("leaderboards-adjusted", fresh = true)
        assertTrue("spinner still read after the reload: $order", order.none { it.startsWith("Loading leaderboards") })
        assertTrue("overview content not readable after the reload", visibleNodes("fst.leaderboards.").isNotEmpty())
        h.assertAccessible()
    }
}
