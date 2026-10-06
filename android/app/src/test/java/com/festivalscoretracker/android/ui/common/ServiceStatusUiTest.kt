package com.festivalscoretracker.android.ui.common

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.HourglassTop
import androidx.compose.material.icons.outlined.SearchOff
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.material3.adaptive.HingeInfo
import androidx.compose.material3.adaptive.Posture
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.HingeSide
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Service status control (`.agents/controls/service-status/spec.md`): every reachable state of
 * the full page and the inline row, the spoken countdown, icons, pulse and large-type stacking.
 */
@RunWith(AndroidJUnit4::class)
class ServiceStatusUiTest {
    @get:Rule
    val rule = createComposeRule()

    // region Pure rules

    @Test
    fun countdownFormatsAsClockAndSpeaksSeconds() {
        assertEquals("0:30", formatCountdown(30))
        assertEquals("1:05", formatCountdown(65))
        assertEquals("5:00", formatCountdown(300))
        assertEquals("Trying again automatically in 30 seconds", countdownLabel(30))
    }

    @Test
    fun everyIssueHasItsOwnIcon() {
        assertEquals(Icons.Outlined.Sync, serviceStatusIcon(ServiceIssue.ScrapeInProgress(30)))
        assertEquals(Icons.Outlined.CloudOff, serviceStatusIcon(ServiceIssue.Unavailable(null)))
        assertEquals(Icons.Outlined.HourglassTop, serviceStatusIcon(ServiceIssue.Syncing))
        assertEquals(Icons.Outlined.SearchOff, serviceStatusIcon(ServiceIssue.NotFound))
        assertEquals(Icons.Outlined.WifiOff, serviceStatusIcon(ServiceIssue.Offline))
        assertEquals(Icons.Outlined.WarningAmber, serviceStatusIcon(ServiceIssue.Other("boom")))
    }

    @Test
    fun onlyAutomaticRetryIsGoldAndPulses() {
        val freeze = ServiceIssue.ScrapeInProgress(30)
        assertEquals(BrandTokens.gold, serviceStatusIconTint(freeze))
        assertEquals(BrandTokens.textPrimary, serviceStatusIconTint(ServiceIssue.Offline))
        assertTrue(serviceStatusPulses(freeze, reduceMotion = false))
        assertFalse(serviceStatusPulses(freeze, reduceMotion = true))
        assertFalse(serviceStatusPulses(ServiceIssue.Unavailable(30), reduceMotion = false))
    }

    @Test
    fun inlineStacksOnlyAtLargeType() {
        assertFalse(inlineStacks(1f))
        assertFalse(inlineStacks(1.3f))
        assertTrue(inlineStacks(INLINE_STACK_FONT_SCALE))
        assertTrue(inlineStacks(2f))
    }

    @Test
    fun shortViewportsUseTheCompactPage() {
        assertTrue(isCompactStatusHeight(220.dp))
        assertFalse(isCompactStatusHeight(COMPACT_STATUS_HEIGHT))
        assertFalse(isCompactStatusHeight(600.dp))
    }

    @Test
    fun tabletopHingeAlwaysKeepsThePageBelowIt() {
        fun side(top: Float, bottom: Float) = serviceStatusHingeSide(800f, 1000f, 0f, top, 800f, bottom, vertical = false, rtl = false)
        // Centred, larger upper half and larger lower half: always below the hinge (shared HingeSide rule).
        assertEquals(HingeSide.Padding(top = 510f), side(490f, 510f))
        assertEquals(HingeSide.Padding(top = 720f), side(700f, 720f))
        assertEquals(HingeSide.Padding(top = 320f), side(300f, 320f))
        // A hinge overlapping the page's top edge still pads through its bottom.
        assertEquals(HingeSide.Padding(top = 20f), side(-10f, 20f))
        // The page ends inside the hinge: no lower half here, keep the part above.
        assertEquals(HingeSide.Padding(bottom = 20f), side(980f, 1010f))
        // The hinge misses the page.
        assertEquals(HingeSide.Padding.NONE, side(1000f, 1020f))
        assertEquals(HingeSide.Padding.NONE, side(-40f, 0f))
        assertEquals(HingeSide.Padding.NONE, serviceStatusHingeSide(800f, 0f, 0f, 0f, 800f, 10f, vertical = false, rtl = false))
    }

