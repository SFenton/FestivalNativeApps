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
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
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
    fun hingePaddingKeepsThePageOnTheWiderSide() {
        assertEquals(0f to 0f, hingeSidePadding(1000f, 1100f, 1120f, preferEnd = false))
        assertEquals(0f to 0f, hingeSidePadding(1000f, -40f, -10f, preferEnd = false))
        assertEquals(0f to 0f, hingeSidePadding(0f, 0f, 10f, preferEnd = false))
        // Hinge right of centre: content stays left of it.
        assertEquals(0f to 400f, hingeSidePadding(1000f, 600f, 620f, preferEnd = false))
        // Hinge left of centre: content starts after it.
        assertEquals(420f to 0f, hingeSidePadding(1000f, 400f, 420f, preferEnd = false))
        // A centred hinge follows the tie-break.
        assertEquals(0f to 510f, hingeSidePadding(1000f, 490f, 510f, preferEnd = false))
        assertEquals(510f to 0f, hingeSidePadding(1000f, 490f, 510f, preferEnd = true))
        // A hinge overlapping the page's start edge.
        assertEquals(20f to 0f, hingeSidePadding(1000f, -10f, 20f, preferEnd = false))
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
    fun tabletopHingeKeepsThePageBelowTheFold() {
        var foldBottom = 0f
        rule.setContent {
            val height = LocalView.current.rootView.height.toFloat()
            foldBottom = height * 0.5f
            val hinge = HingeInfo(Rect(0f, height * 0.48f, 5000f, foldBottom), isFlat = false, isVertical = false, isSeparating = true, isOccluding = true)
            CompositionLocalProvider(LocalShellPosture provides Posture(isTabletop = true, hingeList = listOf(hinge))) {
                FestivalTheme { ServiceStatusView(ServiceIssue.Offline, "Leaderboards unavailable", null, onRetry = {}) }
            }
        }
        rule.waitForIdle()
        val title = rule.onNodeWithTag("fst.service-status.title").fetchSemanticsNode().boundsInWindow
        assertTrue("Title is below the fold", title.top >= foldBottom - 1f)
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
