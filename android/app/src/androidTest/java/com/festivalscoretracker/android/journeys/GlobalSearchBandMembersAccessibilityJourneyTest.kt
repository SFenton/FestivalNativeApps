package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.dp
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.search.GlobalSearchTags
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #589: Global Search band results line their member names up on one edge, row to row,
 * whatever each member's instrument count or name length, at 100% and 200% text
 * (`device.py test com.festivalscoretracker.android.journeys.GlobalSearchBandMembersAccessibilityJourneyTest
 * --avd FST_Phone`). Each band result stays one TalkBack stop (its members are not read
 * separately), every result is at least 48 dp tall and the Accessibility Test Framework checks
 * run on every interaction. Synthetic fixtures only; every request is keyless.
 */
@RunWith(AndroidJUnit4::class)
class GlobalSearchBandMembersAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val lead = "0000000000000000000000000000001a"
    private val bass = "0000000000000000000000000000001b"
    private val drums = "0000000000000000000000000000001c"
    private val longName = "Synthetic.Extraordinarily.Long.Drummer.Name"
    private val allCharts = listOf("Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "Solo_PeripheralGuitar", "Solo_PeripheralBass")

    private val duoAnnouncement = "Synthetic Lead + Synthetic Bass, Duos, 12 appearances"
    private val trioAnnouncement = "Synthetic Bass + Synthetic Lead + $longName, Trios, 7 appearances"

    private val transport = FakeTransport.standard().apply {
        on("/api/bands/search") {
            BandFixtures.bandSearchPage(
                "synthetic",
                listOf(
                    BandFixtures.searchRow(
                        "band-589-duo", "$lead:$bass", "Band_Duets", 12,
                        listOf(BandFixtures.member(lead, "Synthetic Lead", allCharts), BandFixtures.member(bass, "Synthetic Bass", listOf("Solo_Bass"))),
                    ),
                    BandFixtures.searchRow(
                        "band-589-trio", "$bass:$lead:$drums", "Band_Trios", 7,
                        listOf(
                            BandFixtures.member(bass, "Synthetic Bass", listOf("Solo_Bass", "Solo_Vocals")),
                            BandFixtures.member(lead, "Synthetic Lead", listOf("Solo_Guitar")),
                            BandFixtures.member(drums, longName, listOf("Solo_Drums", "Solo_PeripheralBass", "Solo_Vocals")),
                        ),
                    ),
                ),
            )
        }
    }

    private fun open(fontScale: (() -> Float)? = null) {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(stillBackground = true), transport, fontScale = fontScale)
        h.waitForTag("fst.songs.row.s-alpha")
        h.tap(GlobalSearchTags.OPEN)
        h.waitForTag(GlobalSearchTags.HINT)
        h.tap(GlobalSearchTags.scope(SearchScope.Bands))
        rule.onNodeWithTag(GlobalSearchTags.FIELD).performTextReplacement("synthetic")
        h.waitForTag(GlobalSearchTags.RESULT_BAND)
        Espresso.closeSoftKeyboard()
        rule.waitUntil(15_000) { names().size >= 2 }
        h.awaitAccessibilityTree(GlobalSearchTags.RESULT_BAND)
    }

    private fun tagged(suffix: String) = rule.onAllNodes(
        SemanticsMatcher("band member $suffix") { node ->
            node.config.getOrNull(SemanticsProperties.TestTag)?.let { it.startsWith("fst.band-member.") && it.endsWith(suffix) } == true
        },
        useUnmergedTree = true,
    ).fetchSemanticsNodes()

    private fun names() = tagged(".name")

    /** Every member name in every visible band result starts on the same edge; returns each line's name and icon bounds. */
    private fun assertNamesAligned(): List<Pair<Rect, Rect>> {
        val names = names()
        val lefts = names.map { it.boundsInRoot.left }
        lefts.forEach { assertEquals("name lefts $lefts", lefts.first(), it, 1f) }
        val icons = tagged(".icons")
        assertEquals(names.size, icons.size)
        // A member in two bands shares its tag, so lines pair up in tree order (name, then its icons).
        return names.zip(icons) { name, icon ->
            assertEquals(name.config[SemanticsProperties.TestTag].removeSuffix(".name"), icon.config[SemanticsProperties.TestTag].removeSuffix(".icons"))
            name.boundsInRoot to icon.boundsInRoot
        }
    }

    /** Each band result is one stop, read once, and no member name is a stop of its own. */
    private fun assertOneStopPerBand(screen: String) {
        val order = h.readingOrder(screen)
        assertEquals(order.toString(), 1, order.count { it.startsWith(duoAnnouncement) })
        // At 200% the trio may sit below the fold; it is never read twice.
        assertTrue(order.toString(), order.count { it.startsWith(trioAnnouncement) } <= 1)
        listOf("Synthetic Lead", "Synthetic Bass", longName).forEach { name -> assertTrue("$name read alone in $order", order.none { it == name }) }
    }

    private fun assertTargetsAndRequests() {
        val min = with(rule.density) { 48.dp.toPx() } - 1
        rule.onAllNodesWithTag(GlobalSearchTags.RESULT_BAND).fetchSemanticsNodes().forEach {
            assertTrue("band result ${it.touchBoundsInRoot}", it.touchBoundsInRoot.height >= min)
        }
        transport.requests.forEach { request ->
            RequestGate.validateKeyless(request)
            assertTrue(request.headers.keys.none { it.lowercase().startsWith("x-fst-selected") })
        }
    }

    @Test
    fun bandMemberNamesShareOneEdgeWithIconsTrailing() {
        open()
        val lines = assertNamesAligned()
        assertEquals(5, lines.size)
        lines.forEach { (name, icons) ->
            assertTrue("name $name beside its icons $icons", name.right <= icons.left + 1 && icons.top < name.bottom && name.top < icons.bottom)
        }
        val rights = lines.map { it.second.right }
        rights.forEach { assertEquals("icon rights $rights", rights.first(), it, 1f) }
        assertOneStopPerBand("global-search-band-members")
        assertTargetsAndRequests()
        h.assertNothingStraddles(GlobalSearchTags.SURFACE, GlobalSearchTags.RESULT_BAND)
        h.assertAccessible()
    }

    @Test
    fun bandMemberNamesStayAlignedAt200Percent() {
        open(fontScale = { 2f })
        val lines = assertNamesAligned()
        lines.forEach { (name, icons) ->
            assertTrue("icons $icons under the name $name", icons.top >= name.bottom - 1)
            assertEquals("icons start under the name", name.left, icons.left, 1f)
        }
        assertOneStopPerBand("global-search-band-members-200")
        assertTargetsAndRequests()
        h.assertNothingStraddles(GlobalSearchTags.SURFACE, GlobalSearchTags.RESULT_BAND)
        h.assertAccessible()
    }
}
