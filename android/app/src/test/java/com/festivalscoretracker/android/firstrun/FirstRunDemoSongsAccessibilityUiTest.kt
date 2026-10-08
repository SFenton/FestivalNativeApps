package com.festivalscoretracker.android.firstrun

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.firstrun.FirstRunCatalog
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.firstrun.FirstRunSlide
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCarousel
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.firstrun.FirstRunCarouselDialog
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemoCatalog
import com.festivalscoretracker.android.ui.firstrun.LocalFirstRunDemoCatalog
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Accessibility of the First Run song demos that issue #57 switched from invented titles to real
 * catalogue songs (with redacted placeholders while the catalogue loads), issue #420. The demos
 * are decorative pictures beside each slide's title and description, so whether they show
 * placeholders or real songs:
 * - TalkBack reads the same slide (no song title, artist or placeholder becomes a stop);
 * - keyboard focus (Tab) never enters the demo's rows, it moves from Close to the footer actions;
 * - at 200% text the slide text scales without truncation and Next/Done stay 48 dp targets.
 * The device ATF journey is `journeys/FirstRunDemoSongsJourneyTest`.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp")
class FirstRunDemoSongsAccessibilityUiTest {
    @get:Rule
    val rule = createComposeRule()

    /** Catalogue songs with artwork, Epic Games first like the web's `useDemoSongs`. */
    private val songs = listOf(
        Fixtures.song("demo-1", "Neon Overture", artist = "Epic Games").copy(albumArt = "one.jpg"),
        Fixtures.song("demo-2", "Crowd Surfer", artist = "Epic Games").copy(albumArt = "two.jpg"),
        Fixtures.song("demo-3", "Lighthouse Static", artist = "Harbor Kids").copy(albumArt = "three.jpg"),
        Fixtures.song("demo-4", "Velvet Circuit", artist = "Harbor Kids").copy(albumArt = "four.jpg"),
    )

    /** Every text a song demo could leak to TalkBack. */
    private val songTexts = songs.flatMap { listOf(it.title, it.artist) }.distinct()

    /** The slides whose demos read catalogue songs (still and rotating, every page). */
    private val songDemoIds = setOf(
        "songs-song-list", "songs-icons", "songs-metadata", "songs-shop-highlight", "songs-new-in-shop", "songs-leaving-tomorrow",
        "statistics-top-songs", "suggestions-category-card", "suggestions-infinite-scroll", "rivals-detail",
        "shop-overview", "shop-highlighting", "shop-new-items", "shop-leaving-tomorrow",
    )

    private val slides: List<FirstRunSlide> =
        FirstRunPageKey.entries.flatMap { FirstRunCatalog.slides(it, true) }.distinctBy { it.id }.filter { it.id in songDemoIds }

    private val loaded = FirstRunDemoCatalog(songs, artworkUrl = { null })

    private var catalog by mutableStateOf(FirstRunDemoCatalog())

