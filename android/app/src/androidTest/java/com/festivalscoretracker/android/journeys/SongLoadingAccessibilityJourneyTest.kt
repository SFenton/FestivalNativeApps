package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.window.layout.FoldingFeature.Orientation
import androidx.window.layout.WindowInfoTracker
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.HingeSide
import com.festivalscoretracker.android.core.shell.BottomChromeSpacing
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Song Details' first-load spinner centres below the top bar and above lower chrome, in the
 * wider/leading book or lower tabletop pane rather than on the fold (#624). Fixtures hold the previews open;
 * ATF and the published TalkBack order check one named indeterminate stop at both text sizes.
 */
@DeviceCi
@HalfOpenFoldJourney
@RunWith(AndroidJUnit4::class)
class SongLoadingAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val previews = CompletableDeferred<Unit>()
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) {
            Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null")
        }
        beforeRespond = { request -> if ("/api/leaderboard/" in request.url) previews.await() }
    }

    @After
    fun releaseReads() {
        previews.complete(Unit)
    }

    @Test
    fun spinnerCentresInTheVisibleRegion() = journey(1f)

    @Test
    fun spinnerCentresInTheVisibleRegionAtLargeText() = journey(2f)

    private fun journey(scale: Float) {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true), transport, fontScale = { scale })
        h.waitForTag("fst.load-gate.spinner")
        h.publishTalkBackTree()
        h.requireHingeWhenAsked()
        rule.waitForIdle()
        val gate = rule.onNodeWithTag("fst.load-gate").fetchSemanticsNode().boundsInWindow
        val bottomGap = with(rule.density) { BottomChromeSpacing.GAP_DP.dp.toPx() }
        val hasBottomBar = rule.onAllNodes(hasTestTag("fst.nav.bar"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        val navigationBottom = if (hasBottomBar) 0 else checkNotNull(ViewCompat.getRootWindowInsets(rule.activity.window.decorView))
            .getInsets(WindowInsetsCompat.Type.navigationBars()).bottom
        val page = HingeSide.Rect(gate.left, gate.top, gate.right, gate.bottom - bottomGap - navigationBottom)
        val fold = runBlocking {
            withTimeout(5_000) { WindowInfoTracker.getOrCreate(rule.activity).windowLayoutInfo(rule.activity).first() }
        }.displayFeatures.filterIsInstance<androidx.window.layout.FoldingFeature>().firstOrNull { it.isSeparating }
        if (InstrumentationRegistry.getArguments().getString("fstRequireHorizontalHinge") == "true") {
            assertTrue("a separating horizontal hinge is required for tabletop coverage", fold?.orientation == Orientation.HORIZONTAL)
        }
        val region = fold?.let {
            val bounds = it.bounds
            HingeSide.keep(page, HingeSide.Rect(bounds.left.toFloat(), bounds.top.toFloat(), bounds.right.toFloat(), bounds.bottom.toFloat()), vertical = it.orientation == Orientation.VERTICAL, separating = true, rtl = false)
        } ?: page
        val indicators = rule.onAllNodes(hasContentDescription("Loading song"), useUnmergedTree = true).fetchSemanticsNodes()
        assertEquals("one named busy indicator", 1, indicators.size)
        val spinner = indicators.single()
        assertEquals(ProgressBarRangeInfo.Indeterminate, spinner.config.getOrNull(SemanticsProperties.ProgressBarRangeInfo))
        assertEquals("horizontal centre of usable pane", (region.left + region.right) / 2, spinner.boundsInWindow.center.x, 2f)
        assertEquals("vertical centre above bottom chrome", (region.top + region.bottom) / 2, spinner.boundsInWindow.center.y, 2f)
        assertTrue("spinner is not a touch target", !spinner.config.contains(androidx.compose.ui.semantics.SemanticsActions.OnClick))
        val order = h.readingOrder("song-loading fs=$scale", fresh = true)
        assertEquals("one TalkBack loading stop", 1, order.count { it.startsWith("Loading song") })
        val back = order.indexOfFirst { it.startsWith("Back") }
        assertTrue("Back precedes loading: $order", back >= 0 && back < order.indexOfFirst { it.startsWith("Loading song") })
        h.assertTouchTarget("song-loading", "fst.nav.back")
        h.assertAccessible()
    }
}
