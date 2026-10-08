package com.festivalscoretracker.android.journeys

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.text.TextLayoutResult
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * CHOpt Paths sheet on a real device (issue #130): ATF over the warning, image, zoom, text,
 * missing and switch states, TalkBack's reading order per state (logcat `FST_A11Y`), the
 * bottom controls and panels clear of a separating hinge, and no clipped text. Run with
 * `device.py test com.festivalscoretracker.android.journeys.SongPathsDeviceTest --avd <AVD> [--posture half]`.
 */
@RunWith(AndroidJUnit4::class)
class SongPathsDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val controls = arrayOf("fst.paths.instrument.open", "fst.paths.difficulty.open", "fst.paths.display.open")

    private fun png(): ByteArray {
        val bitmap = Bitmap.createBitmap(400, 1_200, Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.WHITE) }
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        val image = png()
        onRaw("/api/paths/s-alpha/Solo_Guitar/expert") { HttpResult(200, image, mapOf("X-FST-Publication-Id" to "7")) }
        on("/api/paths/s-alpha/Solo_Guitar/expert/data", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.pathJson }
        ProfileFixtures.register(this)
    }

    /** Karaoke visible: the sheet opens with its warning. */
    private val preferences
        get() = MemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.VISIBLE_INSTRUMENTS) to "Solo_Guitar,Solo_Bass,Solo_PeripheralVocals"))

    private fun open() {
        h.launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true), transport, preferences)
        h.waitForTag("fst.song-detail.list")
        h.tap("fst.song-detail.paths.open")
        h.waitForTag("fst.paths.karaoke-warning")
    }

    /**
     * No text inside the sheet is cut off: every line fits the node's width, the paragraph its
     * height, and nothing is ellipsized. `TextLayoutResult.hasVisualOverflow` is not used: for a
     * plain `Text` the semantics action re-lays out at the parent's max width, so any
     * wrap-content label (e.g. the zoom "100%") reads as overflowing.
     */
    private fun assertNoClippedText(state: String) {
        val texts = rule.onAllNodes(
            hasAnyAncestor(hasTestTag("fst.song-detail.paths")) and SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult),
            useUnmergedTree = true,
        )
        texts.fetchSemanticsNodes().indices.forEach { i ->
            val layouts = mutableListOf<TextLayoutResult>()
            texts[i].performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val text = texts[i].fetchSemanticsNode().config.getOrElseNullable(SemanticsProperties.Text) { null }?.joinToString().orEmpty()
            layouts.forEach { layout ->
                val lines = 0 until layout.lineCount
                assertFalse("$state: \"$text\" is wider than its box", lines.any { layout.getLineRight(it) - layout.getLineLeft(it) > layout.size.width + 1 })
                assertFalse("$state: \"$text\" is taller than its box", layout.multiParagraph.height > layout.size.height + 1)
                assertFalse("$state: \"$text\" is ellipsized", lines.any { layout.isLineEllipsized(it) })
            }
        }
    }

    @Test
    fun everyStateIsAccessibleAndClearOfTheHinge() {
        h.enableAccessibilityChecks()
        open()
        h.readingOrder("paths-warning")
        h.tap("fst.paths.warning.ok")
        h.waitGone("fst.paths.karaoke-warning")

        // image-loaded and zoomed.
        h.waitForTag("fst.paths.image")
        h.waitForTag("fst.paths.zoom-in")
        h.readingOrder("paths-image")
        h.assertNothingStraddles(*controls, "fst.paths.zoom-in", "fst.paths.zoom-out")
        assertNoClippedText("image")
        h.tap("fst.paths.zoom-in")
        h.tap("fst.paths.zoom-in")
        h.readingOrder("paths-zoomed")

        // Display panel, then text-loaded.
        h.tap("fst.paths.display.open")
        h.waitForTag("fst.paths.display.text")
        h.readingOrder("paths-display-panel")
        h.assertNothingStraddles("fst.paths.display.image", "fst.paths.display.text")
        h.tap("fst.paths.display.text")
        h.waitForTag("fst.paths.row.3")
        h.readingOrder("paths-text")
        h.assertNothingStraddles(*controls)
        assertNoClippedText("text")

        // difficulty-switch to a missing path.
        h.tap("fst.paths.difficulty.open")
        h.waitForTag("fst.paths.difficulty.hard")
        h.readingOrder("paths-difficulty-panel")
        h.assertNothingStraddles("fst.paths.difficulty.easy", "fst.paths.difficulty.medium", "fst.paths.difficulty.hard", "fst.paths.difficulty.expert")
        h.tap("fst.paths.difficulty.hard")
        h.waitForTag("fst.paths.not-generated")
        h.readingOrder("paths-missing")
        assertNoClippedText("missing")

        // instrument-switch: the shared selector is a carousel on compact sheets, a grid otherwise.
        h.tap("fst.paths.instrument.open")
        rule.waitUntil(15_000) { h.exists("fst.paths.instrument.compact") || h.exists("fst.paths.instrument.Solo_Guitar") }
        h.readingOrder("paths-instrument-panel")
        if (h.exists("fst.paths.instrument.compact")) {
            h.assertNothingStraddles("fst.paths.instrument.previous", "fst.paths.instrument.preview", "fst.paths.instrument.next")
            h.tap("fst.paths.instrument.next")
            h.waitForTag("fst.paths.not-generated")
        } else {
            h.assertNothingStraddles("fst.paths.instrument.Solo_Guitar")
            h.tap("fst.paths.instrument.Solo_Bass")
            h.waitForTag("fst.paths.not-generated")
        }
        h.tap("fst.paths.close")
        h.waitGone("fst.paths.close")
        assertTrue(h.exists("fst.song-detail.paths.open"))
        h.assertAccessible()
    }

    /** Karaoke hidden and Text saved as the default view: the sheet opens straight on the cards. */
    private val textPreferences
        get() = MemoryPreferences(
            mutablePreferencesOf(
                stringPreferencesKey(SettingsRegistry.VISIBLE_INSTRUMENTS) to "Solo_Guitar,Solo_Bass",
                stringPreferencesKey(SettingsRegistry.PATH_DEFAULT_VIEW) to PathDisplayMode.Text.token,
            ),
        )

    /**
     * Issue #289 (tracker #384): on a half-open book fold `FestivalModalSheet` keeps the whole
     * Paths sheet on one side of the hinge, at 100% and 200% text. At each size the sheet, its
     * Close, the first card, the control row and the difficulty options straddle nothing;
     * TalkBack reads "Paths" → Close → the cards → the controls (Difficulty first when the
     * row stacks), with the open difficulty panel's Easy…Expert between the cards and the
     * controls; the card grows at 200% (the scale reaches the sheet's window); no text is
     * clipped; and ATF (labels, 48 dp targets, contrast) finds no errors.
     * On a device without a separating hinge the straddle checks pass trivially, so run it with
     * `--avd FST_Book_Fold --posture half`.
     */
    @Test
    fun halfOpenSheetStaysOnOneSideAndReadsInOrderAtEveryTextSize() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true), transport, textPreferences, fontScale = { scale })
        h.waitForTag("fst.song-detail.list")
        val cardHeights = mutableListOf<Float>()
        listOf(1f, 2f).forEach { s ->
            scale = s
            rule.waitForIdle()
            val config = "text ${(s * 100).toInt()}%"
            h.tap("fst.song-detail.paths.open")
            h.waitForTag("fst.paths.row.1")
            h.awaitAccessibilityTree("fst.paths.row.1", absent = "fst.song-detail.paths.open")
            h.assertNothingStraddles("fst.song-detail.paths", "fst.paths.close", "fst.paths.row.1", "fst.paths.selectors", *controls)
            cardHeights += rule.onNodeWithTag("fst.paths.row.1").fetchSemanticsNode().size.height.toFloat()

            val order = h.readingOrder("paths-fold-$config")
            val heading = order.indexOf("Paths")
            val close = order.indexOf("Close")
            val card = order.indexOfFirst { it.startsWith("Activation 1:") }
            val instrument = order.indexOfFirst { it.startsWith("Instrument:") }
            val difficulty = order.indexOfFirst { it.startsWith("Difficulty:") }
            val view = order.indexOfFirst { it.startsWith("View:") }
            val stacked = h.exists("fst.paths.selectors.stacked")
            val controlsInOrder = if (stacked) difficulty in (card + 1) until instrument else instrument in (card + 1) until difficulty
            assertTrue(
                "$config: reading order $order",
                heading >= 0 && close > heading && card > close && controlsInOrder && view > maxOf(instrument, difficulty),
            )
            assertNoClippedText(config)

            h.tap("fst.paths.difficulty.open")
            h.waitForTag("fst.paths.difficulty.expert")
            h.awaitAccessibilityTree("fst.paths.difficulty.expert")
            h.assertNothingStraddles("fst.paths.difficulty.easy", "fst.paths.difficulty.medium", "fst.paths.difficulty.hard", "fst.paths.difficulty.expert")
            // The panel opens above the control row: cards, then Easy…Expert, then the controls.
            val panel = h.readingOrder("paths-fold-difficulty-$config")
            val options = listOf("Easy", "Medium", "Hard", "Expert").map { option -> panel.indexOfFirst { it.startsWith(option) } }
            val panelFirstControl = panel.indexOfFirst { it.startsWith(if (stacked) "Difficulty:" else "Instrument:") }
            assertTrue(
                "$config: difficulty panel reading order $panel",
                options.first() > panel.indexOfFirst { it.startsWith("Activation 1:") } && options.zipWithNext().all { (a, b) -> b > a } &&
                    options.last() < panelFirstControl,
            )
            assertNoClippedText("$config difficulty panel")

            h.tap("fst.paths.close")
            h.waitGone("fst.paths.close")
            h.awaitAccessibilityTree("fst.song-detail.paths.open", absent = "fst.paths.row.1")
        }
        assertTrue("200% text reaches the sheet: card heights $cardHeights", cardHeights[1] > cardHeights[0])
        h.assertAccessible()
    }

    /** Drag from [tag]'s centre past the bottom of the screen, as a finger pulls the sheet away. */
    private fun swipeSheetDownFrom(tag: String) {
        rule.onNodeWithTag(tag).performTouchInput {
            swipeDown(startY = centerY, endY = centerY + rule.activity.window.decorView.height, durationMillis = 300)
        }
        h.waitGone("fst.paths.close")
        assertTrue(h.exists("fst.song-detail.paths.open"))
    }

    /** Issues #96/#192: swiping the sheet down closes it in image and text modes instead of bouncing back. */
    @Test
    fun swipeDownDismissesInImageAndTextModes() {
        open()
        h.tap("fst.paths.warning.ok")
        h.waitForTag("fst.paths.image")
        swipeSheetDownFrom("fst.paths.image")

        h.tap("fst.song-detail.paths.open")
        h.tap("fst.paths.warning.ok")
        h.tap("fst.paths.display.open")
        h.tap("fst.paths.display.text")
        h.waitForTag("fst.paths.row.3")
        swipeSheetDownFrom("fst.paths.row.1")
    }
}
