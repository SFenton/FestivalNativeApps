package com.festivalscoretracker.android.journeys

import android.graphics.Color
import android.graphics.Rect
import android.os.Build
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.firstrun.FirstRunMode
import com.festivalscoretracker.android.core.firstrun.FirstRunSeenStore
import com.festivalscoretracker.android.core.settings.MemoryBlobStore
import com.festivalscoretracker.android.core.whatsnew.Changelog
import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenStore
import com.festivalscoretracker.android.core.whatsnew.InstallChannel
import com.festivalscoretracker.android.core.whatsnew.WhatsNewMode
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCenter
import com.festivalscoretracker.android.presentation.whatsnew.WhatsNewController
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.whatsnew.WhatsNewHost
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * What's New **install-channel notes grouped by category** on a device (issue #80; accessibility
 * backfill #434), at the device's text size and at 200% system text, with ATF on every step. The
 * real [WhatsNewHost] presents a two-version changelog:
 *
 * - **Tester** installs read the sheet title, Close, the "Changes Since Release 2610.01.03"
 *   heading, then each category heading (Songs, Item Shop, Other) followed by its own bullets,
 *   the older "Version 2610.01.03" heading and its bullet, then Dismiss; the release block of the
 *   built version is not shown.
 * - **Store** installs read "Version 2610.02.02" with its Songs and Item Shop headings and never
 *   the tester-only notes.
 *
 * Block and category headings carry the heading role for TalkBack; a version without categories
 * gets no "Other" heading; the decorative "•" is never read; Close and Dismiss are 48 dp targets;
 * at 200% the headings and bullets lay out at 2× without clipping or ellipsis and Dismiss stays
 * on screen. Run with
 * `device.py test com.festivalscoretracker.android.journeys.WhatsNewGroupsAccessibilityJourneyTest --avd …`;
 * reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
class WhatsNewGroupsAccessibilityJourneyTest {
    /** The sheet composes in its own window, so only the system font scale reaches it. */
    @get:Rule(order = 0)
    val fontScale = SystemFontScaleRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Fixture

    /** Expected tester-channel reading sequence inside the list (headings and bullets). */
    private val testerSequence = listOf(
        Stop(TESTER_TITLE, heading = true),
        Stop("Songs", heading = true),
        Stop(SONGS_FIRST),
        Stop(SONGS_SECOND),
        Stop("Item Shop", heading = true),
        Stop(SHOP_NOTE),
        Stop("Other", heading = true),
        Stop(TESTER_ONLY),
        Stop(OLDER_TITLE, heading = true),
        Stop(OLDER_NOTE),
    )

    /** Expected store-channel reading sequence inside the list. */
    private val storeSequence = listOf(
        Stop(STORE_TITLE, heading = true),
        Stop("Songs", heading = true),
        Stop(SONGS_FIRST),
        Stop("Item Shop", heading = true),
        Stop(SHOP_NOTE),
        Stop(OLDER_TITLE, heading = true),
        Stop(OLDER_NOTE),
    )

    // endregion

    // region Helpers

    private val minPx get() = with(rule.density) { 48.dp.toPx() } - 1

    /**
     * Present the sheet for [channel] through the real host, as Settings → What's New does, in
     * an edge-to-edge window like `MainActivity`'s. A bare test activity consumes the status bar
     * inset, so the full-height sheet would stop only 8 dp below the window top and leave
     * Material's "Close sheet" scrim an 8 dp strip that the app never shows.
     *
     * @param channel Install channel.
     */
    private fun present(channel: InstallChannel) {
        rule.runOnUiThread {
            rule.activity.enableEdgeToEdge(
                statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
                navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            )
        }
        h.enableAccessibilityChecks()
        val entries = Changelog.decode(CHANGELOG)
        rule.setContent {
            FestivalTheme {
                val controller = remember {
                    val center = FirstRunCenter(FirstRunSeenStore(MemoryBlobStore()), FirstRunMode.Off)
                    WhatsNewController(ChangelogSeenStore(MemoryBlobStore()), center, WhatsNewMode.Off, VERSION, channel)
                }
                LaunchedEffect(controller) { controller.replay() }
                WhatsNewHost(controller, blocked = false, compact = LocalConfiguration.current.screenWidthDp < 600, entries = entries)
            }
        }
        h.waitForTag("fst.whats-new.dismiss")
        h.awaitAccessibilityTree("fst.whats-new.dismiss")
    }

