package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.rivals.RivalCategorization
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.core.service.ServiceFreezeReason
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.design.ViewAllLinkText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #95 accessibility (backfill #444): while the service refuses rival detail during a
 * publish freeze, Rival Detail and Rivalry are rebuilt from `/rivals/all` (titles from the
 * catalogue), and a rival missing from that snapshot keeps the retry page. TalkBack must read
 * the rebuilt page like a normal one: header heading → summary → category heading → its
 * "View All" → song cards, each card one 48 dp Button named by its catalogue title (never a
 * song ID), at 100% and 200% text; Rivalry's Title sort reads the cards in title order; the
 * retry page reads heading → message → a 48 dp Retry that loads the cards once the freeze
 * lifts. ATF runs on every step. Fixtures only; `@DeviceCi` puts it in the `android-device` job.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class RivalDetailFreezeAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(RivalsFixtures.PLAYER, PLAYER_NAME)
    private val rebuilt = RivalsFixtures.RIVALS[0]
    private val missing = RivalsFixtures.RIVALS[2]

    /**
     * Rivals fixtures where Lead detail for [rebuilt] and [missing] answers a freeze 503 and
     * `/rivals/all` carries only [rebuilt]'s untitled samples: Alpha Tune +2, Beta Song −5,
     * Échos +1, Delta Run +4 (rank deltas, so Closest Battles reads Échos first).
     */
    private fun frozenTransport(): FakeTransport = RivalsFixtures.transport().apply {
        // s-aaa sorts first by ID but third by title, so Title sort proves the catalogue titles were filled.
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) {
            Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null").replace("\"count\":3", "\"count\":4")
                .replace("\"songs\":[", """"songs":[{"songId":"s-aaa","title":"Delta Run","artist":"Band Four","year":2020,"difficulty":{"guitar":2}},""")
        }
        listOf(rebuilt, missing).forEach { id ->
            onRaw(detailPath(id)) { HttpResult(503, ByteArray(0), mapOf(ServiceFreezeReason.HEADER to "post-process")) }
        }
        on("/api/player/${RivalsFixtures.PLAYER}/rivals/all") {
            """{"accountId":"${RivalsFixtures.PLAYER}","songs":["s-alpha","s-beta","s-gamma","s-aaa"],"combos":[{"combo":"01","above":[""" +
                """{"accountId":"$rebuilt","displayName":"$RIVAL_NAME","direction":"above","sharedSongCount":4,"aheadCount":3,"behindCount":1,"rivalScore":1,"samples":[""" +
                """{"s":0,"i":"Solo_Guitar","ur":10,"rr":12,"us":250000,"rs":240000},""" +
                """{"s":1,"i":"Solo_Guitar","ur":20,"rr":15,"us":180000,"rs":190000},""" +
                """{"s":2,"i":"Solo_Guitar","ur":30,"rr":31,"us":120000,"rs":119000},""" +
                """{"s":3,"i":"Solo_Guitar","ur":40,"rr":44,"us":110000,"rs":100000}]}],"below":[]}]}"""
        }
    }

    private fun detailPath(id: String) = "/api/player/${RivalsFixtures.PLAYER}/rivals/Solo_Guitar/$id"

    private fun launch(transport: FakeTransport, rival: String, fontScale: () -> Float) {
        h.enableAccessibilityChecks()
        val route = RivalRoutes.detail(rival, RIVAL_NAME, RivalScopes.song(listOf(Instrument.Lead)))
        h.launch(DebugLaunch(route = route, profile = player, stillBackground = true), transport, fontScale = fontScale)
        h.publishTalkBackTree()
    }

    private fun node(tag: String): SemanticsNode = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().first()

    private fun text(node: SemanticsNode): String = node.config.getOrNull(SemanticsProperties.Text).orEmpty().joinToString("") { it.text }

    private fun description(node: SemanticsNode): String = node.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().joinToString()

    private fun minTargetPx(): Float = with(rule.density) { 48.dp.toPx() } - 1

    /**
     * Assert [node] is a Button at least 48 dp tall and wide.
     *
     * @param name What the node is, for messages.
     */
    private fun assertButtonTarget(node: SemanticsNode, name: String) {
        assertEquals("$name is not a Button", Role.Button, node.config.getOrNull(SemanticsProperties.Role))
        assertTrue("$name is ${node.size} px, under 48 dp", node.size.width >= minTargetPx() && node.size.height >= minTargetPx())
    }

    /**
     * Index of the first stop that starts with [prefix].
     *
     * @param order Reading order.
     * @param prefix Label prefix.
     * @return Index or -1.
     */
    private fun at(order: List<String>, prefix: String) = order.indexOfFirst { it.startsWith(prefix) }

    /**
     * The rebuilt Rival Detail: header, summary, Closest Battles heading, its View All and the
     * first card, read in that order, with every card named by its catalogue title.
     *
     * @param screen Reading-order log name.
     * @return The first Closest Battles card's height in pixels.
     */
    private fun assertRebuiltDetail(screen: String): Int {
        h.waitForTag(CLOSEST_CARD)
        h.awaitAccessibilityTree(present = CLOSEST_CARD)
        assertTrue("Rival Detail fell back to the retry page", !h.exists(RETRY))
        val header = text(node(TITLE))
        assertEquals("$PLAYER_NAME vs. $RIVAL_NAME", header)
        assertTrue("The header is not a heading", node(TITLE).config.contains(SemanticsProperties.Heading))
        val summary = text(node(SUMMARY))
        val closest = RivalCategorization.title("closest_battles")
        val viewAll = node(SEE_ALL_CLOSEST)
        assertEquals(ViewAllLinkText.spoken(closest), description(viewAll))
        assertButtonTarget(viewAll, "View All: $closest")

        val cards = rule.onAllNodes(cardMatcher()).fetchSemanticsNodes()
        assertTrue("No rebuilt song cards", cards.isNotEmpty())
        cards.forEach { card ->
            val label = description(card)
            assertTrue("Card \"$label\" is not named by a catalogue title", TITLES.any { label.startsWith("$it, ${Instrument.Lead.label}, ") })
            assertTrue("Card \"$label\" speaks a song ID", SONG_IDS.none { it in label })
            assertTrue("Card \"$label\" reads no ranks", "$PLAYER_NAME rank" in label && "$RIVAL_NAME rank" in label)
            assertButtonTarget(card, "Card \"$label\"")
        }

        val order = h.readingOrder(screen, fresh = true)
        val iHeader = order.indexOf(header)
        val iSummary = order.indexOf(summary)
        val iClosest = order.indexOf(closest)
        val iViewAll = order.indexOf(ViewAllLinkText.spoken(closest))
        assertTrue("TalkBack misses the header, summary, Closest Battles or its View All: $order", listOf(iHeader, iSummary, iClosest, iViewAll).all { it >= 0 })
        assertTrue("Rebuilt Rival Detail reads out of order: $order", iHeader < iSummary && iSummary < iClosest && iClosest < iViewAll)
        val iCard = at(order, "$CLOSEST_TITLE, ")
        // At 200% text the first card can sit below the fold; when shown it follows its View All.
        if (iCard >= 0) assertTrue("The first Closest Battles card is read before its View All: $order", iCard > iViewAll)
        return node(CLOSEST_CARD).size.height
    }

    private fun cardMatcher() = SemanticsMatcher("rival song card") { node ->
        node.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.rivals.song.") == true
    }

    /** Rebuilt Rival Detail reads like a normal one at 100% and 200% text; Rivalry's Title sort reads in title order. */
    @Test
    fun rebuiltDetailAndRivalryAreReadableAtEveryTextSize() {
        var scale by mutableFloatStateOf(1f)
        val transport = frozenTransport()
        launch(transport, rebuilt) { scale }
        val heights = mutableListOf<Int>()
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            heights += assertRebuiltDetail("rival-detail-freeze-${fontScale}x")
        }
        assertTrue("The detail endpoint was never refused", transport.sent(detailPath(rebuilt)).isNotEmpty())
        assertTrue("Rival Detail was not rebuilt from rivals/all", transport.sent("/api/player/${RivalsFixtures.PLAYER}/rivals/all").isNotEmpty())
        assertTrue("200% text did not grow the song card ($heights px)", heights[1] > heights[0])

        scale = 1f
        rule.waitForIdle()
        h.tap(SEE_ALL_CLOSEST)
        h.waitForTag(RIVALRY_TITLE)
        h.awaitAccessibilityTree(present = RIVALRY_TITLE, absent = TITLE)
        assertTrue("The Rivalry header is not a heading", node(RIVALRY_TITLE).config.contains(SemanticsProperties.Heading))
        h.tap(SORT)
        h.waitForTag(SORT_MENU)
        h.tap(SORT_TITLE)
        h.tap(SORT)
        h.waitForTag(SORT_MENU)
        rule.onNodeWithTag(SORT_TITLE).assertIsSelected()
        assertEquals(Role.RadioButton, node(SORT_TITLE).config.getOrNull(SemanticsProperties.Role))
        // Choosing the selected option again closes the menu and keeps Title order.
        h.tap(SORT_TITLE)
        h.waitGone(SORT_MENU)
        val order = h.readingOrder("rivalry-freeze-title-sort", fresh = true)
        val read = order.mapNotNull { label -> TITLES.firstOrNull { label.startsWith("$it, ") } }
        assertTrue("Rivalry reads fewer than two rebuilt cards: $order", read.size >= 2)
        assertEquals("Title sort reads rebuilt cards out of title order: $order", TITLES.take(read.size), read)
        h.assertAccessible()
    }

    /** A rival missing from `/rivals/all` keeps an accessible retry page; Retry loads the cards once the freeze lifts. */
    @Test
    fun missingRivalKeepsAnAccessibleRetryPage() {
        var scale by mutableFloatStateOf(1f)
        val transport = frozenTransport()
        launch(transport, missing) { scale }
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            h.waitForTag(RETRY)
            h.awaitAccessibilityTree(present = RETRY)
            val title = node(STATUS_TITLE)
            assertTrue("The retry page's title is not a heading", title.config.contains(SemanticsProperties.Heading))
            val retry = rule.onNodeWithTag(RETRY).fetchSemanticsNode()
            assertButtonTarget(retry, "Retry")
            val retryLabel = text(retry).ifEmpty { description(retry) }
            assertTrue("Retry has no label", retryLabel.isNotBlank())
            val order = h.readingOrder("rival-detail-retry-${fontScale}x", fresh = true)
            val iTitle = order.indexOf(text(title))
            val iRetry = at(order, retryLabel)
            assertTrue("TalkBack misses the retry heading or Retry: $order", iTitle >= 0 && iRetry >= 0)
            assertTrue("Retry is read before the retry heading: $order", iTitle < iRetry)
        }
        transport.on(detailPath(missing)) { RivalsFixtures.detail(missing) }
        scale = 1f
        rule.waitForIdle()
        if (h.exists(RETRY)) h.tap(RETRY)
        h.waitForTag(TITLE)
        h.waitForTag("fst.rivals.song.s-alpha.Solo_Guitar")
        h.assertAccessible()
    }

    private companion object {
        const val PLAYER_NAME = "Synthetic Player"
        const val RIVAL_NAME = "Synthetic Rival"
        const val TITLE = "fst.rival-detail.title"
        const val SUMMARY = "fst.rival-detail.summary"
        const val SEE_ALL_CLOSEST = "fst.rival-detail.see-all.closest_battles"
        const val CLOSEST_CARD = "fst.rivals.song.s-gamma.Solo_Guitar"
        const val RIVALRY_TITLE = "fst.rivalry.title"
        const val SORT = "fst.rivalry.sort"
        const val SORT_MENU = "fst.rivalry.sort.menu"
        const val SORT_TITLE = "fst.rivalry.sort.title"
        const val RETRY = "fst.service-status.retry"
        const val STATUS_TITLE = "fst.service-status.title"

        /** Catalogue titles of `s-alpha`, `s-beta`, `s-aaa`, `s-gamma`, in title order. */
        val TITLES = listOf("Alpha Tune", "Beta Song", "Delta Run", "Échos")
        val SONG_IDS = listOf("s-alpha", "s-beta", "s-aaa", "s-gamma")

        /** Closest Battles' first card: Échos, one rank apart. */
        const val CLOSEST_TITLE = "Échos"
    }
}
