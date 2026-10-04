package com.festivalscoretracker.android.design

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.ui.design.StarRating
import com.festivalscoretracker.android.ui.design.StarRatingStyle
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The star rating's five reachable states on a real device (issue #128): what TalkBack's
 * linear order reads, the platform class it sees, Accessibility Test Framework checks and
 * double text. Run with `device.py test com.festivalscoretracker.android.design.StarRatingDeviceTest
 * --avd <AVD>`; reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
class StarRatingDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    /** A reachable state: id, service stars, forced gold (an average of six) and spoken label. */
    private data class State(val id: String, val stars: Int, val gold: Boolean, val label: String)

    private val states = listOf(
        State("white-1", 1, false, "1 star"),
        State("white-5", 5, false, "5 stars"),
        State("gold-6", 6, false, "5 gold stars"),
        State("minimum-one", 0, false, "1 star"),
        State("gold-average", 6, true, "5 gold stars"),
    )

    private fun show(style: StarRatingStyle) {
        rule.setContent {
            FestivalTheme {
                Column(
                    Modifier.fillMaxSize().background(BrandTokens.cardBackground).safeDrawingPadding().padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    states.forEach { state ->
                        StarRating(state.stars, Modifier.testTag("fst.star-rating.${state.id}"), size = 20.dp, gold = state.gold, style = style)
                    }
                }
            }
        }
        h.waitForTag("fst.star-rating.gold-average")
    }

    @Test
    fun everyInlineStateIsOneLabelledImageInOrder() {
        h.enableAccessibilityChecks()
        show(StarRatingStyle.Inline)
        assertEquals(states.map { it.label }, h.readingOrder("star-rating-inline"))
        nodes().filter { it.contentDescription?.toString()?.contains("star") == true }.forEach { node ->
            assertEquals("android.widget.ImageView", node.className?.toString())
            assertFalse(node.isClickable)
            assertFalse(node.isFocusable)
        }
        h.assertAccessible()
    }

    @Test
    fun everyMiniStateIsOneLabelledImageInOrder() {
        h.enableAccessibilityChecks()
        show(StarRatingStyle.Mini)
        assertEquals(states.map { it.label }, h.readingOrder("star-rating-mini"))
        // Mini: 5 × 24 dp circles + 4 × 3 dp gaps.
        assertSize("fst.star-rating.white-5", 132f, 24f)
        assertSize("fst.star-rating.minimum-one", 24f, 24f)
        h.assertAccessible()
    }

    @Test
    fun doubleTextKeepsTheStarGeometryAndLabels() {
        rule.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(2f)) {
                FestivalTheme {
                    Column(Modifier.fillMaxSize().background(BrandTokens.cardBackground).safeDrawingPadding().padding(16.dp)) {
                        StarRating(6, Modifier.testTag("fst.star-rating.gold-6"), size = 20.dp, style = StarRatingStyle.Mini)
                        StarRating(5, Modifier.testTag("fst.star-rating.white-5"), size = 20.dp)
                    }
                }
            }
        }
        h.waitForTag("fst.star-rating.white-5")
        assertSize("fst.star-rating.gold-6", 132f, 24f)
        // Inline: 5 × 20 dp + 4 × 2 dp.
        assertSize("fst.star-rating.white-5", 108f, 20f)
        assertEquals(listOf("5 gold stars", "5 stars"), h.readingOrder("star-rating-font-2"))
    }

    /**
     * Asserts a node's size in dp, allowing for each image and gap rounding to whole pixels at
     * fractional densities (20 dp is 52.5 px at 2.625×; a 3 dp gap is 4.5 px at 1.5×).
     *
     * @param tag Test tag.
     * @param width Expected width in dp.
     * @param height Expected height in dp.
     */
    private fun assertSize(tag: String, width: Float, height: Float) {
        val bounds = rule.onNodeWithTag(tag).getUnclippedBoundsInRoot()
        assertEquals(width, bounds.width.value, 1.5f)
        assertEquals(height, bounds.height.value, 0.75f)
    }

    /** Every visible node of the active window, depth-first. */
    private fun nodes(): List<AccessibilityNodeInfo> {
        val out = mutableListOf<AccessibilityNodeInfo>()
        fun walk(n: AccessibilityNodeInfo) {
            if (!n.isVisibleToUser) return
            out += n
            for (i in 0 until n.childCount) n.getChild(i)?.let(::walk)
        }
        InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow?.let(::walk)
        return out
    }
}
