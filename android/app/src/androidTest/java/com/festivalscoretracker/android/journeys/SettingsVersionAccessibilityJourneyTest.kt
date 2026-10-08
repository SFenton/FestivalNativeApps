package com.festivalscoretracker.android.journeys

import android.os.Build
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.BuildConfig
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.settings.AppBuildInfo
import com.festivalscoretracker.android.core.settings.SettingsDetail
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.settings.AppVersionRow
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Settings → Version → App Version on a real device (issue #413, for the build-commit suffix of
 * #43/#151), with the Accessibility Test Framework on every interaction at font scale 1.0 and
 * 2.0. The row is one read-only TalkBack item (no click action or role) that reads "App Version"
 * before the version and, on stamped builds, the ` · <sha7>` suffix; it keeps the 48 dp
 * `settings-value-row` minimum (R2) and a TalkBack focus box over all its text, its title and
 * value stay inside it without overlapping or clipping, and the Version card reads
 * heading → hint → App Version → Build → Service Version → Service. Connected journeys run the
 * Debug build, which is usually unstamped (`dev`), so the stamped state is also rendered on
 * device from a fixed commit. Run with `device.py test
 * com.festivalscoretracker.android.journeys.SettingsVersionAccessibilityJourneyTest --avd <AVD>`;
 * reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
class SettingsVersionAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val scales = listOf(1f, 2f)

    // region Tests

    @Test
    fun versionCardReadsInOrderAndTheAppVersionRowFitsAtEveryTextSize() {
        val version = AppBuildInfo.versionText(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, BuildConfig.GIT_SHA)
        var scale by mutableFloatStateOf(scales.first())
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), FakeTransport.standard(), fontScale = { scale })
        h.waitForTag("fst.settings.list")
        scales.forEach { s ->
            scale = s
            rule.waitForIdle()
            h.openSetting(SettingsDetail.Version.rowTag, TAG)
            h.waitForTag("fst.settings.service-origin")
            assertRow("fs $s", version)
            assertVersionCardOrder("fs $s", version)
        }
        h.assertAccessible()
    }

    @Test
    fun stampedRowIsOneReadOnlyItemThatFitsAtEveryTextSize() {
        val stamped = AppBuildInfo.versionText(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, STAMPED_SHA)
        assertTrue(stamped.endsWith("${AppBuildInfo.COMMIT_SEPARATOR}${STAMPED_SHA.take(7)}"))
        var scale by mutableFloatStateOf(scales.first())
        h.enableAccessibilityChecks()
        rule.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(scale)) {
                FestivalTheme {
                    // As FestivalApp's root: tags become resource ids for the accessibility-tree checks.
                    Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }.background(BrandTokens.cardBackground).padding(16.dp)) {
                        Box(Modifier.fillMaxWidth()) { AppVersionRow(stamped) }
                    }
                }
            }
        }
        scales.forEach { s ->
            scale = s
            rule.waitForIdle()
            h.waitForTag(TAG)
            assertRow("stamped fs $s", stamped, inList = false)
            refreshAccessibilityTree()
            val order = h.readingOrder("settings-app-version-stamped fs $s")
            val items = order.filter { it.contains("App Version") }
            assertEquals("stamped fs $s: one App Version item ($order)", 1, items.size)
            assertTrue("stamped fs $s: title before the version and commit (${items[0]})", items[0].indexOf(stamped) > items[0].indexOf("App Version"))
        }
        h.assertAccessible()
    }

    // endregion

    // region Row

    /**
     * The App Version row is one merged, non-interactive item reading title then [version], at
     * least 48 dp tall with its padding, with title and value inside it, not overlapping and
     * unclipped, and a TalkBack focus box spanning its text.
     *
     * @param config Configuration name for messages.
     * @param version Expected value text.
     * @param inList Whether the row sits in a scrolling list to bring it on screen first.
     */
    private fun assertRow(config: String, version: String, inList: Boolean = true) {
        if (inList) rule.onNodeWithTag(TAG).performScrollTo()
        rule.waitForIdle()
        val merged = rule.onNodeWithTag(TAG).fetchSemanticsNode()
        assertEquals("$config: reads title then version", listOf("App Version", version), merged.config[SemanticsProperties.Text].map { it.text })
        assertNull("$config: read-only row has no role", merged.config.getOrNull(SemanticsProperties.Role))
        assertFalse("$config: read-only row has no click action", merged.config.contains(SemanticsActions.OnClick))

        val px = rule.density.density
        // The tag sits inside the row's 8 dp vertical padding (settings-value-row R2).
        val row = merged.boundsInRoot
        assertTrue("$config: row at least 48 dp tall with its padding (${row.height / px} + 16 dp)", row.height + 16 * px >= 48 * px - 1)
        val inRow = hasAnyAncestor(hasTestTag(TAG))
        val title = bounds(hasText("App Version") and inRow)
        val value = bounds(hasText(version) and inRow)
        for (part in listOf(title, value)) {
            assertTrue("$config: $part inside $row", part.left >= row.left - 1 && part.right <= row.right + 1 && part.top >= row.top - 1 && part.bottom <= row.bottom + 1)
        }
        assertFalse("$config: $title overlaps $value", title.overlaps(value))
        // didOverflowWidth compares the paragraph's layout width with a box shrunk to the text, so
        // check where the glyphs actually end instead.
        val layout = textLayout(hasText(version) and inRow)
        val lines = (0 until layout.lineCount).map { layout.getLineLeft(it) to layout.getLineRight(it) }
        assertTrue(
            "$config: version text is clipped (box ${layout.size}, lines $lines, overflow h ${layout.didOverflowHeight}, row $row, value $value)",
            !layout.didOverflowHeight && lines.all { (left, right) -> left >= -1 && right <= layout.size.width + 1 },
        )

        val node = accessibilityNode(TAG)
        assertNotNull("$config: App Version is in the accessibility tree", node)
        // Read-only, so the 48 dp touch-target minimum does not apply; the focus box must still cover the whole text.
        assertFalse("$config: TalkBack does not offer a tap action", node!!.isClickable)
        val focus = android.graphics.Rect().also(node::getBoundsInScreen)
        assertTrue("$config: focus ${focus.height() / px} dp tall covers the row's text", focus.height() >= maxOf(title.bottom, value.bottom) - minOf(title.top, value.top) - 1)
    }

    /**
     * Bounds in the root of the first unmerged node matching [matcher].
     *
     * @param matcher Node matcher.
     * @return Bounds in px.
     */
    private fun bounds(matcher: SemanticsMatcher): Rect =
        rule.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().first().boundsInRoot

    /**
     * Text layout of the first unmerged text node matching [matcher].
     *
     * @param matcher Node matcher.
     * @return Its laid-out text.
     */
    private fun textLayout(matcher: SemanticsMatcher): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        val node = rule.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().first()
        node.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(results)
        return results.single()
    }

    // endregion

    // region Accessibility

    /**
     * TalkBack meets the Version card in visual order. At 2.0 the card may not fit the window, so
     * the order is read with the heading, App Version and Service rows on screen in turn; each
     * dump keeps the visible items in order and together they cover all six.
     *
     * @param config Configuration name for messages.
     * @param version App Version value text.
     */
    private fun assertVersionCardOrder(config: String, version: String) {
        val expected = listOf<(String) -> Boolean>(
            { it == SettingsDetail.Version.title },
            { it == SettingsDetail.Version.hint },
            { it.startsWith("App Version") && it.contains(version) },
            { it.startsWith("Build") && (it.contains("Debug") || it.contains("Release")) },
            { it.startsWith("Service Version") },
            { it.startsWith("Service") && !it.startsWith("Service Version") && !it.startsWith(SERVICE_INFO_PREFIX) },
        )
        val seen = BooleanArray(expected.size)
        val anchors = listOf(
            "heading" to (hasText(SettingsDetail.Version.title) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading)),
            "app-version" to hasTestTag(TAG),
            "service-origin" to hasTestTag("fst.settings.service-origin"),
        )
        anchors.forEach { (anchor, matcher) ->
            rule.onAllNodes(matcher)[0].performScrollTo()
            refreshAccessibilityTree()
            val order = h.readingOrder("settings-version $config at $anchor")
            val at = expected.map { match -> order.indexOfFirst(match) }
            val visible = at.withIndex().filter { it.value >= 0 }
            visible.forEach { seen[it.index] = true }
            assertEquals("$config: Version items out of order at $anchor: $order", visible.map { it.value }.sorted(), visible.map { it.value })
        }
        assertTrue("$config: every Version item was read (${seen.toList()})", seen.all { it })
    }

    /** UiAutomation caches nodes and Compose may not invalidate them after a programmatic scroll; read fresh ones. */
    private fun refreshAccessibilityTree() {
        rule.waitForIdle()
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) automation.clearCache()
        runCatching { automation.waitForIdle(500, 5_000) }
    }

    /**
     * The visible accessibility node exposing [tag] as its resource id.
     *
     * @param tag Test tag.
     * @return The node, or `null`.
     */
    private fun accessibilityNode(tag: String): AccessibilityNodeInfo? {
        refreshAccessibilityTree()
        fun find(n: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            n ?: return null
            if (n.viewIdResourceName == tag && n.isVisibleToUser) return n
            for (i in 0 until n.childCount) find(n.getChild(i))?.let { return it }
            return null
        }
        return find(InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow)
    }

    // endregion

    private companion object {
        const val TAG = "fst.settings.app-version"

        /** A full commit; the row shows its first seven characters. */
        const val STAMPED_SHA = "42edc57a1b2c3d4e5f60718293a4b5c6d7e8f901"

        /** The next section's chevron/header ("Service Info …") also starts with "Service". */
        const val SERVICE_INFO_PREFIX = "Service Info"
    }
}
