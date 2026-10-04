package com.festivalscoretracker.android.design

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.ui.design.InstrumentSelector
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.theme.systemReducesMotion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The Instrument Selector's states on a real device (issue #129): what TalkBack's linear
 * order reads and which platform class it sees, Accessibility Test Framework checks
 * (48 dp targets, labels, contrast), font scale 2.0, the device's animator scale, and the
 * Songs filter's deferred compact selector. Run with `device.py test
 * com.festivalscoretracker.android.design.InstrumentSelectorDeviceTest --avd <AVD>`; reading
 * orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
class InstrumentSelectorDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val four = listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals)

    /** Optional (none/selected, disabled Bass, muted Drums), required (hidden Vocals) and compact deferred selectors. */
    @Composable
    private fun States() {
        var optional by remember { mutableStateOf<Instrument?>(null) }
        var required by remember { mutableStateOf<Instrument?>(Instrument.Lead) }
        var deferred by remember { mutableStateOf<Instrument?>(null) }
        Column(Modifier.fillMaxSize().background(BrandTokens.cardBackground).safeDrawingPadding().verticalScroll(rememberScrollState()).padding(16.dp)) {
            InstrumentSelector(four, optional, { optional = it }, disabled = setOf(Instrument.Bass), muted = setOf(Instrument.Drums), compact = false, tag = "opt")
            InstrumentSelector(four, required, { required = it }, hidden = setOf(Instrument.Vocals), required = true, compact = false, tag = "req", modifier = Modifier.padding(top = 16.dp))
            InstrumentSelector(four, deferred, { deferred = it }, compact = true, deferSelection = true, tag = "cmp", modifier = Modifier.padding(top = 16.dp)) {
                Text("Detail for the chosen chart", Modifier.height(48.dp).testTag("cmp.body"), color = BrandTokens.textPrimary)
            }
        }
    }

    @Test
    fun everyStateReadsItsRoleAndStateWithAccessibleTargets() {
        h.enableAccessibilityChecks()
        rule.setContent { FestivalTheme { States() } }
        h.waitForTag("cmp.preview")
        val order = h.readingOrder("instrument-selector-none")
        val expected = listOf("Lead", "Bass", "Drums", "Tap Vocals", "Lead", "Bass", "Drums", "Previous instrument", "Lead", "Next instrument")
        assertEquals(order.toString(), expected, order.map { it.substringBefore(",") })
        assertTrue(order.toString(), order[1].contains("Unavailable"))
        assertTrue(order.toString(), order[2].contains("conflicts with another choice"))
        // Optional: four circles (disabled Bass included) and the compact centre; required: three circles.
        assertEquals(5, nodes { it.className == "android.widget.CheckBox" }.size)
        assertEquals(3, nodes { it.className == "android.widget.RadioButton" }.size)

        h.tap("opt.Solo_Guitar")
        h.tap("req.Solo_Drums")
        h.tap("cmp.next")
        h.tap("cmp.next")
        h.tap("cmp.preview")
        h.waitForTag("cmp.body")
        // Compose publishes accessibility changes after a short debounce.
        rule.waitUntil(5_000) { nodes { it.text?.toString() == "Detail for the chosen chart" }.isNotEmpty() }
        val after = h.readingOrder("instrument-selector-selected")
        assertTrue(after.toString(), after.any { it.startsWith("Detail for the chosen chart") })
        assertEquals(listOf(true, false, false, false), four.map { checked("opt.${it.wireId}") })
        assertEquals(listOf(false, false, true), four.take(3).map { checked("req.${it.wireId}") })
        assertEquals("Drums", rule.onNodeWithTag("cmp.preview").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].single())
        h.assertAccessible()
    }

    @Test
    fun doubleTextKeepsTheCirclesAndArrows() {
        rule.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(2f)) { FestivalTheme { States() } }
        }
        h.waitForTag("cmp.preview")
        four.forEach { rule.onNodeWithTag("opt.${it.wireId}").assertWidthIsEqualTo(64.dp).assertHeightIsEqualTo(64.dp) }
        rule.onNodeWithTag("cmp.preview").assertWidthIsEqualTo(64.dp)
        val icon = nodes { it.contentDescription?.toString() == "Next instrument" }.single()
        val arrow = generateSequence(icon) { it.parent }.first { it.isClickable }
        val bounds = android.graphics.Rect().also(arrow::getBoundsInScreen)
        val min = with(rule.density) { 48.dp.roundToPx() }
        assertTrue("arrow touch bounds $bounds", bounds.width() >= min && bounds.height() >= min)
    }

    /**
     * Cold-booted FST emulators run at animator scale 0 (reduced motion): the detail and disc
     * appear on the first frames. With `--animations` the detail is still expanding.
     */
    @Test
    fun theDeviceAnimatorScaleDecidesWhetherTheDetailAnimates() {
        val still = systemReducesMotion(rule.activity)
        rule.setContent { FestivalTheme { States() } }
        h.waitForTag("cmp.preview")
        rule.mainClock.autoAdvance = false
        rule.onNodeWithTag("cmp.preview").performSemanticsAction(SemanticsActions.OnClick)
        repeat(3) { rule.mainClock.advanceTimeByFrame() }
        val full = with(rule.density) { 48.dp.toPx() }
        val height = rule.onNodeWithTag("cmp.detail").fetchSemanticsNode().size.height.toFloat()
        if (still) assertEquals("reduced motion: detail at full height", full, height, 1f) else assertTrue("animating: $height < $full", height < full)
        rule.mainClock.autoAdvance = true
    }

    @Test
    fun songsFilterDeferredSelectorReadsItsArrowsAndPreview() {
        h.enableAccessibilityChecks()
        val transport = FakeTransport.standard().apply { ProfileFixtures.register(this) }
        h.launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true), transport)
        h.waitForTag("fst.songs.list")
        h.tap("fst.songs.filter.open")
        h.scrollTo("fst.songs.filter.form", "fst.songs.filter.instrument")
        val tag = if (h.exists("fst.songs.filter.instrument.compact")) "fst.songs.filter.instrument.preview" else "fst.songs.filter.instrument.Solo_Guitar"
        h.scrollTo("fst.songs.filter.form", tag)
        val order = h.readingOrder("songs-filter-instrument")
        assertTrue(order.toString(), order.any { it.startsWith("Lead") })
        if (tag.endsWith("preview")) assertTrue(order.toString(), "Previous instrument" in order && "Next instrument" in order)
        h.tap(tag)
        h.scrollTo("fst.songs.filter.form", "fst.songs.filter.instrument.detail")
        assertTrue(checked(tag))
        h.assertAccessible()
    }

    private fun checked(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().config
        .getOrElse(androidx.compose.ui.semantics.SemanticsProperties.Selected) { false }

    /** Visible nodes of the active window matching [predicate]. */
    private fun nodes(predicate: (AccessibilityNodeInfo) -> Boolean): List<AccessibilityNodeInfo> {
        rule.waitForIdle()
        val out = mutableListOf<AccessibilityNodeInfo>()
        fun walk(n: AccessibilityNodeInfo) {
            if (!n.isVisibleToUser) return
            if (predicate(n)) out += n
            for (i in 0 until n.childCount) n.getChild(i)?.let(::walk)
        }
        InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow?.let(::walk)
        return out
    }
}