    private fun show() {
        rule.mainClock.autoAdvance = false
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalFirstRunDemoCatalog provides catalog) {
                    FirstRunCarouselDialog(FirstRunCarousel(1, FirstRunPageKey.Songs, slides, isReplay = false)) { }
                }
            }
        }
        settle()
    }

    /** Advances the paused clock past the pager scroll and entrance animations (rotating demos never idle). */
    private fun settle() {
        rule.mainClock.advanceTimeBy(1_500)
        rule.waitForIdle()
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun next() {
        rule.onNodeWithTag("fst.first-run.next").performClick()
        settle()
    }

    private fun back() {
        rule.onNodeWithTag("fst.first-run.back").performClick()
        settle()
    }

    /** Every node of the whole window, merged as TalkBack sees it. */
    private fun allNodes(unmerged: Boolean): List<SemanticsNode> =
        rule.onAllNodes(SemanticsMatcher("any") { true }, useUnmergedTree = unmerged).fetchSemanticsNodes()

    private fun SemanticsNode.label(): String = listOfNotNull(
        config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(),
        config.getOrNull(SemanticsProperties.Text)?.joinToString { it.text },
        config.getOrNull(SemanticsProperties.StateDescription),
    ).filter { it.isNotBlank() }.joinToString(", ")

    /** What TalkBack can read on the slide: labelled merged nodes under the slide's container. */
    private fun spoken(slide: FirstRunSlide): List<String> =
        rule.onAllNodes(hasAnyAncestor(hasTestTag("fst.first-run.slide.${slide.id}")))
            .fetchSemanticsNodes().map { it.label() }.filter { it.isNotEmpty() }

    /**
     * The demo is one silent node as TalkBack sees it (merged tree): no label, no action, no
     * children, and no song text anywhere in the window.
     *
     * @return Song titles and artists the demo draws (unmerged tree), proving what it hides.
     */
    private fun assertDemoSilent(slide: FirstRunSlide, state: String): List<String> {
        val inDemo = hasTestTag("fst.first-run.demo") and hasAnyAncestor(hasTestTag("fst.first-run.slide.${slide.id}"))
        val demo = rule.onAllNodes(inDemo).fetchSemanticsNodes().single()
        assertEquals("${slide.id} ($state): demo has no label", "", demo.label())
        assertTrue("${slide.id} ($state): demo has no action", SemanticsActions.OnClick !in demo.config)
        assertTrue("${slide.id} ($state): demo exposes no children", demo.children.isEmpty())
        val leaked = allNodes(unmerged = false).map { it.label() }.filter { label -> songTexts.any { it in label } }
        assertTrue("${slide.id} ($state): no song text reaches accessibility services: $leaked", leaked.isEmpty())
        return rule.onAllNodes(hasAnyAncestor(inDemo), useUnmergedTree = true).fetchSemanticsNodes()
            .map { it.label() }.flatMap { label -> songTexts.filter { it in label } }.distinct()
    }

    /**
     * TalkBack reads each slide's heading then description, whether the demo shows placeholders
     * (catalogue still loading, first pass) or catalogue songs (loaded, second pass walking back).
     */
    @Test
    fun songDemosReadTheSameWhileLoadingAndOnceLoaded() {
        show()
        val whileLoading = mutableMapOf<String, List<String>>()
        slides.forEachIndexed { index, slide ->
            assertEquals("${slide.id}: placeholders draw no song", emptyList<String>(), assertDemoSilent(slide, "placeholders"))
            whileLoading[slide.id] = spoken(slide)
            if (index < slides.lastIndex) next()
        }
        catalog = loaded
        settle()
        val drewSongs = mutableListOf<String>()
        slides.indices.reversed().forEach { index ->
            val slide = slides[index]
            if (assertDemoSilent(slide, "catalogue songs").isNotEmpty()) drewSongs += slide.id
            val songsShown = spoken(slide)
            assertEquals("${slide.id}: same reading with songs as with placeholders", whileLoading[slide.id], songsShown)
            assertEquals("${slide.id}: heading, then description", listOf(slide.title, slide.description), songsShown)
            val heading = rule.onAllNodes(hasAnyAncestor(hasTestTag("fst.first-run.slide.${slide.id}")) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
                .fetchSemanticsNodes().single()
            assertEquals(slide.title, heading.label())
            if (index > 0) back()
        }
        println("FST_A11Y first-run song demos drawing catalogue songs (hidden): $drewSongs")
        assertTrue("the walk shows catalogue songs in most demos: $drewSongs", drewSongs.size >= slides.size / 2)
    }

    /** Tab from Close reaches Next without stopping on an invisible demo row or control. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun keyboardFocusSkipsTheSongDemos() {
        catalog = loaded
        show()
        slides.forEachIndexed { index, slide ->
            rule.onNodeWithTag("fst.first-run.close").performSemanticsAction(SemanticsActions.RequestFocus)
            settle()
            val stops = mutableListOf<String>()
            val target = if (index == slides.lastIndex) "fst.first-run.done" else "fst.first-run.next"
            for (step in 0 until 8) {
                rule.onNodeWithTag("fst.first-run.dialog").performKeyInput { pressKey(Key.Tab) }
                settle()
                val inDemo = rule.onAllNodes(isFocused() and hasAnyAncestor(hasTestTag("fst.first-run.demo")), useUnmergedTree = true).fetchSemanticsNodes()
                assertTrue("${slide.id}: Tab ${step + 1} after $stops focused a demo node: ${inDemo.map { it.config.getOrNull(SemanticsProperties.TestTag) }}", inDemo.isEmpty())
                val focused = rule.onAllNodes(isFocused(), useUnmergedTree = true).fetchSemanticsNodes()
                assertTrue("${slide.id}: Tab ${step + 1} after $stops left focus on no visible control", focused.isNotEmpty())
                val tag = focused.first().config.getOrNull(SemanticsProperties.TestTag) ?: focused.first().label()
                stops += tag
                if (tag == target) break
            }
            println("FST_A11Y ${slide.id} Tab order: $stops")
            assertEquals("${slide.id}: Tab reaches $target", target, stops.last())
            if (index < slides.lastIndex) next()
        }
    }

    /** At 200% text, the slide text grows untruncated beside the song demo and the actions stay 48 dp targets. */
    @Test
    @Config(qualifiers = "w411dp-h891dp", fontScale = 2f)
    fun largeTextKeepsEverySongDemoSlideReadable() {
        catalog = loaded
        show()
        val minTarget = with(rule.density) { 48.dp.toPx() } - 1f
        slides.forEachIndexed { index, slide ->
            val inSlide = hasAnyAncestor(hasTestTag("fst.first-run.slide.${slide.id}"))
            listOf(slide.title, slide.description).forEach { text ->
                val node = rule.onAllNodes(inSlide and SemanticsMatcher.expectValue(SemanticsProperties.Text, listOf(AnnotatedString(text))))
                    .fetchSemanticsNodes().single()
                val layouts = mutableListOf<TextLayoutResult>()
                node.config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
                val layout = layouts.single()
                assertEquals("${slide.id}: '$text' follows the font scale", 2f, layout.layoutInput.density.fontScale)
                assertTrue("${slide.id}: '$text' is not ellipsized", (0 until layout.lineCount).none { layout.isLineEllipsized(it) })
            }
            val action = if (index == slides.lastIndex) "fst.first-run.done" else "fst.first-run.next"
            val dialog = rule.onNodeWithTag("fst.first-run.dialog").fetchSemanticsNode().boundsInRoot
            val button = rule.onNodeWithTag(action).fetchSemanticsNode()
            assertTrue("${slide.id}: $action stays inside the dialog", button.boundsInRoot.bottom <= dialog.bottom && button.boundsInRoot.top >= dialog.top)
            assertTrue("${slide.id}: $action keeps a 48 dp target", button.touchBoundsInRoot.height >= minTarget && button.touchBoundsInRoot.width >= minTarget)
            assertTrue(exists("fst.first-run.demo"))
            assertDemoSilent(slide, "200% text")
            if (index < slides.lastIndex) next()
        }
    }
}
