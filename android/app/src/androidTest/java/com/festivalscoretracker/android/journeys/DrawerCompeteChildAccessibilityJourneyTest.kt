package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasContentDescriptionExactly
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.CompeteFixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #610 accessibility: on a phone, the drawer's Rivals and Leaderboards open as children
 * of the Compete tab. TalkBack must hear the Compete tab as the selected bar destination (not
 * the tab the drawer was opened from), the page's Back as a labelled 48 dp button read before
 * the page content, and system Back must land on Compete's root with Compete still selected.
 * ATF runs on every step. Compact windows only (regular widths show Rivals and Leaderboards as
 * tabs and are unchanged). Fixtures only; `@DeviceCi` puts it in the `android-device` job.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class DrawerCompeteChildAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = CompeteFixtures.transport()
    private val player = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player")

    /**
     * Open [row] from the drawer on the current tab root and check the page shows under Compete.
     *
     * @param row Drawer row tag.
     * @param page Tag that proves the page is up.
     * @param left Tab the drawer was opened from, which must no longer be selected.
     * @param absent Tag of the page left, gone from TalkBack's tree.
     * @param screen Reading-order log name.
     */
    private fun openUnderCompete(row: String, page: String, left: String, absent: String, screen: String) {
        h.tap("fst.nav.drawer")
        h.waitForTag(row)
        h.tap(row)
        h.waitForTag(page)
        h.waitGone(absent)
        h.awaitAccessibilityTree(present = page, absent = absent)
        rule.onNodeWithTag(COMPETE_TAB).assertIsSelected().assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab))
        rule.onNodeWithTag(left).assertIsNotSelected()
        rule.onNodeWithTag(BACK).assert(hasContentDescriptionExactly("Back"))
        h.assertFullTouchTarget(BACK)
        val order = h.readingOrder(screen, fresh = true)
        val back = order.indexOf("Back")
        assertTrue("TalkBack does not read Back first on $screen: $order", back in 0..1)
    }

    /** System Back from the child returns to Compete's root, Compete still the selected tab. */
    private fun backToCompete(from: String, screen: String) {
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.waitForIdle()
        h.waitGone(from)
        h.waitForTag(COMPETE_GRID)
        h.awaitAccessibilityTree(present = COMPETE_GRID, absent = from)
        rule.onNodeWithTag(COMPETE_TAB).assertIsSelected()
        assertTrue("Compete's root shows Back after returning from $from", !h.exists(BACK))
        h.readingOrder(screen, fresh = true)
    }

    @Test
    fun drawerRivalsAndLeaderboardsSelectTheCompeteTab() {
        assumeTrue("Compact windows only", rule.activity.resources.configuration.screenWidthDp < 600)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport)
        h.waitForTag("fst.songs.list")
        h.waitForTag(COMPETE_TAB)
        h.tap(SHOP_TAB)
        h.waitForTag(SHOP_PAGE)
        h.awaitAccessibilityTree(present = SHOP_PAGE, absent = "fst.songs.list")

        openUnderCompete("fst.nav.drawer.rivals", RIVALS_PAGE, left = SHOP_TAB, absent = SHOP_PAGE, screen = "drawer-rivals-under-compete")
        backToCompete(RIVALS_PAGE, "drawer-rivals-back-compete")

        openUnderCompete("fst.nav.drawer.leaderboards", LEADERBOARDS_PAGE, left = SHOP_TAB, absent = COMPETE_GRID, screen = "drawer-leaderboards-under-compete")
        backToCompete(LEADERBOARDS_PAGE, "drawer-leaderboards-back-compete")

        // The tab the drawer was opened from keeps its place.
        h.tap(SHOP_TAB)
        h.waitForTag(SHOP_PAGE)
        rule.onNodeWithTag(SHOP_TAB).assertIsSelected()
        rule.onNodeWithTag(COMPETE_TAB).assertIsNotSelected()
        h.assertAccessible()
    }

    /**
     * Regular widths are unchanged (#610 acceptance): Rivals and Leaderboards are their own
     * destinations, so opening them from the navigation selects their own row as a root page
     * with no Back, and there is no Compete destination to host them.
     */
    @Test
    fun regularWidthsKeepRivalsAndLeaderboardsAsTabs() {
        assumeTrue("Regular windows only", !compact())
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport)
        h.waitForTag("fst.songs.list")
        h.waitForTag(RIVALS_TAB)
        assertTrue("Compete is a destination at a regular width", !h.exists(COMPETE_TAB))
        for ((tab, page) in listOf(RIVALS_TAB to RIVALS_PAGE, LEADERBOARDS_TAB to LEADERBOARDS_PAGE)) {
            h.tap(tab)
            h.waitForTag(page)
            h.awaitAccessibilityTree(present = page)
            rule.onNodeWithTag(tab).assertIsSelected()
            assertTrue("$page shows Back at a regular width", !h.exists(BACK))
            h.readingOrder("regular-$page", fresh = true)
        }
        h.assertAccessible()
    }

    private fun compact(): Boolean = rule.activity.resources.configuration.screenWidthDp < 600

    private companion object {
        const val RIVALS_TAB = "fst.nav.tab.rivals"
        const val LEADERBOARDS_TAB = "fst.nav.tab.leaderboards"
        const val COMPETE_TAB = "fst.nav.tab.compete"
        const val SHOP_TAB = "fst.nav.tab.shop"
        const val SHOP_PAGE = "fst.shop.sort.open"
        const val RIVALS_PAGE = "fst.rivals.findRival"
        const val LEADERBOARDS_PAGE = "fst.leaderboards"
        const val COMPETE_GRID = "fst.compete.grid"
        const val BACK = "fst.nav.back"
    }
}
