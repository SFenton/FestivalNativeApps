package com.festivalscoretracker.android.ui.quicklinks

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.profile.ProfileSections
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.profile.ProfileJourney
import com.festivalscoretracker.android.ui.settings.settingsSections
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Issue #154 (Android check of #46 / iOS #6): Quick Links on the real Settings and player pages list
 * their sections top to bottom in the order the page shows them, from the compact floating-toolbar
 * sheet and the wider top-app-bar menu alike; a jump lands and the chosen item is the selected one
 * when Quick Links reopen.
 */
@RunWith(AndroidJUnit4::class)
class QuickLinksPageOrderUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val journey = ProfileJourney(rule)

    // region Helpers

    private val itemMatcher = SemanticsMatcher("Quick Links item") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(ITEM) == true }

    /** Items currently laid out in the open sheet or menu, top to bottom on screen. */
    private fun visibleItems(): List<String> = rule.onAllNodes(itemMatcher).fetchSemanticsNodes()
        .sortedBy { it.positionInRoot.y }
        .map { it.config[SemanticsProperties.TestTag].removePrefix(ITEM) }

    /**
     * Opens Quick Links and reads every item in on-screen order. The sheet's list is lazy, so it is
     * scrolled through; items keep the order in which they first appear top to bottom.
     */
    private fun openAndReadOrder(sheet: Boolean): List<String> {
        journey.tap(OPEN)
        journey.waitForTag(if (sheet) SHEET else MENU)
        val seen = visibleItems().toMutableList()
        var index = 0
        while (sheet && index < seen.size) {
            rule.onNodeWithTag(LIST).performScrollToIndex(index++)
            journey.settle()
            visibleItems().filterNot { it in seen }.forEach(seen::add)
        }
        return seen
    }

    /** The page's item index for each lazy key (its top-to-bottom order), from the list's semantics. */
    private fun pageIndex(listTag: String): (Any) -> Int = rule.onNodeWithTag(listTag).fetchSemanticsNode().config[SemanticsProperties.IndexForKey]

    private fun assertPageOrder(order: List<String>, expectedCount: Int, indexOf: (String) -> Int) {
        assertEquals("every section is listed once: $order", expectedCount, order.toSet().size)
        val indices = order.map(indexOf)
        assertTrue("every Quick Link has a page row: $order → $indices", indices.none { it < 0 })
        assertEquals("Quick Links follow the page top to bottom: $order → $indices", indices.sorted(), indices)
    }

    /** Choose [id], then reopen: the jump made it current, and it alone is selected. */
    private fun jumpAndReopen(id: String, title: String, sheet: Boolean) {
        journey.tap("$ITEM$id")
        journey.waitGone(if (sheet) SHEET else MENU)
        journey.settle()
        rule.onNodeWithTag(OPEN).assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Quick Links, current section $title")))
        rule.onNodeWithTag(OPEN).performSemanticsAction(SemanticsActions.OnClick)
        journey.waitForTag("$ITEM$id")
        val selected = rule.onAllNodes(itemMatcher).fetchSemanticsNodes()
            .filter { it.config.getOrNull(SemanticsProperties.Selected) == true }
            .map { it.config[SemanticsProperties.TestTag].removePrefix(ITEM) }
        assertEquals(listOf(id), selected)
    }

    private fun settingsOrder(sheet: Boolean) {
        val sections = settingsSections(debug = true)
        journey.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true))
        journey.waitForTag("fst.settings.list")
        journey.waitForTag(OPEN)
        val order = openAndReadOrder(sheet)
        val index = pageIndex("fst.settings.list")
        assertPageOrder(order, sections.size) { index(it) }
        jumpAndReopen("licenses", "Licenses", sheet)
    }

    private fun profileOrder(sheet: Boolean) {
        journey.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true))
        journey.waitForTag("fst.player.available")
        journey.waitForTag(OPEN)
        val index = pageIndex("fst.player.available")
        val order = openAndReadOrder(sheet)
        assertTrue("global first and bands last: $order", order.first() == "global" && order.last() == "bands")
        assertTrue("one link per visible chart: $order", order.count { it.startsWith("instrument:") } >= 2)
        assertPageOrder(order, order.size) { index(ProfileSections.rowKey(it)) }
        jumpAndReopen("top-songs", "Top Songs", sheet)
    }

    // endregion

    /** Compact window: the floating toolbar's Quick Links open a sheet in Settings page order. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun settingsSheetFollowsThePage() = settingsOrder(sheet = true)

    /** Wide window: the top app bar's Quick Links menu lists Settings in the same page order. */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-mdpi")
    fun settingsMenuFollowsThePage() = settingsOrder(sheet = false)

    /** Phone landscape (medium/expanded width, short height): the top-bar menu keeps page order. */
    @Test
    @Config(qualifiers = "w891dp-h411dp-xxhdpi")
    fun settingsLandscapeMenuFollowsThePage() = settingsOrder(sheet = false)

    /** Compact window: the player page's sheet lists Global, each chart, Top Songs, Bands in page order. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun profileSheetFollowsThePage() = profileOrder(sheet = true)

    /** Wide window: the player page's menu matches its multi-column grid order. */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-mdpi")
    fun profileMenuFollowsThePage() = profileOrder(sheet = false)

    /** Phone landscape: the player page's top-bar menu (scrollable on a short window) keeps page order. */
    @Test
    @Config(qualifiers = "w891dp-h411dp-xxhdpi")
    fun profileLandscapeMenuFollowsThePage() = profileOrder(sheet = false)

    private companion object {
        const val OPEN = "fst.quick-links.open"
        const val SHEET = "fst.quick-links.sheet"
        const val MENU = "fst.quick-links.menu"
        const val LIST = "fst.quick-links.list"
        const val ITEM = "fst.quick-links.item."
    }
}