    /**
     * Visible platform nodes (what TalkBack reads) matching [predicate].
     *
     * @param predicate Node filter.
     * @return Matches.
     */
    private fun accessibilityNodes(predicate: (AccessibilityNodeInfo) -> Boolean): List<AccessibilityNodeInfo> {
        val out = mutableListOf<AccessibilityNodeInfo>()
        fun walk(node: AccessibilityNodeInfo?) {
            node ?: return
            if (node.isVisibleToUser && predicate(node)) out += node
            for (i in 0 until node.childCount) walk(node.getChild(i))
        }
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) automation.clearCache()
        walk(automation.rootInActiveWindow)
        return out
    }

    /**
     * Assert a 48 × 48 dp target as TalkBack and ATF measure it (the platform node's bounds).
     *
     * @param screen Log name.
     * @param tag Test tag (exposed as the resource id).
     */
    private fun assertTarget(screen: String, tag: String) {
        var box = Rect()
        runCatching {
            rule.waitUntil(5_000) {
                box = accessibilityNodes { it.viewIdResourceName == tag }.firstOrNull()?.let { n -> Rect().also(n::getBoundsInScreen) } ?: Rect()
                box.width() >= minPx && box.height() >= minPx
            }
        }
        assertTrue("$screen: $tag is ${box.width()}x${box.height()} px, at least 48 dp", box.width() >= minPx && box.height() >= minPx)
    }

    /**
     * Index of [stop] in [order]: headings match exactly (so "Songs" never matches a bullet that
     * names Songs), bullets by their text.
     *
     * @param order Reading order.
     * @param stop Expected stop.
     * @return Index, or -1.
     */
    private fun indexOf(order: List<String>, stop: Stop): Int =
        if (stop.heading) order.indexOf(stop.text) else order.indexOfFirst { it == stop.text }

    /**
     * Read the list from top to bottom, scrolling when it overflows (200% text, short windows),
     * and assert every snapshot reads [sequence] in order between the header (title, Close) and
     * Dismiss, and that the walk visits every stop once each.
     *
     * @param screen Log name.
     * @param sequence Expected list stops.
     */
    private fun assertReadingOrder(screen: String, sequence: List<Stop>) {
        val seen = linkedSetOf<String>()
        var snapshot = 0
        while (true) {
            val order = h.readingOrder("$screen-$snapshot", fresh = true)
            val title = order.indexOfFirst { it == sheetTitle || it.startsWith("$sheetTitle,") }
            val close = order.indexOfFirst { it == "Close" || it.startsWith("Close,") }
            val dismiss = order.indexOf("Dismiss")
            assertTrue("$screen: title, Close, …, Dismiss in $order", title >= 0 && close > title && dismiss > close)
            val positions = sequence.map { indexOf(order, it) }
            val visible = positions.filter { it >= 0 }
            assertEquals("$screen: list stops in visual order in $order", visible.sorted(), visible)
            assertTrue("$screen: list stops between Close and Dismiss in $order", visible.all { it in (close + 1) until dismiss })
            assertFalse("$screen: the decorative bullet is never read in $order", order.any { it == "•" || it.startsWith("•") })
            sequence.forEachIndexed { i, stop -> if (positions[i] >= 0) seen += stop.text }
            val next = sequence.firstOrNull { it.text !in seen } ?: break
            assertTrue("$screen: could not reach \"${next.text}\" after $snapshot scrolls", snapshot < sequence.size)
            scrollListTo(next.text)
            snapshot++
        }
        assertEquals("$screen: every list stop read", sequence.map { it.text }.toSet(), seen)
    }

    /**
     * Assert [stop] is a heading in Compose semantics and on the platform node TalkBack reads.
     *
     * @param screen Log name.
     * @param stop Heading stop.
     */
    private fun assertHeading(screen: String, stop: Stop) {
        scrollListTo(stop.text)
        assertTrue("$screen: \"${stop.text}\" is a heading", SemanticsProperties.Heading in listTextNode(stop.text).config)
        val platform = accessibilityNodes { it.text?.toString() == stop.text }
        assertTrue("$screen: \"${stop.text}\" on screen for TalkBack", platform.isNotEmpty())
        assertTrue("$screen: TalkBack announces \"${stop.text}\" as a heading", platform.all { it.isHeading })
    }

    /**
     * Scroll the list until the node showing [text] is composed and on screen.
     *
     * @param text Visible text.
     */
    private fun scrollListTo(text: String) {
        rule.onNodeWithTag("fst.whats-new.list").performScrollToNode(hasText(text))
        rule.waitForIdle()
    }

    /**
     * The unmerged `Text` node in the list that shows exactly [text].
     *
     * @param text Visible text.
     * @return Its semantics node.
     */
    private fun listTextNode(text: String): SemanticsNode =
        rule.onAllNodes(hasText(text) and hasAnyAncestor(hasTestTag("fst.whats-new.list")), useUnmergedTree = true)
            .fetchSemanticsNodes().first { it.config.getOrNull(SemanticsProperties.Text)?.any { t -> t.text == text } == true }

    /**
     * Bullets are not headings, and a block without categories shows no "Other" heading.
     *
     * @param screen Log name.
     * @param sequence Expected list stops.
     */
    private fun assertBulletsAndUnheadedBlock(screen: String, sequence: List<Stop>) {
        sequence.filterNot { it.heading }.forEach { stop ->
            scrollListTo(stop.text)
            val platform = accessibilityNodes { it.text?.toString() == stop.text || it.contentDescription?.toString() == stop.text }
            assertTrue("$screen: \"${stop.text}\" read by TalkBack", platform.isNotEmpty())
            assertFalse("$screen: bullet \"${stop.text}\" is not a heading", platform.any { it.isHeading })
        }
        val olderBlock = rule.onAllNodes(hasText("Other") and hasAnyAncestor(hasTestTag("fst.whats-new.section.1")), useUnmergedTree = true)
        assertTrue("$screen: the uncategorized older version has no Other heading", olderBlock.fetchSemanticsNodes().isEmpty())
    }

    /**
     * Each list text lays out at [scale] inside its box: no line wider than the box, no paragraph
     * taller than it, nothing ellipsized.
     *
     * @param screen Log name.
     * @param sequence Expected list stops.
     * @param scale Font scale.
     */
    private fun assertTextScales(screen: String, sequence: List<Stop>, scale: Float) {
        sequence.forEach { stop ->
            scrollListTo(stop.text)
            val node = listTextNode(stop.text)
            val layouts = mutableListOf<TextLayoutResult>()
            rule.onNode(SemanticsMatcher("id ${node.id}") { it.id == node.id }, useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val layout = layouts.single()
            assertEquals("$screen: \"${stop.text}\" laid out at ${scale}x text", scale, layout.layoutInput.density.fontScale, 0.01f)
            val lines = 0 until layout.lineCount
            assertFalse("$screen: \"${stop.text}\" is wider than its box", lines.any { layout.getLineRight(it) - layout.getLineLeft(it) > layout.size.width + 1 })
            assertFalse("$screen: \"${stop.text}\" is taller than its box", layout.multiParagraph.height > layout.size.height + 1)
            assertFalse("$screen: \"${stop.text}\" is ellipsized", lines.any(layout::isLineEllipsized))
        }
    }

    /**
     * The whole check for one channel at the current font scale.
     *
     * @param screen Log name.
     * @param channel Install channel.
     * @param sequence Expected list stops.
     * @param absent Texts the channel must not show.
     * @param scale Font scale the list must lay out at.
     */
    private fun assertChannel(screen: String, channel: InstallChannel, sequence: List<Stop>, absent: List<String>, scale: Float) {
        present(channel)
        rule.onNodeWithTag("fst.whats-new.close").assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Close")))
        assertTarget(screen, "fst.whats-new.close")
        assertTarget(screen, "fst.whats-new.dismiss")
        assertReadingOrder(screen, sequence)
        sequence.filter { it.heading }.forEach { assertHeading(screen, it) }
        assertBulletsAndUnheadedBlock(screen, sequence)
        assertTextScales(screen, sequence, scale)
        absent.forEach { text ->
            assertTrue("$screen: \"$text\" is not shown", rule.onAllNodes(hasText(text, substring = true), useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        }
        // Dismiss stays reachable below the scrolled notes.
        assertTarget("$screen-end", "fst.whats-new.dismiss")
        h.readingOrder("$screen-end", fresh = true)
        h.tap("fst.whats-new.dismiss")
        h.waitGone("fst.whats-new.sheet")
        h.assertAccessible()
    }

    private val sheetTitle = "What's New · $VERSION"

    // endregion

    // region Tests

    /** Tester install, device text: the grouped tester list in order, with headings, targets and ATF. */
    @Test
    @DeviceCi
    fun testerNotesReadByCategoryWithHeadings() {
        assertChannel("whats-new-tester", InstallChannel.Tester, testerSequence, listOf(STORE_TITLE), rule.activity.resources.configuration.fontScale)
    }

    /** Store install, device text: the release's own groups only, never the tester notes. */
    @Test
    @DeviceCi
    fun storeNotesReadByCategoryWithoutTesterNotes() {
        assertChannel("whats-new-store", InstallChannel.Store, storeSequence, listOf(TESTER_TITLE, TESTER_ONLY, SONGS_SECOND), rule.activity.resources.configuration.fontScale)
    }

    /** Tester install at 200% system text: headings and bullets grow unclipped, order and targets hold. */
    @Test
    @DeviceCi
    @SystemFontScale(2f)
    fun testerNotesAtDoubleTextKeepOrderHeadingsAndTargets() {
        assertEquals(2f, rule.activity.resources.configuration.fontScale, 0.01f)
        assertChannel("whats-new-tester-2x", InstallChannel.Tester, testerSequence, listOf(STORE_TITLE), 2f)
    }

    // endregion

    /**
     * One expected stop in the list.
     *
     * @property text Visible text (word for word).
     * @property heading Whether TalkBack must announce it as a heading.
     */
    private data class Stop(val text: String, val heading: Boolean = false)

    private companion object {
        const val VERSION = "2610.02.02"
        const val TESTER_TITLE = "Changes Since Release 2610.01.03"
        const val STORE_TITLE = "Version 2610.02.02"
        const val OLDER_TITLE = "Version 2610.01.03"
        const val SONGS_FIRST = "Rows load faster when you scroll the full catalogue."
        const val SONGS_SECOND = "The A–Z index lands on the letter you tap."
        const val SHOP_NOTE = "Filter offers by New, Available or Leaving Tomorrow."
        const val TESTER_ONLY = "Tester build polish for this round."
        const val OLDER_NOTE = "The first release of Festival Score Tracker for Android."

        /** A `versioning.py whats-new` document: the built version with groups and tester notes, plus an older ungrouped release. */
        val CHANGELOG = """
            {"schema":1,"platform":"android","version":"$VERSION","entries":[
              {"version":"$VERSION","released":false,
               "items":["Songs: $SONGS_FIRST","Item Shop: $SHOP_NOTE"],
               "groups":[{"category":"Songs","items":["$SONGS_FIRST"]},{"category":"Item Shop","items":["$SHOP_NOTE"]}],
               "testflight":{"release":"2610.01.03",
                 "groups":[{"category":"Songs","items":["$SONGS_FIRST","$SONGS_SECOND"]},
                           {"category":"Item Shop","items":["$SHOP_NOTE"]},
                           {"category":null,"items":["$TESTER_ONLY"]}]}},
              {"version":"2610.01.03","released":true,"items":["$OLDER_NOTE"]}
            ]}
        """.trimIndent()
    }
}
