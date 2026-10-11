package com.festivalscoretracker.android.ui.quicklinks

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Looper
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Toc
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.VectorGroup
import androidx.compose.ui.graphics.vector.VectorPath
import androidx.compose.ui.graphics.vector.toPath
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.RivalDetailRoute
import com.festivalscoretracker.android.core.rivals.RivalCategorization
import com.festivalscoretracker.android.core.rivals.RivalQuickLinks
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Issue #605, pattern `quick-links` R9: Rival Detail's chooser draws each category row's own
 * Material glyph, on rendered pixels. The phone sheet and the wide menu are drawn in software;
 * each row's leading icon is cut out, reduced to its ink and matched against every candidate
 * glyph rasterised from its [ImageVector] paths at the same size: the six category glyphs, the
 * generic `Toc` fallback and the Rivals `people` icon. Each row must best match its assigned
 * glyph (so an absent, generic or swapped icon fails) and the rows must differ from each other.
 * Accessibility (decorative icons, names, order, 48 dp) is the ATF journey
 * `PlayerAccessibilityJourneyTest.rivalDetailQuickLinksIconsAreDecorative`.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RivalDetailQuickLinkIconsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Tests

    /** Phone: the floating-toolbar sheet. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun sheetRowsDrawTheirCategoryGlyphs() = assertRowsDrawTheirGlyphs(SHEET)

    /** Wide window: the top-app-bar menu. */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun menuRowsDrawTheirCategoryGlyphs() = assertRowsDrawTheirGlyphs(MENU)

    // endregion

    // region Check

    private fun assertRowsDrawTheirGlyphs(container: String) {
        launch()
        waitForTag(OPEN)
        rule.onNodeWithTag(OPEN).performSemanticsAction(SemanticsActions.OnClick)
        waitForTag(container)
        settle(1_200)
        val rows = rule.onAllNodes(categoryRow).fetchSemanticsNodes()
            .sortedBy { it.positionInRoot.y }
            .map { it.config[SemanticsProperties.TestTag].removePrefix(ROW_PREFIX) }
        assertEquals("$container: one row per category, in page order", RivalCategorization.keys, rows)

        val window = drawTopWindow()
        val candidates = (rows.map(RivalQuickLinks::categoryIcon) + listOf(null, RivalQuickLinks.FALLBACK_CATEGORY_ICON))
            .associate { token -> (token ?: "toc") to quickLinkIcon(token) }
        assertEquals("the generic fallback is Toc", Icons.AutoMirrored.Outlined.Toc.name, candidates.getValue("toc").name)

        val drawn = rows.map { key ->
            val bounds = rule.onNode(hasTestTag(QUICK_LINK_ICON_TAG) and hasAnyAncestor(hasTestTag("$ROW_PREFIX$key")), useUnmergedTree = true)
                .fetchSemanticsNode().boundsInRoot
            val ink = renderedInk(window, bounds, "$container $key")
            val references = candidates.mapValues { (_, icon) -> referenceInk(icon, ink.width, ink.height) }
            references.values.forEach { assertTrue("$container: a reference glyph rasterised empty", it.count > 0) }
            val scores = references.mapValues { (_, ref) -> ink.iou(ref) }
            val assigned = RivalQuickLinks.categoryIcon(key)
            val best = scores.maxBy { it.value }
            assertEquals("$container: $key draws ${best.key}, not its $assigned glyph ($scores)", assigned, best.key)
            assertTrue("$container: $key's $assigned glyph is only a loose match ($scores)", best.value >= MATCH)
            val runnerUp = scores.filterKeys { it != assigned }.values.max()
            assertTrue("$container: $key's glyph is ambiguous ($scores)", best.value - runnerUp >= MARGIN)
            key to ink
        }
        // Rows differ from each other on screen, not only in the model.
        drawn.forEachIndexed { i, (a, inkA) ->
            drawn.drop(i + 1).forEach { (b, inkB) ->
                val overlap = inkA.iou(inkB)
                assertTrue("$container: $a and $b draw near-identical icons ($overlap)", overlap < SAME)
            }
        }
    }

    // endregion

    // region Harness

    private fun launch() {
        val transport = RivalsFixtures.transport().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        val debug = DebugLaunch(route = RivalDetailRoute(RivalsFixtures.RIVALS[1]), profile = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player"), stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String) = rule.waitUntil(10_000) {
        settle(100)
        rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    }

    private val categoryRow = SemanticsMatcher("Rival Detail category row") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(ROW_PREFIX) == true }

    /**
     * The topmost window (the sheet's dialog or the menu's popup), drawn in software:
     * Robolectric's `captureToImage` never gets a frame (precedent `SongPathsSheetUiTest`).
     */
    private fun drawTopWindow(): Bitmap {
        val global = Class.forName("android.view.WindowManagerGlobal")
        val instance = global.getMethod("getInstance").invoke(null)
        @Suppress("UNCHECKED_CAST")
        val window = (global.getDeclaredField("mViews").apply { isAccessible = true }.get(instance) as List<View>).last()
        val whole = Bitmap.createBitmap(window.width, window.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { window.draw(Canvas(whole)) }
        return whole
    }

    // endregion

    // region Ink masks

    /** Which pixels of a glyph-sized box are ink. */
    private class Ink(val width: Int, val height: Int, val on: BooleanArray) {
        val count: Int get() = on.count { it }

        /** Intersection over union with [other] (same size). */
        fun iou(other: Ink): Double {
            var both = 0
            var either = 0
            for (i in on.indices) {
                if (on[i] && other.on[i]) both++
                if (on[i] || other.on[i]) either++
            }
            return if (either == 0) 0.0 else both.toDouble() / either
        }
    }

    /**
     * The icon's ink in the drawn window: pixels at least halfway from the box's dominant
     * background colour to its strongest contrast (the icon tint), whatever the row's fill.
     */
    private fun renderedInk(window: Bitmap, bounds: Rect, what: String): Ink {
        val left = bounds.left.roundToInt()
        val top = bounds.top.roundToInt()
        val width = bounds.width.roundToInt()
        val height = bounds.height.roundToInt()
        assertTrue("$what's icon is off the window ($bounds)", left >= 0 && top >= 0 && left + width <= window.width && top + height <= window.height && width > 0 && height > 0)
        val pixels = IntArray(width * height)
        window.getPixels(pixels, 0, width, left, top, width, height)
        val background = pixels.groupBy { it }.maxBy { it.value.size }.key
        val distance = pixels.map { colourDistance(it, background) }
        val strongest = distance.max()
        assertTrue("$what draws no icon (strongest contrast $strongest)", strongest >= MIN_CONTRAST)
        return Ink(width, height, BooleanArray(pixels.size) { distance[it] * 2 >= strongest })
    }

    private fun colourDistance(a: Int, b: Int): Int = max(
        abs(android.graphics.Color.red(a) - android.graphics.Color.red(b)),
        max(abs(android.graphics.Color.green(a) - android.graphics.Color.green(b)), abs(android.graphics.Color.blue(a) - android.graphics.Color.blue(b))),
    )

    /** [icon] filled from its vector paths at [width] x [height] px; ink is half coverage or more. */
    private fun referenceInk(icon: ImageVector, width: Int, height: Int): Ink {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.scale(width / icon.viewportWidth, height / icon.viewportHeight)
        val paint = Paint().apply { isAntiAlias = true; color = android.graphics.Color.BLACK; style = Paint.Style.FILL }
        fun draw(group: VectorGroup) {
            group.forEach { node ->
                when (node) {
                    is VectorGroup -> draw(node)
                    is VectorPath -> {
                        val path = node.pathData.toPath()
                        path.fillType = if (node.pathFillType == PathFillType.EvenOdd) PathFillType.EvenOdd else PathFillType.NonZero
                        canvas.drawPath(path.asAndroidPath(), paint)
                    }
                }
            }
        }
        draw(icon.root)
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        return Ink(width, height, BooleanArray(pixels.size) { android.graphics.Color.alpha(pixels[it]) >= 128 })
    }

    // endregion

    private companion object {
        const val OPEN = "fst.quick-links.open"
        const val SHEET = "fst.quick-links.sheet"
        const val MENU = "fst.quick-links.menu"
        const val ROW_PREFIX = "fst.quick-links.item.rival-category:"

        /** Least contrast (max channel difference) that counts as a drawn icon. */
        const val MIN_CONTRAST = 40

        /** Least overlap with the assigned glyph. */
        const val MATCH = 0.6

        /** Least lead of the assigned glyph over the next candidate. */
        const val MARGIN = 0.1

        /** Overlap at which two rows count as the same icon. */
        const val SAME = 0.8
    }
}