    @Test
    fun bookHingeKeepsTheWiderOrLeadingSide() {
        fun side(left: Float, right: Float, rtl: Boolean = false) = serviceStatusHingeSide(1000f, 800f, left, 0f, right, 800f, vertical = true, rtl = rtl)
        assertEquals(HingeSide.Padding(right = 400f), side(600f, 620f))
        assertEquals(HingeSide.Padding(left = 420f), side(400f, 420f))
        assertEquals(HingeSide.Padding(right = 510f), side(490f, 510f))
        assertEquals(HingeSide.Padding(left = 510f), side(490f, 510f, rtl = true))
    }

    // endregion

    // region Full page

    @Test
    fun separatingHingeKeepsThePageOffTheFold() {
        lateinit var hingeLeft: () -> Float
        rule.setContent {
            val width = LocalView.current.rootView.width.toFloat()
            hingeLeft = { width * 0.4f }
            val hinge = HingeInfo(Rect(width * 0.4f, 0f, width * 0.42f, 5000f), isFlat = false, isVertical = true, isSeparating = true, isOccluding = true)
            CompositionLocalProvider(LocalShellPosture provides Posture(isTabletop = false, hingeList = listOf(hinge))) {
                FestivalTheme { ServiceStatusView(ServiceIssue.ScrapeInProgress(30), "Leaderboards unavailable", 30, onRetry = {}) }
            }
        }
        rule.waitForIdle()
        for (tag in listOf("fst.service-status.title", "fst.service-status.countdown", "fst.service-status.retry")) {
            val bounds = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInWindow
            assertTrue("$tag clears the fold", bounds.left >= hingeLeft() * 1.05f - 1f)
        }
    }

    @Test
    fun tabletopHingeKeepsThePageBelowTheFold() = assertBelowTabletopHinge(0.48f)

    @Test
    fun asymmetricTabletopHingeStillKeepsThePageBelowTheFold() = assertBelowTabletopHinge(0.62f)

    /**
     * Shows the offline page under a separating horizontal hinge whose top is at [fraction] of the
     * window height and asserts its heading and Retry sit below it. At 0.62 the larger half is
     * above the hinge, where the old larger-side rule put the page.
     *
     * @param fraction Hinge top as a fraction of the window height.
     */
    private fun assertBelowTabletopHinge(fraction: Float) {
        var foldBottom = 0f
        rule.setContent {
            val height = LocalView.current.rootView.height.toFloat()
            foldBottom = height * (fraction + 0.02f)
            val hinge = HingeInfo(Rect(0f, height * fraction, 5000f, foldBottom), isFlat = false, isVertical = false, isSeparating = true, isOccluding = true)
            CompositionLocalProvider(LocalShellPosture provides Posture(isTabletop = true, hingeList = listOf(hinge))) {
                FestivalTheme { ServiceStatusView(ServiceIssue.Offline, "Leaderboards unavailable", null, onRetry = {}) }
            }
        }
        rule.waitForIdle()
        assertTrue("window measured", foldBottom > 0f)
        for (tag in listOf("fst.service-status.title", "fst.service-status.retry")) {
            val bounds = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInWindow
            assertTrue("$tag is below the fold at $fraction (${bounds.top} < $foldBottom)", bounds.top >= foldBottom - 1f)
        }
    }

