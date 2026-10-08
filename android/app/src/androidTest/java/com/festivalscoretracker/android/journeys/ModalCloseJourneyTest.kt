package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.unit.dp
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.common.MODAL_CLOSE_LABEL
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Every modal's shared Close on a device (issue #146, validating #23): each sheet and dialog
 * built on `FestivalModalSheet`, `FestivalModalDialog` or the Feedback full-screen dialog
 * opens, shows one Material close icon button (spoken "Close", button role, ≥ 48 dp target)
 * at the top end of its pane and on one side of a separating hinge, passes ATF, logs its
 * TalkBack reading order (`FST_A11Y`) and dismisses on Close. Alerts keep Material's text
 * buttons. Run per AVD and posture:
 * `device.py test com.festivalscoretracker.android.journeys.ModalCloseJourneyTest --avd …`
 * (add `--posture half` on book folds).
 */
@RunWith(AndroidJUnit4::class)
class ModalCloseJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        on("/api/paths/s-alpha/Solo_Guitar/expert/data", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.pathJson }
        on("/api/player/${Fixtures.ACCOUNT_A}/notifications", headers = mapOf("X-FST-Publication-Id" to "7")) {
            """{"sourceRunId":3,"items":[
              {"eventId":1,"notificationGuid":"n-song","eventKind":"player_score_pb","songId":"s-alpha","instrument":"Solo_Guitar","newNumeric":123456,"detectedAt":"2026-09-28T11:00:00Z"}]}"""
        }
        on("/api/service-info") { """{"contractVersion":2}""" }
        on("/api/features") { """{"appManual":false,"feedback":true}""" }
        ProfileFixtures.register(this)
    }

    // region Close contract

    /**
     * Assert the shared Close of an open modal, log its reading order, then close it.
     *
     * @param screen Reading-order log name.
     * @param close Close button test tag.
     * @param pane Modal surface test tag (sheet or dialog), or `null` when it has none.
     * @param title Header title test tag, or `null` when it has none.
     */
    private fun assertCloseAndDismiss(screen: String, close: String, pane: String?, title: String? = null) {
        h.waitForTag(close)
        rule.waitForIdle()
        val button = rule.onAllNodesWithTag(close)[0]
        button.assert(hasContentDescription(MODAL_CLOSE_LABEL))
        button.assert(hasClickAction())
        button.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        val node = button.fetchSemanticsNode()
        val minTarget = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("$close target ${node.touchBoundsInRoot}", node.touchBoundsInRoot.width >= minTarget && node.touchBoundsInRoot.height >= minTarget)
        val box = node.boundsInWindow
        // A sheet's tagged surface reports its unshifted box (ModalBottomSheet applies its slide
        // offset inside the caller's modifier), so only its horizontal edges are compared.
        pane?.let { tag ->
            val surface = rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0].fetchSemanticsNode().boundsInWindow
            val endInset = with(rule.density) { 24.dp.toPx() }
            assertTrue("$close not at the end of $tag: $box in $surface", box.right <= surface.right + 1 && surface.right - box.right <= endInset)
            h.assertNothingStraddles(tag)
        }
        val headings = title?.let { listOf(rule.onAllNodesWithTag(it, useUnmergedTree = true)[0].fetchSemanticsNode()) }
            ?: rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading), useUnmergedTree = true).fetchSemanticsNodes()
        // The header title fills the row up to its actions, so the nearest heading on the row is the modal's own (not the page's behind it).
        val rowHeading = headings.filter { it.boundsInWindow.right <= box.left + 1 && it.boundsInWindow.top < box.bottom && it.boundsInWindow.bottom > box.top }
            .maxByOrNull { it.boundsInWindow.right }
        assertTrue("$close shares no header row with a heading before it: $box", rowHeading != null)
        h.assertNothingStraddles(close)
        val order = h.readingOrder(screen)
        val headingText = rowHeading!!.config.getOrElseNullable(SemanticsProperties.Text) { null }?.joinToString().orEmpty()
        val headingAt = order.indexOf(headingText)
        val closeAt = order.indexOf(MODAL_CLOSE_LABEL)
        // Material's scrim ("Close sheet"), sheet area and drag handle may precede the header.
        assertTrue("$screen: Close does not follow \"$headingText\" in the header: $order", headingAt >= 0 && closeAt - headingAt in 1..MAX_HEADER_ACTIONS + 1)
        h.tap(close)
        h.waitGone(close)
        pane?.let(h::waitGone)
    }

    // endregion

    // region Songs area

    @Test
    fun songsSortAndFilterSheetsClose() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport)
        h.waitForTag("fst.songs.list")
        h.tap("fst.songs.sort.open")
        assertCloseAndDismiss("modal-songs-sort", "fst.songs.sort.done", "fst.songs.sort")
        h.waitForTag("fst.songs.list")
        h.tap("fst.songs.filter.open")
        assertCloseAndDismiss("modal-songs-filter", "fst.songs.filter.done", "fst.songs.filter")
        h.assertAccessible()
    }

    @Test
    fun songDetailQuickLinksAndPathsClose() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true), transport)
        h.waitForTag("fst.song-detail.intensity")
        // Quick Links is a sheet on compact windows, an anchored menu (no Close) on medium ones and a rail on expanded ones.
        if (h.exists("fst.quick-links.open")) {
            h.tap("fst.quick-links.open")
            rule.waitUntil(15_000) { h.exists("fst.quick-links.close") || h.exists("fst.quick-links.menu") }
            if (h.exists("fst.quick-links.menu")) {
                Espresso.pressBack()
                h.waitGone("fst.quick-links.menu")
            } else {
                assertCloseAndDismiss("modal-quick-links", "fst.quick-links.close", "fst.quick-links.sheet")
            }
        }
        h.tap("fst.song-detail.paths.open")
        h.waitForTag("fst.paths.close")
        if (h.exists("fst.paths.karaoke-warning")) {
            h.tap("fst.paths.warning.ok")
            h.waitGone("fst.paths.karaoke-warning")
        }
        assertCloseAndDismiss("modal-paths", "fst.paths.close", "fst.song-detail.paths")
        h.assertAccessible()
    }

    @Test
    fun shopFilterCloses() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("shop"), profile = player, stillBackground = true), transport)
        h.tap("fst.shop.filter.open")
        assertCloseAndDismiss("modal-shop-filter", "fst.shop.filter.done", "fst.shop.filter")
        h.assertAccessible()
    }

    @Test
    fun suggestionsFilterCloses() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Suggestions, profile = player, stillBackground = true), transport)
        h.tap("fst.suggestions.filter-button")
        assertCloseAndDismiss("modal-suggestions-filter", "fst.suggestions.filter.done", null, "fst.suggestions.filter.title")
        h.assertAccessible()
    }

    // endregion

    // region Shell

    @Test
    fun profileSheetCloses() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(opensProfileSheet = true, stillBackground = true), transport)
        assertCloseAndDismiss("modal-profile", "fst.profile.close", "fst.profile.sheet")
        h.assertAccessible()
    }

    @Test
    fun notificationsSheetCloses() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, opensNotifications = true, stillBackground = true), transport)
        h.waitForTag("fst.notifications.list")
        assertCloseAndDismiss("modal-notifications", "fst.notifications.close", "fst.notifications.sheet")
        h.assertAccessible()
    }

    @Test
    fun whatsNewCloses() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(whatsNew = "force", stillBackground = true), transport)
        assertCloseAndDismiss("modal-whats-new", "fst.whats-new.close", "fst.whats-new.sheet")
        h.assertAccessible()
    }

    @Test
    fun firstRunGuideCloses() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(firstRun = "force", stillBackground = true), transport)
        assertCloseAndDismiss("modal-first-run", "fst.first-run.close", "fst.first-run.dialog")
        h.assertAccessible()
    }

    // endregion

    // region Settings and player pages

    @Test
    fun settingsPrivacyLicensesAndFeedbackClose() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), transport)
        h.scrollTo("fst.settings.list", "fst.settings.privacy-policy")
        // List/detail windows (issue #371) show the policy in the detail pane, not a modal.
        val panes = h.exists("fst.settings.detail-pane")
        h.tap("fst.settings.privacy-policy")
        if (panes) h.waitForTag("fst.privacy-policy.pane") else assertCloseAndDismiss("modal-privacy-policy", "fst.privacy-policy.close", "fst.privacy-policy.sheet")
        h.scrollTo("fst.settings.list", "fst.settings.feedback.bug")
        h.tap("fst.settings.feedback.bug")
        assertCloseAndDismiss("modal-feedback", "fst.settings.feedback.close", "fst.settings.feedback.dialog", "fst.settings.feedback.title")
        // Alerts keep Material's text-button dismiss (no header Close).
        h.scrollTo("fst.settings.list", "fst.settings.reset")
        h.tap("fst.settings.reset")
        h.waitForTag("fst.settings.reset.dialog")
        assertTrue(!h.exists("fst.settings.reset.close"))
        h.readingOrder("modal-reset-alert")
        h.tap("fst.settings.reset.cancel")
        h.waitGone("fst.settings.reset.dialog")
        h.scrollTo("fst.settings.list", "fst.settings.licenses")
        h.tap("fst.settings.licenses")
        h.waitForTag("fst.licenses.list")
        h.tap(LICENSE_ROW)
        // Wide windows show the text in the detail pane; compact ones in the shared sheet.
        if (!h.exists("fst.licenses.detail-pane")) assertCloseAndDismiss("modal-license", "fst.licenses.close", "fst.licenses.detail")
        h.assertAccessible()
    }

    @Test
    fun findRivalCloses() {
        val rivals = RivalsFixtures.transport().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = RivalsRoute, profile = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player"), stillBackground = true), rivals)
        h.tap("fst.rivals.findRival")
        assertCloseAndDismiss("modal-find-rival", "fst.rivals.find.close", "fst.rivals.find.sheet")
        h.assertAccessible()
    }

    @Test
    fun historySortCloses() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, route = PlayerHistoryRoute("s-alpha", "Solo_Guitar"), stillBackground = true), transport)
        h.waitForTag("fst.history.rows")
        h.tap("fst.history.sort.open")
        assertCloseAndDismiss("modal-history-sort", "fst.history.sort.close", "fst.history.sort")
        h.assertAccessible()
    }

    // endregion

    private companion object {
        const val LICENSE_ROW = "fst.licenses.row.androidx.activity:activity-compose"

        /** Most header actions (e.g. Reset, Submit) between the heading and Close. */
        const val MAX_HEADER_ACTIONS = 2
    }
}
