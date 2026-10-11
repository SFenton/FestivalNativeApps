package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.text.TextLayoutResult
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.SectionIndexFixtures
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Accessibility of the Songs `#`/A–Z section titles in Title and Artist order (issue #582: the
 * owner asked whether these sections should have headers; the web, Apple and Windows title them).
 * Each title is one heading stop with its spoken label ("Numbers and symbols" for `#`), read
 * before its own rows and after the previous section's; Quick Links stay out because the section
 * index navigates; a section-index jump pins the landed title at the top of the list with its
 * first row directly beneath and read after it; at 200% text the titles grow unclipped in the
 * same order. ATF stays clean throughout. Fixture-only ([SectionIndexFixtures]);
 * `device.py test com.festivalscoretracker.android.journeys.SongsAlphaHeaderAccessibilityJourneyTest --avd FST_Phone`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class SongsAlphaHeaderAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val labels = SectionIndexFixtures.labels

    // region Helpers

    /**
     * Launch Songs in [sort] over the still artwork background and publish TalkBack's order.
     *
     * @param sort Saved sort mode (`Title` or `Artist`).
     * @param fontScale Font scale provider, or `null` for the device's.
     */
    private fun launch(sort: String, fontScale: (() -> Float)? = null) {
        val preferences = MemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to sort))
        h.launch(DebugLaunch(stillBackground = true), SectionIndexFixtures.transport(), preferences, fontScale)
        h.waitForTag("fst.songs.row.s-0-1")
        h.publishTalkBackTree()
    }

    private fun live(tag: String): SemanticsNode =
        rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().first { it.layoutInfo.isPlaced && !it.layoutInfo.isDeactivated }

    /**
     * The section titles on screen are headings with spoken labels, unclipped and not touch
     * targets; in TalkBack's order each is one stop, read before every shown row of its own
     * section and after every shown row of the section before it.
     *
     * @param screen Reading-order log name.
     * @param mode Header test-tag mode (`title` or `artist`).
     * @param sectionOfToken Section index of a header token.
     * @param sectionOfRow Section index of a fixture row (`s-<titleSection>-<n>`).
     * @return The titles' spoken descriptions (what TalkBack reads instead of the glyph) in reading order.
     */
    private fun assertTitlesLeadTheirRows(screen: String, mode: String, sectionOfToken: (String) -> Int, sectionOfRow: (Int) -> Int): List<String> {
        val prefix = "$HEADER_PREFIX$mode."
        val stops = h.readingStops(screen, fresh = true)
        val titles = stops.withIndex().filter { it.value.id?.startsWith(prefix) == true }
        assertTrue("$screen: a section title is read: ${stops.map { it.label }}", titles.isNotEmpty())
        titles.forEach { (_, stop) ->
            val tag = stop.id!!
            assertTrue("$screen: $tag is a heading", stop.isHeading)
            assertFalse("$screen: $tag is not a button", stop.isClickable)
            assertEquals("$screen: $tag is one stop", 1, stops.count { it.id == tag })
            val node = live(tag)
            val layouts = mutableListOf<TextLayoutResult>()
            node.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(layouts)
            layouts.forEach { assertFalse("$screen: $tag text is clipped", it.hasVisualOverflow) }
        }
        val titleAt = titles.associate { sectionOfToken(it.value.id!!.removePrefix(prefix)) to it.index }
        val rows = stops.withIndex().filter { it.value.id?.startsWith(ROW_PREFIX) == true }
        assertTrue("$screen: rows are read", rows.isNotEmpty())
        rows.forEach { (index, stop) ->
            val section = sectionOfRow(stop.id!!.removePrefix(ROW_PREFIX).substringBefore('-').toInt())
            titleAt[section]?.let { assertTrue("$screen: section $section's title precedes ${stop.id}: ${stops.map { it.label }}", it < index) }
            titleAt[section + 1]?.let { assertTrue("$screen: the next title follows ${stop.id}: ${stops.map { it.label }}", it > index) }
        }
        return titles.map { (_, stop) ->
            val spoken = live(stop.id!!).config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().joinToString(", ")
            assertTrue("$screen: ${stop.id} reads \"$spoken\" first: ${stop.label}", spoken.isNotEmpty() && (stop.label == spoken || stop.label.startsWith("$spoken, ")))
            spoken
        }
    }

    private fun titleSection(token: String): Int = if (token == "#") 0 else labels.indexOf(token.uppercase())

    private fun artistSection(token: String): Int = ARTIST_TOKENS.indexOf(token)

    // endregion

    // region Journeys

    /** Title order at rest: `#` and A are headings read before their rows; no Quick Links beside the index. */
    @Test
    fun titleSectionsAreHeadingsReadBeforeTheirRows() {
        h.enableAccessibilityChecks()
        launch("Title")
        h.waitForTag("${HEADER_PREFIX}title.#")
        val read = assertTitlesLeadTheirRows("songs-title-rest", "title", ::titleSection) { it }
        assertEquals("# is spoken in words: $read", "Numbers and symbols", read.first())
        assertTrue("A follows #: $read", "A" in read)
        assertFalse("the section index replaces Quick Links", h.exists("fst.quick-links.open"))
        assertTrue("the section index is shown", h.exists(RAIL))
        h.assertAccessible()
    }

    /** A section-index jump to M pins M's title at the list top, its first row beneath it and read after it. */
    @Test
    fun indexJumpPinsTheTitleAboveItsFirstRow() {
        h.enableAccessibilityChecks()
        launch("Title")
        h.waitForTag(RAIL)
        val m = labels.indexOf("M")
        rule.onNodeWithTag(RAIL).performTouchInput { click(Offset(width / 2f, height * (m + 0.5f) / labels.size)) }
        val tag = "${HEADER_PREFIX}title.m"
        val list = rule.onNodeWithTag(LIST).fetchSemanticsNode().boundsInRoot
        rule.waitUntil(10_000) {
            h.exists(tag) && abs(live(tag).boundsInRoot.top - list.top) <= rule.density.density * 2
        }
        val title = live(tag).boundsInRoot
        val row = live("${ROW_PREFIX}$m-1").boundsInRoot
        assertTrue("M's first row sits below its pinned title ($row vs $title)", row.top >= title.bottom - 1f)
        assertTrue("…directly below it ($row vs $title)", row.top - title.bottom <= rule.density.density * 8)
        val read = assertTitlesLeadTheirRows("songs-title-jump-m", "title", ::titleSection) { it }
        assertEquals("M is the first title read: $read", "M", read.first())
        h.assertAccessible()
    }

    /** Artist order at 200% text: A/M/Z titles grow unclipped, keep their order, and ATF stays clean. */
    @Test
    fun artistSectionsGrowUnclippedAtDoubleText() {
        h.enableAccessibilityChecks()
        launch("Artist", fontScale = { 2f })
        h.waitForTag("${HEADER_PREFIX}artist.a")
        val read = assertTitlesLeadTheirRows("songs-artist-200", "artist", ::artistSection) { it % ARTIST_TOKENS.size }
        assertEquals("A is read first: $read", "A", read.first())
        h.assertAccessible()
    }

    // endregion

    private companion object {
        const val LIST = "fst.songs.list"
        const val RAIL = "fst.songs.section-index"
        const val HEADER_PREFIX = "fst.songs.section."
        const val ROW_PREFIX = "fst.songs.row.s-"

        /** Artist sections in list order ([SectionIndexFixtures.artistOf]). */
        val ARTIST_TOKENS = listOf("a", "m", "z")
    }
}
