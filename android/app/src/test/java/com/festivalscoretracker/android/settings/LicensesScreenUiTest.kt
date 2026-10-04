package com.festivalscoretracker.android.settings

import android.os.Looper
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.licenses.LicenseManifest
import com.festivalscoretracker.android.core.licenses.LicensedPackage
import com.festivalscoretracker.android.ui.settings.LicensesContent
import com.festivalscoretracker.android.ui.settings.LicensesScreen
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import kotlinx.coroutines.awaitCancellation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.Duration

// region Fixtures

/** Two packages: one with a project link (Apache-2.0), one without (two licenses). */
private val MANIFEST = LicenseManifest(
    packages = listOf(
        LicensedPackage("androidx.activity", "activity-compose", "1.10.1", "Activity Compose", listOf("Apache-2.0"), "https://developer.android.com/jetpack/androidx/releases/activity"),
        LicensedPackage("com.google.protobuf", "protobuf-javalite", "4.28.2", "Protocol Buffers", listOf("BSD-3-Clause", "Apache-2.0")),
    ),
    texts = mapOf("Apache-2.0" to "Apache License text", "BSD-3-Clause" to "BSD license text"),
)

private const val FIRST = "fst.licenses.row.androidx.activity:activity-compose"
private const val SECOND = "fst.licenses.row.com.google.protobuf:protobuf-javalite"

/** Shared Robolectric driving for the Licenses page tests. */
private abstract class LicensesHarness {
    abstract val rule: androidx.compose.ui.test.junit4.ComposeContentTestRule

    fun settle() = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
        rule.waitForIdle()
    }

    fun has(tag: String, unmerged: Boolean = false) = rule.onAllNodesWithTag(tag, useUnmergedTree = unmerged).fetchSemanticsNodes().isNotEmpty()

    fun waitFor(tag: String) = rule.waitUntil(10_000) { settle(); has(tag) }

    fun screen(manifest: LicenseManifest = MANIFEST) {
        rule.setContent { FestivalTheme(appReduceMotion = true) { LicensesScreen(loadManifest = { manifest }) } }
        settle()
    }

    fun tap(tag: String) {
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }
}

// endregion

// region Compact window

