package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.window.layout.FoldingFeature.Orientation
import androidx.window.layout.FoldingFeature.State
import androidx.window.testing.layout.FoldingFeature
import androidx.window.testing.layout.TestWindowLayoutInfo
import androidx.window.testing.layout.WindowLayoutInfoPublisherRule
import com.festivalscoretracker.android.core.bands.BandLayout
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #361 accessibility (backfill #488): on a book foldable, Band Detail's two panes and the
 * Player Bands card grid divide the free content area beside the rail at its midpoint when the
 * device is fully unfolded (flat), and split at the hinge only when it is half open. This
 * journey checks that each layout stays accessible in both postures, on the real
 * accessibility tree:
 *
 * - **Band Detail:** TalkBack reads the whole leading pane (title, Members, a member card, Band
 *   Summary, Band Statistics) before the trailing pane (Band Rank History, Five Best Songs), so
 *   two side-by-side panes never interleave. Flat, the panes are equal and meet at the content
 *   midpoint. Half open, each pane keeps to its side of the hinge. Every section header is a
 *   heading and Rank By is a labelled 48 dp button. Rank By shows only with Experimental Ranks
 *   on (`experimental-ranks` R1, #541), so that journey launches with the setting on; a second
 *   one keeps the default (off) and checks Rank By is absent from the page and from TalkBack
 *   while Band Statistics stays a heading clear of the hinge (#563).
 * - **Player Bands:** the subtitle and group picker are read before the cards, and the cards
 *   in visual row order. Flat, the grid is centred on the content area. Half open, the controls
 *    pane ends at the hinge and the cards start after it. The All and Duos segments are named
  *   single-choice options (radio role, All selected, Duos not) and 48 dp in every state.
 *
 * Both pages are then checked at 200% text, where they drop to one column by design
 * (`rememberSingleColumn`): text grows, headings aren't clipped and the order holds. ATF
 * (labels, 48 dp targets, contrast) finds no errors in any state.
 *
 * Postures are synthetic vertical folds at the window centre ([WindowLayoutInfoPublisherRule]),
 * so the flat case runs on the fold emulator whatever its hinge angle. The two-pane checks need
 * an expanded window (≥ [BandLayout.EXPANDED_WIDTH] dp, the unfolded Pixel 9 Pro Fold);
 * `@HalfOpenFoldJourney` runs them in `android-fold`, where `fstRequireHinge=true` makes a
 * compact window fail instead of skipping them. `@DeviceCi` runs the single-column checks on
 * the `android-device` phone. Fixtures only. Locally: `device.py test
 * com.festivalscoretracker.android.journeys.BandFoldAccessibilityJourneyTest --avd
 * FST_Book_Fold --posture half --runner-arg fstRequireHinge=true`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
@HalfOpenFoldJourney
class BandFoldAccessibilityJourneyTest {
    @get:Rule(order = 0)
    val windowInfo = WindowLayoutInfoPublisherRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val transport = BandFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    )

    // region Helpers

    private fun nodes(tag: String): List<SemanticsNode> = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes()

    private fun node(tag: String): SemanticsNode = nodes(tag).first()

    private fun bounds(tag: String): Rect = node(tag).boundsInWindow

    private fun text(node: SemanticsNode): String = node.config.getOrNull(SemanticsProperties.Text).orEmpty().joinToString("") { it.text }

    private fun description(tag: String): String =
        rule.onAllNodesWithTag(tag).fetchSemanticsNodes().first().config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().joinToString(" ")

    /** The synthetic fold's x in window pixels (window centre, where [publish] puts it). */
    private fun foldX(): Float = rule.activity.window.decorView.width / 2f

    /**
     * Whether the window is expanded, where Band Detail splits even when flat. `android-fold`
     * passes `fstRequireHinge=true`, so there a compact window fails instead of skipping the
     * two-pane checks.
     *
     * @return True on an expanded window.
     */
    private fun expanded(): Boolean {
        val wide = rule.activity.resources.configuration.screenWidthDp >= BandLayout.EXPANDED_WIDTH
        if (InstrumentationRegistry.getArguments().getString(JourneyHarness.REQUIRE_HINGE_ARG) == "true") {
            assertTrue("the fold job needs the unfolded inner display (≥ ${BandLayout.EXPANDED_WIDTH} dp)", wide)
        }
        return wide
    }

    /**
     * Publish one vertical fold at the window centre to Jetpack WindowManager and wait for [ready].
     *
     * @param state Flat (fully unfolded) or half opened (book posture).
     * @param ready The layout that posture should produce.
     */
    private fun publish(state: State, ready: () -> Boolean) {
        windowInfo.overrideWindowLayoutInfo(
            TestWindowLayoutInfo(listOf(FoldingFeature(rule.activity, state = state, orientation = Orientation.VERTICAL))),
        )
        rule.waitUntil(15_000) { ready() }
        rule.waitForIdle()
    }

    /**
     * Index of [label] in [order]: the stop itself, or a stop that adds its state after a comma.
     *
     * @param order Reading order.
     * @param label Stop label.
     * @return Index, or -1.
     */
    private fun indexOf(order: List<String>, label: String): Int = order.indexOfFirst { it == label || it.startsWith("$label, ") }

    /**
     * Assert [tag] is a heading whose text is [title].
     *
     * @param tag Test tag of the heading.
     * @param title Expected text.
     * @param config Configuration, for messages.
     */
    private fun assertHeading(tag: String, title: String, config: String) {
        val heading = node(tag)
        assertEquals("$config: $tag text", title, text(heading))
        assertTrue("$config: \"$title\" is not a heading", heading.config.contains(SemanticsProperties.Heading))
    }

    /**
     * Assert [tag] is at least 48 dp in both directions and, when [role] is given, has it.
     *
     * @param tag Test tag.
     * @param name What the node is, for messages.
     * @param role Expected role, or null to skip the role check.
     */
    private fun assertTarget(tag: String, name: String, role: Role? = null) {
        val target = node(tag)
        if (role != null) assertEquals("$name role", role, target.config.getOrNull(SemanticsProperties.Role))
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("$name is ${target.size} px, under 48 dp", target.size.width >= min && target.size.height >= min)
    }

    /**
     * Assert the Player Bands segment [tag] is an option of the single-choice picker: its
     * merged accessible name is [label], it has [Role.RadioButton], its selected state is
     * [selected] and it is at least 48 dp.
     *
     * @param tag Test tag of the segment.
     * @param label Expected accessible name.
     * @param selected Whether the segment should be the current choice.
     * @param config Configuration, for messages.
     */
    private fun assertSegment(tag: String, label: String, selected: Boolean, config: String) {
        val merged = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().first()
        assertEquals("$config: $label segment name", label, text(merged))
        assertEquals("$config: $label segment selected state", selected, merged.config.getOrNull(SemanticsProperties.Selected))
        assertTarget(tag, "$config: $label segment", Role.RadioButton)
    }

    /**
     * Assert the selected All and the unselected Duos segments keep their name, radio role,
     * state and 48 dp target.
     *
     * @param config Configuration, for messages.
     */
    private fun assertSegments(config: String) {
        assertSegment(PB_SEGMENT_ALL, "All", selected = true, config)
        assertSegment(PB_SEGMENT_DUOS, "Duos", selected = false, config)
    }

    /**
     * Assert every node with [tags] lies wholly on one side of the fold at [fold].
     *
     * @param fold Fold x in window pixels.
     * @param tags Test tags.
     */
    private fun assertOffTheHinge(fold: Float, vararg tags: String) {
        tags.forEach { tag ->
            nodes(tag).forEach { n ->
                val box = n.boundsInWindow
                assertTrue("$tag [${box.left}, ${box.right}] straddles the hinge at $fold", box.right <= fold + 1f || box.left >= fold - 1f)
            }
        }
    }

    /**
     * No text in [tag] (the node or its descendants) is cut off: each line fits the node's width,
     * the paragraph its height, and nothing is ellipsized.
     *
     * @param tag Test tag of the region.
     * @param state Configuration, for messages.
     * @return The first line's height (px) of the first text, which grows with text size.
     */
    private fun assertNoClippedText(tag: String, state: String): Float {
        val texts = rule.onAllNodes(
            (hasTestTag(tag) or hasAnyAncestor(hasTestTag(tag))) and SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult),
            useUnmergedTree = true,
        )
        val heights = mutableListOf<Float>()
        texts.fetchSemanticsNodes().indices.forEach { i ->
            val layouts = mutableListOf<TextLayoutResult>()
            texts[i].performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val label = text(texts[i].fetchSemanticsNode())
            layouts.forEach { layout ->
                val range = 0 until layout.lineCount
                assertFalse("$state: \"$label\" is wider than its box", range.any { layout.getLineRight(it) - layout.getLineLeft(it) > layout.size.width + 1 })
                assertFalse("$state: \"$label\" is taller than its box", layout.multiParagraph.height > layout.size.height + 1)
                assertFalse("$state: \"$label\" is ellipsized", range.any { layout.isLineEllipsized(it) })
                heights += layout.getLineBottom(0) - layout.getLineTop(0)
            }
        }
        assertTrue("$state: no text under $tag", heights.isNotEmpty())
        return heights.first()
    }

    // endregion

    // region Band Detail

    /** Band Detail's pane headings, leading pane first. */
    private val leadingHeadings = listOf(MEMBERS to "Members", SUMMARY to "Band Summary", STATISTICS to "Band Statistics")
    private val trailingHeadings = listOf(HISTORY to "Band Rank History", SONGS to "Five Best Songs")

    /** The duo's Band Detail route. */
    private val bandRoute get() = DebugLaunch.parseRoute("band:${BandFixtures.DUO_ID}:Band_Duets:${BandFixtures.DUO_KEY}")

    /**
     * Preferences with Settings → Experimental Ranks [on]: Band Detail offers Rank By only then
     * (`experimental-ranks` R1, #541).
     *
     * @param on Whether the setting is on.
     * @return In-memory preferences for [JourneyHarness.launch].
     */
    private fun experimentalRanks(on: Boolean) = MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.EXPERIMENTAL_RANKS) to on))

    /**
     * Band Detail's TalkBack order in the current layout: every leading-pane stop that is on
     * screen comes before every trailing-pane stop, and each pane's top stop is read.
     *
     * @param config Configuration, for messages and the log.
     * @param twoPane Whether the trailing pane is on screen beside the leading one (in one
     *   column it starts below the viewport).
     */
    private fun assertBandDetailReadsLeadingThenTrailing(config: String, twoPane: Boolean) {
        val order = h.readingOrder("band-detail-$config", fresh = true)
        val title = text(node(BAND_TITLE))
        val member = description(MEMBER)
        val leading = (listOf(title, member) + leadingHeadings.map { it.second }).map { indexOf(order, it) }.filter { it >= 0 }
        val trailing = trailingHeadings.map { indexOf(order, it.second) }.filter { it >= 0 }
        assertTrue("$config: TalkBack never reaches the title, Members or a member card: $order", listOf(title, "Members", member).all { indexOf(order, it) >= 0 })
        if (twoPane) assertTrue("$config: TalkBack never reaches Band Rank History: $order", indexOf(order, "Band Rank History") >= 0)
        if (trailing.isNotEmpty()) assertTrue("$config: the panes interleave; a trailing stop is read before the leading pane ends: $order", leading.max() < trailing.min())
        assertTrue("$config: the title is not read first: $order", indexOf(order, title) == leading.min())
    }

    /**
     * Flat: two equal panes centred on the content area beside the rail; half open: the leading
     * pane ends at the hinge and the trailing one starts after it, with no header, chart or
     * button across it. Both read leading then trailing; 200% text drops to one column.
     * Experimental Ranks is on so Rank By is on the page (#541).
     */
    @Test
    fun bandDetailPanesStayAccessibleFlatAndHalfOpen() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = bandRoute, stillBackground = true), transport, experimentalRanks(on = true), fontScale = { scale })
        h.waitForTag(MEMBERS)
        h.publishTalkBackTree()
        val wide = expanded()
        val requests = transport.requests.count { it.url.contains("/rankings/bands") }

        publish(State.FLAT) { if (wide) h.exists(LEADING) && h.exists(TRAILING) else h.exists(CONTENT) }
        h.waitForTag(HISTORY)
        h.awaitAccessibilityTree(present = MEMBERS)
        (leadingHeadings + trailingHeadings).forEach { (tag, title) -> assertHeading(tag, title, "flat") }
        assertTrue("flat: the band title is not a heading", node(BAND_TITLE).config.contains(SemanticsProperties.Heading))
        assertTarget(RANK_BY, "flat: Rank By", Role.Button)
        assertTrue("flat: Rank By has no label", description(RANK_BY).startsWith("Rank by "))
        if (wide) {
            val leading = bounds(LEADING)
            val trailing = bounds(TRAILING)
            assertEquals("flat: unequal panes $leading | $trailing", leading.width, trailing.width, 2f)
            val gap = (leading.right + trailing.left) / 2
            assertEquals("flat: the panes don't meet at the content midpoint", (leading.left + trailing.right) / 2, gap, 2f)
        } else {
            assertFalse("flat: a compact window split into panes", h.exists(LEADING))
        }
        assertBandDetailReadsLeadingThenTrailing("flat", wide)

        if (wide) {
            val fold = foldX()
            publish(State.HALF_OPENED) { h.exists(LEADING) && kotlin.math.abs(bounds(LEADING).right - fold) <= with(rule.density) { 40.dp.toPx() } }
            h.awaitAccessibilityTree(present = MEMBERS)
            assertTrue("half open: the leading pane ${bounds(LEADING)} runs past the hinge $fold", bounds(LEADING).right <= fold + 1f)
            assertTrue("half open: the trailing pane ${bounds(TRAILING)} starts before the hinge $fold", bounds(TRAILING).left >= fold - 1f)
            assertOffTheHinge(fold, BAND_TITLE, MEMBERS, MEMBER, SUMMARY, STATISTICS, RANK_BY, HISTORY, HISTORY_CHART, SONGS)
            assertTarget(RANK_BY, "half open: Rank By", Role.Button)
            assertBandDetailReadsLeadingThenTrailing("half-open", twoPane = true)

            // Unfolding reflows the same page in place (#346): equal panes again, no reload.
            publish(State.FLAT) { kotlin.math.abs(bounds(LEADING).width - bounds(TRAILING).width) <= 2f }
            assertEquals("unfolding reloaded the band", requests, transport.requests.count { it.url.contains("/rankings/bands") })
        }
        val titleAt100 = assertNoClippedText(BAND_TITLE, "flat 100%")
        assertNoClippedText(MEMBERS, "flat 100%")

        scale = 2f
        rule.waitUntil(15_000) { h.exists(CONTENT) && !h.exists(LEADING) }
        rule.waitForIdle()
        h.awaitAccessibilityTree(present = MEMBERS)
        (leadingHeadings + trailingHeadings).forEach { (tag, title) -> assertHeading(tag, title, "200%") }
        assertTarget(RANK_BY, "200%: Rank By", Role.Button)
        val titleAt200 = assertNoClippedText(BAND_TITLE, "200%")
        assertNoClippedText(MEMBERS, "200%")
        assertTrue("200% text did not grow the band title ($titleAt100 → $titleAt200 px)", titleAt200 > titleAt100)
        val order = h.readingOrder("band-detail-200", fresh = true)
        val title = text(node(BAND_TITLE))
        assertTrue("200%: the title is not read before Members: $order", indexOf(order, title) in 0 until indexOf(order, "Members"))
        h.assertAccessible()
    }

    /**
     * Experimental Ranks off (the default): Band Detail has no Rank By, on the page or in
     * TalkBack, flat and half open, and Band Statistics stays a heading clear of the hinge with
     * the panes still read leading then trailing (`experimental-ranks` R1, #541, #563).
     */
    @Test
    fun bandDetailHidesRankByWithoutExperimentalRanks() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = bandRoute, stillBackground = true), transport, experimentalRanks(on = false))
        h.waitForTag(MEMBERS)
        h.publishTalkBackTree()
        val wide = expanded()

        publish(State.FLAT) { if (wide) h.exists(LEADING) && h.exists(TRAILING) else h.exists(CONTENT) }
        h.waitForTag(HISTORY)
        h.awaitAccessibilityTree(present = MEMBERS)
        assertHeading(STATISTICS, "Band Statistics", "flat, off")
        assertFalse("flat, off: Rank By offered with Experimental Ranks off", h.exists(RANK_BY))
        val order = h.readingOrder("band-detail-ranks-off", fresh = true)
        assertTrue("flat, off: TalkBack reads Rank By with Experimental Ranks off: $order", order.none { it.startsWith("Rank by") })
        assertBandDetailReadsLeadingThenTrailing("flat-ranks-off", wide)

        if (wide) {
            val fold = foldX()
            publish(State.HALF_OPENED) { h.exists(LEADING) && kotlin.math.abs(bounds(LEADING).right - fold) <= with(rule.density) { 40.dp.toPx() } }
            h.awaitAccessibilityTree(present = MEMBERS)
            assertFalse("half open, off: Rank By offered with Experimental Ranks off", h.exists(RANK_BY))
            assertOffTheHinge(fold, BAND_TITLE, MEMBERS, MEMBER, SUMMARY, STATISTICS, HISTORY, HISTORY_CHART, SONGS)
            assertBandDetailReadsLeadingThenTrailing("half-open-ranks-off", twoPane = true)
        }
        h.assertAccessible()
    }

    // endregion

    // region Player Bands

    /** Card tag for the [index]th band in `BandFixtures.playerBands`. */
    private fun card(index: Int) = "fst.player-bands.row.${if (index == 0) BandFixtures.DUO_ID else "band-$index"}"

    /**
     * Player Bands' TalkBack order: the subtitle and group picker, then [cards] in that order.
     *
     * @param cards Card indices in visual order.
     * @param config Configuration, for messages and the log.
     */
    private fun assertPlayerBandsOrder(cards: List<Int>, config: String) {
        val order = h.readingOrder("player-bands-$config", fresh = true)
        val subtitle = indexOf(order, text(node(PB_SUBTITLE)))
        val duos = order.indexOfFirst { it.startsWith("Duos") }
        val read = cards.map { indexOf(order, description(card(it))) }
        assertTrue("$config: TalkBack misses the subtitle, the Duos segment or a card: $order", subtitle >= 0 && duos >= 0 && read.all { it >= 0 })
        assertTrue("$config: the picker isn't read between the subtitle and the cards: $order", subtitle < duos && duos < read.first())
        assertEquals("$config: cards aren't read in visual order: $order", read.sorted(), read)
    }

    /**
     * Flat: the card grid is centred on the content area (equal margins), read row by row; half
     * open: the controls pane ends at the hinge and one column of cards starts after it. Both
     * read the controls first; 200% text drops to one column.
     */
    @Test
    fun playerBandsGridStaysAccessibleFlatAndHalfOpen() {
        var scale by mutableFloatStateOf(1f)
        val player = SelectedPlayer(BandFixtures.PLAYER, "Synthetic Player")
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("playerBands:${BandFixtures.PLAYER}"), profile = player, stillBackground = true), transport, fontScale = { scale })
        h.waitForTag(card(1))
        h.publishTalkBackTree()
        val wide = expanded()

        publish(State.FLAT) { h.exists(card(1)) && !h.exists(PB_CONTROLS) }
        h.awaitAccessibilityTree(present = card(1))
        assertSegments("flat")
        assertTarget(card(0), "flat: first band card", Role.Button)
        val list = bounds(PB_LIST)
        val first = bounds(card(0))
        val second = bounds(card(1))
        if (wide) {
            assertEquals("flat: cards ${first} | ${second} don't share a row", first.top, second.top, 2f)
            // Centred on the content area beside the rail, not anchored to the fold (#361).
            assertEquals("flat: the grid isn't centred in $list", first.left - list.left, list.right - second.right, 2f)
            assertPlayerBandsOrder(listOf(0, 1, 2), "flat")
        } else {
            assertTrue("flat: a compact window shows more than one column", second.top >= first.bottom)
            assertPlayerBandsOrder(listOf(0, 1), "flat")
        }
        val subtitleAt100 = assertNoClippedText(PB_SUBTITLE, "flat 100%")

        if (wide) {
            val fold = foldX()
            publish(State.HALF_OPENED) { h.exists(PB_CONTROLS) }
            h.awaitAccessibilityTree(present = card(0))
            assertTrue("half open: the controls ${bounds(PB_CONTROLS)} run past the hinge $fold", bounds(PB_CONTROLS).right <= fold + 1f)
            assertTrue("half open: the cards ${bounds(PB_LIST)} start before the hinge $fold", bounds(PB_LIST).left >= fold - 1f)
            assertOffTheHinge(fold, PB_SUBTITLE, PB_PICKER, card(0), card(1))
            assertSegments("half open")
            assertPlayerBandsOrder(listOf(0, 1), "half-open")
            publish(State.FLAT) { !h.exists(PB_CONTROLS) }
        }

        scale = 2f
        rule.waitUntil(15_000) { h.exists(card(1)) && bounds(card(1)).top >= bounds(card(0)).bottom }
        // Unfolding keeps the first card at the top (the grid holds its first visible item by key); go back to the controls.
        rule.onNodeWithTag(PB_LIST).performScrollToNode(hasTestTag(PB_SUBTITLE))
        rule.waitForIdle()
        h.awaitAccessibilityTree(present = card(0))
        assertSegments("200%")
        assertTarget(card(0), "200%: first band card", Role.Button)
        val subtitleAt200 = assertNoClippedText(PB_SUBTITLE, "200%")
        assertTrue("200% text did not grow the subtitle ($subtitleAt100 → $subtitleAt200 px)", subtitleAt200 > subtitleAt100)
        val order = h.readingOrder("player-bands-200", fresh = true)
        val subtitle = indexOf(order, text(node(PB_SUBTITLE)))
        val firstCard = indexOf(order, description(card(0)))
        assertTrue("200%: the subtitle isn't read before the first card: $order", subtitle >= 0 && firstCard > subtitle)
        h.assertAccessible()
    }

    // endregion

    private companion object {
        const val LEADING = "fst.band.pane.leading"
        const val TRAILING = "fst.band.pane.trailing"
        const val CONTENT = "fst.band.content"
        const val BAND_TITLE = "fst.band.title"
        const val MEMBERS = "fst.band.members-section"
        const val MEMBER = "fst.band.member.${Fixtures.ACCOUNT_A}"
        const val SUMMARY = "fst.band.summary-section"
        const val STATISTICS = "fst.band.statistics-section"
        const val RANK_BY = "fst.band.rank-by"
        const val HISTORY = "fst.band.history-section"
        const val HISTORY_CHART = "fst.band.history-chart"
        const val SONGS = "fst.band.songs-section"
        const val PB_LIST = "fst.player-bands.list"
        const val PB_CONTROLS = "fst.player-bands.list.controls-pane"
        const val PB_SUBTITLE = "fst.player-bands.subtitle"
        const val PB_PICKER = "fst.player-bands.group-picker"
        const val PB_SEGMENT_ALL = "fst.player-bands.group.all"
        const val PB_SEGMENT_DUOS = "fst.player-bands.group.duos"
    }
}