    @Test
    fun compactHeightDropsTheIconButKeepsRetry() {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.height(220.dp)) {
                    ServiceStatusView(ServiceIssue.ScrapeInProgress(30), "Leaderboards unavailable", 30, onRetry = {})
                }
            }
        }
        rule.onNodeWithTag("fst.service-status.retry").assertIsDisplayed()
        val retry = rule.onNodeWithTag("fst.service-status.retry").fetchSemanticsNode().boundsInRoot
        assertTrue("Retry is above the fold", retry.bottom <= with(rule.density) { 220.dp.toPx() })
    }

    @Test
    fun scrapeFreezeCountdownShowsClockSpeaksSecondsAndRetriesNow() {
        var retries = 0
        page(ServiceIssue.ScrapeInProgress(30), countdown = 30) { retries++ }
        rule.onNodeWithTag("fst.service-status.title").assert(hasText("Scores are updating")).assert(isHeading())
        rule.onNodeWithTag("fst.service-status.countdown")
            .assert(hasText("Trying again in 0:30"))
            .assert(hasContentDescription("Trying again automatically in 30 seconds"))
        rule.onNodeWithTag("fst.service-status.retry").assert(hasText("Retry Now")).assertHeightIsAtLeast(48.dp).performClick()
        assertEquals(1, retries)
        rule.onNode(hasLiveRegion()).assertIsDisplayed()
            .assert(hasAnyDescendant(hasTestTag("fst.service-status.title")))
            .assert(hasAnyDescendant(hasText(ServiceIssue.ScrapeInProgress(30).message)))
        // The ticking countdown and Retry sit outside the live region, so ticks never re-announce.
        rule.onNodeWithTag("fst.service-status.countdown").assert(!hasAnyAncestor(hasLiveRegion()))
        rule.onNodeWithTag("fst.service-status.retry").assert(!hasAnyAncestor(hasLiveRegion()))
    }

    @Test
    fun scrapeFreezeRetryingFollowsTheBackedOffCountdown() {
        var remaining by mutableStateOf(1)
        rule.setContent {
            FestivalTheme {
                ServiceStatusView(ServiceIssue.ScrapeInProgress(30), "Leaderboards unavailable", remaining, onRetry = {})
            }
        }
        rule.onNodeWithTag("fst.service-status.countdown").assert(hasText("Trying again in 0:01"))
        remaining = 60
        rule.onNodeWithTag("fst.service-status.countdown")
            .assert(hasText("Trying again in 1:00"))
            .assert(hasContentDescription("Trying again automatically in 60 seconds"))
        rule.onNodeWithTag("fst.service-status.retry").assert(hasText("Retry Now"))
    }

    @Test
    fun unavailableUsesScreenTitleAndManualRetry() {
        var retries = 0
        page(ServiceIssue.Unavailable(null), countdown = null) { retries++ }
        rule.onNodeWithTag("fst.service-status.title").assert(hasText("Leaderboards unavailable"))
        rule.onNodeWithText(ServiceIssue.Unavailable(null).message).assertIsDisplayed()
        rule.onNodeWithTag("fst.service-status.countdown").assertDoesNotExist()
        rule.onNodeWithTag("fst.service-status.retry").assert(hasText("Retry")).performClick()
        assertEquals(1, retries)
    }

    @Test
    fun unavailableWithRetryAfterNamesTheWait() {
        val issue = ServiceIssue.Unavailable(45)
        page(issue, countdown = null)
        assertTrue(issue.message.contains("45"))
        rule.onNodeWithText(issue.message).assertIsDisplayed()
        rule.onNodeWithTag("fst.service-status.countdown").assertDoesNotExist()
    }

    @Test
    fun offlineHasItsOwnHeadingAndNoCountdown() {
        page(ServiceIssue.Offline, countdown = null)
        rule.onNodeWithTag("fst.service-status.title").assert(hasText("You're offline")).assert(isHeading())
        rule.onNodeWithText(ServiceIssue.Offline.message).assertIsDisplayed()
        rule.onNodeWithTag("fst.service-status.retry").assert(hasText("Retry"))
    }

    @Test
    fun syncingHasItsOwnHeading() {
        page(ServiceIssue.Syncing, countdown = null)
        rule.onNodeWithTag("fst.service-status.title").assert(hasText("Still syncing"))
        rule.onNodeWithTag("fst.service-status.retry").assert(hasText("Retry"))
    }

    @Test
    fun notFoundFallsBackToScreenTitle() {
        page(ServiceIssue.NotFound, countdown = null)
        rule.onNodeWithTag("fst.service-status.title").assert(hasText("Leaderboards unavailable"))
        rule.onNodeWithText(ServiceIssue.NotFound.message).assertIsDisplayed()
    }

    @Test
    fun otherShowsReadableMessage() {
        val issue = ServiceIssue.Other("Something went wrong.")
        page(issue, countdown = null)
        rule.onNodeWithTag("fst.service-status.title").assert(hasText("Leaderboards unavailable"))
        rule.onNodeWithText(issue.message).assertIsDisplayed()
    }

    @Test
    fun freezeRendersWithReducedMotion() {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = true)) {
                    ServiceStatusView(ServiceIssue.ScrapeInProgress(30), "Leaderboards unavailable", 30, onRetry = {})
                }
            }
        }
        rule.onNodeWithTag("fst.service-status.countdown").assertIsDisplayed()
    }

    @Test
    fun fullPageKeepsEveryPartAtDoubleFontScale() {
        rule.setContent {
            FestivalTheme {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f)) {
                    ServiceStatusView(ServiceIssue.ScrapeInProgress(30), "Leaderboards unavailable", 30, onRetry = {})
                }
            }
        }
        rule.onNodeWithTag("fst.service-status.title").assertIsDisplayed()
        rule.onNodeWithTag("fst.service-status.countdown").assertIsDisplayed()
        rule.onNodeWithTag("fst.service-status.retry").assertExists().assertHeightIsAtLeast(48.dp)
    }

    // endregion

    // region Inline

    @Test
    fun inlineCountdownIsSilentAndSpeaksSeconds() {
        var retries = 0
        rule.setContent {
            FestivalTheme {
                ServiceStatusInline(ServiceIssue.ScrapeInProgress(30), "Lead unavailable", 30, onRetry = { retries++ }, retryTag = "row.retry")
            }
        }
        rule.onNodeWithTag("fst.service-status.inline").assertIsDisplayed()
        rule.onNode(hasLiveRegion()).assertDoesNotExist()
        rule.onNodeWithText("Scores are updating").assertIsDisplayed()
        rule.onNodeWithText("Trying again in 0:30").assert(hasContentDescription("Trying again automatically in 30 seconds"))
        rule.onNodeWithTag("row.retry").assert(hasText("Retry Now")).assertHeightIsAtLeast(48.dp).performClick()
        assertEquals(1, retries)
    }

    @Test
    fun inlineManualStateShowsMessageAndRetry() {
        rule.setContent {
            FestivalTheme {
                ServiceStatusInline(ServiceIssue.Offline, "Lead unavailable", null, onRetry = {})
            }
        }
        rule.onNodeWithText("You're offline").assertIsDisplayed()
        rule.onNodeWithText(ServiceIssue.Offline.message).assertIsDisplayed()
        rule.onNodeWithText("Retry").assertIsDisplayed()
        rule.onNodeWithText("Retry Now").assertDoesNotExist()
    }

    @Test
    fun inlineStacksRetryUnderTextAtDoubleFontScale() {
        rule.setContent {
            FestivalTheme {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f)) {
                    ServiceStatusInline(ServiceIssue.ScrapeInProgress(30), "Lead unavailable", 30, onRetry = {}, retryTag = "row.retry")
                }
            }
        }
        val text = rule.onNodeWithText("Trying again in 0:30").fetchSemanticsNode().boundsInRoot
        val retry = rule.onNodeWithTag("row.retry").fetchSemanticsNode().boundsInRoot
        assertTrue("Retry sits below the countdown", retry.top >= text.bottom)
        rule.onNodeWithTag("row.retry").assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun inlineSitsBesideTextAtDefaultScale() {
        rule.setContent {
            FestivalTheme {
                ServiceStatusInline(ServiceIssue.Unavailable(null), "Lead unavailable", null, onRetry = {}, retryTag = "row.retry")
            }
        }
        val title = rule.onNodeWithText("Lead unavailable").fetchSemanticsNode().boundsInRoot
        val retry = rule.onNodeWithTag("row.retry").fetchSemanticsNode().boundsInRoot
        assertTrue("Retry sits beside the text", retry.left >= title.right)
    }

    @Test
    fun inlineWithoutRetryShowsOnlyStatusAtBothScales() {
        var scale by mutableStateOf(1f)
        rule.setContent {
            FestivalTheme {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = scale)) {
                    ServiceStatusInline(ServiceIssue.Offline, "Players unavailable", null, onRetry = null, retryTag = "row.retry")
                }
            }
        }
        for (value in listOf(1f, 2f)) {
            scale = value
            rule.waitForIdle()
            rule.onNodeWithTag("fst.service-status.inline").assertIsDisplayed()
            rule.onNodeWithText("You're offline").assertIsDisplayed()
            rule.onNodeWithTag("row.retry").assertDoesNotExist()
            rule.onNodeWithText("Retry").assertDoesNotExist()
        }
    }

    // endregion

    // region Helpers

    private fun page(issue: ServiceIssue, countdown: Int?, onRetry: () -> Unit = {}) {
        rule.setContent { Themed { ServiceStatusView(issue, "Leaderboards unavailable", countdown, onRetry) } }
    }

    @Composable
    private fun Themed(content: @Composable () -> Unit) = FestivalTheme { content() }

    private fun isHeading() = SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading)

    private fun hasLiveRegion() = SemanticsMatcher("has live region") { it.config.getOrNull(SemanticsProperties.LiveRegion) != null }

    // endregion
}