/** Phone (compact): rows open a sheet; empty and loading states. */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class LicensesCompactUiTest {
    @get:Rule
    val rule = createComposeRule()
    private val h = object : LicensesHarness() { override val rule get() = this@LicensesCompactUiTest.rule }

    @Test
    fun rowsAreButtonsThatOpenAndCloseTheSheet() {
        h.screen()
        h.waitFor(FIRST)
        val row = rule.onNodeWithTag(FIRST).fetchSemanticsNode()
        assertEquals(androidx.compose.ui.semantics.Role.Button, row.config.getOrNull(SemanticsProperties.Role))
        // One reading: the visible texts in order, no duplicate description, and no selection
        // state without a detail pane.
        assertNull(row.config.getOrNull(SemanticsProperties.ContentDescription))
        assertEquals(listOf("Activity Compose", "Maven · androidx.activity:activity-compose 1.10.1", "Apache-2.0"), row.config[SemanticsProperties.Text].map { it.text })
        assertNull(row.config.getOrNull(SemanticsProperties.Selected))
        assertEquals("BSD-3-Clause / Apache-2.0", rule.onNodeWithTag(SECOND).fetchSemanticsNode().config[SemanticsProperties.Text].last().text)
        assertTrue(row.size.height >= with(rule.density) { 48.dp.roundToPx() })
        assertFalse(h.has("fst.licenses.detail-pane"))

        // Inline badge at the default scale: beside the name, never below it.
        val name = rule.onAllNodesWithText("Activity Compose", useUnmergedTree = true)[0].getUnclippedBoundsInRoot()
        val badge = rule.onAllNodesWithTag("fst.licenses.badge", useUnmergedTree = true)[0].getUnclippedBoundsInRoot()
        assertTrue(badge.left > name.left && badge.top < name.bottom)

        h.tap(SECOND)
        h.waitFor("fst.licenses.detail")
        assertTrue(rule.onAllNodesWithText("BSD license text\n\n———\n\nApache License text", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        assertFalse(h.has("fst.licenses.project-link", unmerged = true))
        h.tap("fst.licenses.close")
        rule.waitUntil(10_000) { h.settle(); !h.has("fst.licenses.detail") }

        h.tap(FIRST)
        h.waitFor("fst.licenses.detail")
        assertTrue(h.has("fst.licenses.project-link", unmerged = true))
    }

    @Test
    fun emptyManifestExplainsThereAreNoPackages() {
        h.screen(LicenseManifest())
        h.waitFor("fst.licenses.list")
        assertTrue(rule.onAllNodesWithText("This build includes no third-party packages.").fetchSemanticsNodes().isNotEmpty())
        assertFalse(h.has("fst.licenses.detail-pane"))
        assertFalse(h.has("fst.licenses.detail-empty"))
    }

    @Test
    fun manifestStillLoadingShowsTheLoadGateOnly() {
        rule.setContent { FestivalTheme(appReduceMotion = true) { LicensesScreen(loadManifest = { awaitCancellation() }) } }
        h.settle()
        assertFalse(h.has("fst.licenses.list"))
        assertTrue(rule.onAllNodesWithText("Licenses").fetchSemanticsNodes().isNotEmpty())
    }
}

// endregion

// region Large text

/** Phone at 200%: the badge stacks under the coordinates and is never cut short. */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2f)
class LicensesLargeTextUiTest {
    @get:Rule
    val rule = createComposeRule()
    private val h = object : LicensesHarness() { override val rule get() = this@LicensesLargeTextUiTest.rule }

    @Test
    fun badgeStacksUnderTheCoordinatesWithoutTruncation() {
        h.screen()
        h.waitFor(SECOND)
        val badges = rule.onAllNodesWithTag("fst.licenses.badge", useUnmergedTree = true)
        val coordinates = rule.onAllNodesWithText("Maven · androidx.activity:activity-compose 1.10.1", useUnmergedTree = true)[0].getUnclippedBoundsInRoot()
        val badge = badges[0].getUnclippedBoundsInRoot()
        assertTrue("badge below the coordinates", badge.top >= coordinates.bottom)
        // The tag sits inside the pill's 8 dp padding, so the pill itself lines up with the coordinates.
        assertEquals(coordinates.left + 8.dp, badge.left)
        // Robolectric measures glyphs crudely, so overflow is checked on the emulator (issue #122); here
        // the badge's position and full text are the contract.
        assertEquals("BSD-3-Clause / Apache-2.0", badges[1].fetchSemanticsNode().config[SemanticsProperties.Text].joinToString { it.text })
    }
}

/** Expanded window at 200%: 1280 dp is only 640 text-scaled dp, so the page keeps one column and a sheet. */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi", fontScale = 2f)
class LicensesExpandedLargeTextUiTest {
    @get:Rule
    val rule = createComposeRule()
    private val h = object : LicensesHarness() { override val rule get() = this@LicensesExpandedLargeTextUiTest.rule }

    @Test
    fun largeTextKeepsOneColumnAndASheet() {
        h.screen()
        h.waitFor(FIRST)
        assertFalse(h.has("fst.licenses.detail-pane"))
        h.tap(FIRST)
        h.waitFor("fst.licenses.detail")
    }
}

// endregion

// region Panes

/** Medium window (tablet portrait, 800 dp): one column with a sheet. */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w800dp-h1232dp-xhdpi")
class LicensesMediumUiTest {
    @get:Rule
    val rule = createComposeRule()
    private val h = object : LicensesHarness() { override val rule get() = this@LicensesMediumUiTest.rule }

    @Test
    fun mediumWindowUsesTheSheet() {
        h.screen()
        h.waitFor(FIRST)
        assertFalse(h.has("fst.licenses.detail-pane"))
        h.tap(SECOND)
        h.waitFor("fst.licenses.detail")
    }
}

/** Flat unfolded book fold (852 dp, expanded): list and detail panes, never a sheet across the fold. */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w852dp-h883dp-hdpi")
class LicensesExpandedUiTest {
    @get:Rule
    val rule = createComposeRule()
    private val h = object : LicensesHarness() { override val rule get() = this@LicensesExpandedUiTest.rule }

    @Test
    fun expandedWindowShowsTheSelectedPackageBesideTheList() {
        h.screen()
        h.waitFor("fst.licenses.detail-pane")
        rule.onNodeWithTag(FIRST).assertIsSelected()
        rule.onNodeWithTag(SECOND).assertIsNotSelected()
        assertTrue(rule.onAllNodesWithText("Apache License text", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        val list = rule.onNodeWithTag("fst.licenses.list").getUnclippedBoundsInRoot()
        val pane = rule.onNodeWithTag("fst.licenses.detail-pane").getUnclippedBoundsInRoot()
        assertTrue(pane.left >= list.right)

        h.tap(SECOND)
        rule.onNodeWithTag(SECOND).assertIsSelected()
        rule.onNodeWithTag(FIRST).assertIsNotSelected()
        assertTrue(rule.onAllNodesWithText("BSD license text\n\n———\n\nApache License text", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        assertFalse(h.has("fst.licenses.detail"))
    }

    @Test
    fun emptyManifestOnAWideWindowKeepsOneColumn() {
        h.screen(LicenseManifest())
        h.waitFor("fst.licenses.list")
        assertFalse(h.has("fst.licenses.detail-pane"))
    }
}

/** Book posture (half-open, separating hinge): the list ends at the hinge and the detail starts after it. */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w673dp-h841dp-hdpi")
class LicensesHingeUiTest {
    @get:Rule
    val rule = createComposeRule()
    private val h = object : LicensesHarness() { override val rule get() = this@LicensesHingeUiTest.rule }

    private fun hinged(manifest: LicenseManifest) {
        val start = with(rule.density) { 320.dp.toPx() }
        val gap = with(rule.density) { 16.dp.toPx() }
        rule.setContent { FestivalTheme(appReduceMotion = true) { LicensesContent(manifest, wide = true, hinge = start to gap) } }
        h.settle()
    }

    @Test
    fun hingeSplitsListAndDetail() {
        hinged(MANIFEST)
        h.waitFor("fst.licenses.detail-pane")
        val list = rule.onNodeWithTag("fst.licenses.list").getUnclippedBoundsInRoot()
        val pane = rule.onNodeWithTag("fst.licenses.detail-pane").getUnclippedBoundsInRoot()
        assertEquals(320f, list.right.value, 1f)
        // Hinge (320–336 dp) plus the pane's 16 dp leading padding.
        assertEquals(352f, pane.left.value, 1f)
        rule.onNodeWithTag(FIRST).assertIsSelected()
    }

    @Test
    fun hingeWithoutPackagesShowsTheEmptyDetail() {
        hinged(LicenseManifest())
        h.waitFor("fst.licenses.detail-empty")
    }
}

// endregion
