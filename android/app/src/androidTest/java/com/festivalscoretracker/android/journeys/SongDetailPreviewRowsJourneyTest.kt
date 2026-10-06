package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Song Detail top-ten rows on a device (issues #63, #171): each account row has the Button
 * role (TalkBack reads "… Button") and, in the window's real accessibility tree, is one clickable
 * stop at least 48 dp tall whose click label
 * names the destination ("Open profile"; the appended selected-player row opens "your page of
 * the full leaderboard"), with no focusable children; a row without an account is one
 * unclickable stop reading "Profile unavailable". Activating a row opens the player and Back
 * returns to Song Detail. ATF runs throughout; nothing straddles a hinge
 * (`device.py test com.festivalscoretracker.android.journeys.SongDetailPreviewRowsJourneyTest --avd …`).
 */
@RunWith(AndroidJUnit4::class)
class SongDetailPreviewRowsJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val other = "abcdefabcdefabcdefabcdefabcdef01"
    private val board = """{"songId":"s-alpha","instrument":"Solo_Guitar","count":3,"totalEntries":60,"localEntries":60,"entries":[
      {"accountId":"$other","displayName":"Other Player","score":99999,"rank":1,"accuracy":990000,"isFullCombo":false},
      {"accountId":"","displayName":"","score":99998,"rank":2,"accuracy":990000,"isFullCombo":false},
      {"accountId":"${Fixtures.ACCOUNT_B}","displayName":"Second Player","score":99997,"rank":3,"accuracy":990000,"isFullCombo":false}]}"""
    private val profileJson = """
        {"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":1,"scores":[
          {"si":"s-alpha","ins":"01","sc":50000,"acc":900,"fc":false,"st":5,"sn":15,"dif":3,"rk":42,"te":60,"lp":"2026-09-01T12:00:00Z"}]}
    """.trimIndent()
    private val transport = FakeTransport.standard().apply {
        on("/api/leaderboard/s-alpha/Solo_Guitar") { board }
        on("/api/player/${Fixtures.ACCOUNT_A}") { profileJson }
    }

    private fun row(id: String) = "fst.song-detail.preview-row.Solo_Guitar.$id"

    // region Accessibility tree

    /** Visible accessibility node whose resource id is [tag] (test tags are resource ids), or null. */
    private fun node(tag: String): AccessibilityNodeInfo? {
        fun find(n: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            n ?: return null
            if (n.viewIdResourceName == tag && n.isVisibleToUser) return n
            for (i in 0 until n.childCount) find(n.getChild(i))?.let { return it }
            return null
        }
        return find(InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow)
    }

    /** The clickable node at or directly inside [tag] (the your-rank row wraps its clickable row). */
    private fun clickable(tag: String): AccessibilityNodeInfo {
        var n = requireNotNull(node(tag)) { "no visible $tag" }
        while (!n.isClickable && n.childCount == 1) n = n.getChild(0) ?: break
        return n
    }

    /** Whether any descendant of [n] is a separate TalkBack stop. */
    private fun hasFocusableDescendant(n: AccessibilityNodeInfo): Boolean = (0 until n.childCount).any { i ->
        val c = n.getChild(i) ?: return@any false
        c.isClickable || c.isScreenReaderFocusable || hasFocusableDescendant(c)
    }

    private fun assertButtonRow(tag: String, label: String) {
        // Compose reports the role to TalkBack ("… Button") but leaves a merged row's className a View.
        val isButton = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)
        rule.onNode(hasTestTag(tag) and (isButton or hasAnyDescendant(isButton)), useUnmergedTree = true).assertExists()
        val n = clickable(tag)
        assertTrue("$tag not clickable", n.isClickable)
        assertEquals("$tag click label", label, n.actionList.firstOrNull { it.id == AccessibilityNodeInfo.ACTION_CLICK }?.label?.toString())
        assertFalse("$tag has a second stop inside it", hasFocusableDescendant(n))
        val minPx = 48 * rule.activity.resources.displayMetrics.density - 1
        val box = android.graphics.Rect().also(n::getBoundsInScreen)
        assertTrue("$tag is ${box.height()} px tall (< 48 dp)", box.height() >= minPx)
    }

    // endregion

    @Test
    fun topTenRowsAreButtonsThatOpenTheProfile() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), songQuery = "s-alpha", stillBackground = true), transport)
        h.waitForTag("fst.song-detail.list")
        h.scrollTo("fst.song-detail.list", "fst.song-detail.view-all.Solo_Guitar")
        h.waitForTag(row(Fixtures.ACCOUNT_B))
        h.awaitAccessibilityTree(row(Fixtures.ACCOUNT_B))
        rule.waitUntil(10_000) { node("fst.song-detail.your-rank.Solo_Guitar") != null }

        assertButtonRow(row(other), "Open profile")
        assertButtonRow(row(Fixtures.ACCOUNT_B), "Open profile")
        assertButtonRow("fst.song-detail.your-rank.Solo_Guitar", "Open your page of the full leaderboard")
        val anonymous = requireNotNull(node(row("rank-2"))) { "no visible anonymous row" }
        assertFalse("anonymous row is actionable", anonymous.isClickable)
        assertEquals("Profile unavailable", anonymous.stateDescription?.toString())
        val order = h.readingOrder("song-detail-top-ten")
        listOf("Other Player", "Unknown User", "Second Player").forEach { name ->
            assertEquals("$name stops in $order", 1, order.count { it.contains(name) })
        }
        h.assertNothingStraddles(row(other), row("rank-2"), row(Fixtures.ACCOUNT_B), "fst.song-detail.your-rank.Solo_Guitar")

        // Activating a row opens the player; system Back returns to Song Detail.
        h.tap(row(other))
        h.waitForTag("fst.player")
        h.waitGone("fst.song-detail.list")
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        h.waitForTag("fst.song-detail.list")
        // The top bar's Back does the same from the second row's profile.
        h.waitForTag(row(Fixtures.ACCOUNT_B))
        h.tap(row(Fixtures.ACCOUNT_B))
        h.waitForTag("fst.player")
        h.tap("fst.nav.back")
        h.waitForTag("fst.song-detail.list")
        h.assertAccessible()
    }
}
