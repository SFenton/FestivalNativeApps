package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Tracker issue #596 accessibility: the profile's Duos/Trios/Quads groups are each one card of
 * band rows ending in the shared purple "View All Bands (N)" (owner #596), and the rows no longer
 * carry a Duos/Trios/Quads pill. On the real accessibility tree, at 100% and 200% text:
 *
 * - every band row and View All sit inside their group's card, which is one grid item under the
 *   group heading;
 * - TalkBack reads the group heading, its band rows in order, then "View All Bands (N), Duos"
 *   (`view-all-cta` R4) before the next group's heading;
 * - a row's spoken name no longer repeats the size (the heading names it);
 * - rows and View All are 48 dp buttons, and the heading is not clipped at 200%.
 *
 * ATF (labels, 48 dp targets, contrast) runs on every step. Fixtures only (Duos has eight bands,
 * six shown; Trios is empty; Quads has two). Locally: `device.py test
 * com.festivalscoretracker.android.journeys.ProfileBandGroupsAccessibilityJourneyTest --avd FST_Phone`;
 * reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class ProfileBandGroupsAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    /** The groups read as one card each at 100% text. */
    @Test
    fun bandGroupsReadAsOneCardEndingInViewAll() = groupsJourney(1f)

    /** The same at 200% text: rows grow, the heading is unclipped and the order holds. */
    @Test
    fun bandGroupsAtDoubleTextReadAsOneCard() = groupsJourney(2f)

    /**
     * Open the synthetic player's profile, scroll through the band groups and check each as
     * TalkBack reads it.
     *
     * @param scale Font scale.
     */
    private fun groupsJourney(scale: Float) {
        val config = "${scale}x"
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            ProfileFixtures.register(this)
            BandFixtures.install(this)
            on(BANDS_PATH) { request ->
                val size = Regex("pageSize=(\\d+)").find(request.url)!!.groupValues[1].toInt()
                when (Regex("group=(\\w+)").find(request.url)!!.groupValues[1]) {
                    "duos" -> BandFixtures.playerBands(8, 1, size, "duos")
                    "quads" -> BandFixtures.playerBands(2, 1, size, "quads", idPrefix = "q-")
                    "trios" -> BandFixtures.playerBands(0, 1, size, "trios")
                    else -> BandFixtures.playerBands(30, 1, size)
                }
            }
        }
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true), transport, fontScale = { scale })

        // Duos: heading, then the card's first row.
        h.scrollTo(GRID, duosHeader)
        h.waitForTag(duosHeader)
        rule.onNodeWithTag(duosHeader, useUnmergedTree = true).assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        h.assertTextUnclipped("profile-band-groups $config", GRID, "Duos", scale)
        DUO_ROWS.forEach { id ->
            rule.onNodeWithTag(row(id)).assert(hasAnyAncestor(hasTestTag(card("duos"))))
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            val spoken = spoken(row(id))
            assertFalse("$config: row $id still speaks its size: $spoken", spoken.contains("Duos") || spoken.contains("Band"))
        }
        h.assertTouchTarget("$config first band row", row(DUO_ROWS.first()))
        val top = h.readingStops("profile-band-groups-duos-$config", fresh = true)
        val heading = top.indexOfFirst { it.label == "Duos" && it.isHeading }
        assertTrue("$config: the Duos heading is not read: ${top.map { it.label }}", heading >= 0)
        assertEquals("$config: the first band row is not read right after Duos", row(DUO_ROWS.first()), top.getOrNull(heading + 1)?.id)

        // The card's end: the remaining rows in order, then the purple View All, before Trios.
        h.scrollTo(GRID, viewAll("duos"))
        rule.onNodeWithTag(viewAll("duos")).assert(hasAnyAncestor(hasTestTag(card("duos"))))
        h.assertTouchTarget("$config Duos View All", viewAll("duos"))
        assertEquals("View All Bands (8), Duos", spoken(viewAll("duos")))
        assertInside(config, viewAll("duos"), card("duos"))
        val end = h.readingStops("profile-band-groups-duos-end-$config", fresh = true)
        val ids = end.mapNotNull { it.id }
        val readRows = ids.filter { it.startsWith(ROW_PREFIX) }
        assertEquals("$config: Duos rows out of order: $ids", DUO_ROWS.map(::row).filter { it in readRows }, readRows.filter { !it.startsWith("${ROW_PREFIX}q-") })
        val cta = ids.indexOf(viewAll("duos"))
        assertTrue("$config: View All is not read: $ids", cta >= 0)
        assertTrue("$config: View All is not read after the last band row: $ids", ids.indexOf(row(DUO_ROWS.last())).let { it < 0 || it < cta })
        end.indexOfFirst { it.label == "Trios" && it.isHeading }.takeIf { it >= 0 }?.let { trios ->
            assertTrue("$config: Trios is read before the Duos View All: ${end.map { it.label }}", end.indexOfFirst { it.id == viewAll("duos") } < trios)
        }

        // Trios: no bands, so no card and no View All.
        h.scrollTo(GRID, "fst.player.bands.empty.trios")
        assertTrue(rule.onAllNodesWithTag(card("trios")).fetchSemanticsNodes().isEmpty())
        assertTrue(rule.onAllNodesWithTag(viewAll("trios")).fetchSemanticsNodes().isEmpty())

        // Quads: two rows, then View All like every preview card.
        h.scrollTo(GRID, viewAll("quads"))
        listOf("q-${BandFixtures.DUO_ID}", "q-band-1").forEach { rule.onNodeWithTag(row(it)).assert(hasAnyAncestor(hasTestTag(card("quads")))) }
        assertEquals("View All Bands (2), Quads", spoken(viewAll("quads")))
        h.assertTouchTarget("$config Quads View All", viewAll("quads"))
        val quads = h.readingStops("profile-band-groups-quads-$config", fresh = true).mapNotNull { it.id }
        assertTrue(
            "$config: Quads rows are not read before its View All: $quads",
            quads.indexOf(row("q-band-1")) in 0 until quads.indexOf(viewAll("quads")),
        )
        h.assertAccessible()
    }

    /** What TalkBack speaks for the merged node tagged [tag]. */
    private fun spoken(tag: String): String =
        rule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString(" ")

    /** Assert [inner] lies within [outer] on screen. */
    private fun assertInside(config: String, inner: String, outer: String) {
        val a = bounds(inner)
        val b = bounds(outer)
        assertTrue("$config: $inner $a is not inside $outer $b", a.left >= b.left - 1 && a.right <= b.right + 1 && a.bottom <= b.bottom + 1 && a.top >= b.top - 1)
    }

    /** Window bounds of the first node tagged [tag]. */
    private fun bounds(tag: String): Rect = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().first().boundsInWindow

    private fun row(id: String) = "$ROW_PREFIX$id"

    private fun card(group: String) = "fst.player.bands.card.$group"

    private fun viewAll(group: String) = "fst.player.bands.view-all.$group"

    private val duosHeader = "fst.player.bands.header.duos"

    private companion object {
        val BANDS_PATH = "/api/player/${Fixtures.ACCOUNT_A}/bands"
        const val GRID = "fst.player.available"
        const val ROW_PREFIX = "fst.player-bands.row."
        val DUO_ROWS = listOf(BandFixtures.DUO_ID, "band-1", "band-2", "band-3", "band-4", "band-5")
    }
}
