package com.festivalscoretracker.android.ui.design

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.format.DifficultyMeterSpec
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The difficulty meter's reachable states (`.agents/controls/difficulty-meter/spec.md`):
 * `one` … `seven` drawn as filled/unfilled parallelograms with one image-like TalkBack
 * element, and `invalid` as readable "Difficulty unavailable" text (issue #123).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class DifficultyMeterUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val backdrop = Color.Black

    /** Raw service values 0–6 (one … seven) on a known backdrop, each tagged by state. */
    private fun showRawStates() {
        rule.setContent {
            FestivalTheme {
                Column {
                    (0..6).forEach { raw ->
                        Box(Modifier.background(backdrop).padding(4.dp).testTag("state.${raw + 1}")) { DifficultyMeter(raw.toDouble()) }
                    }
                }
            }
        }
        rule.waitForIdle()
    }

    private fun meterIn(state: Int) = rule.onNodeWithTag("state.$state", useUnmergedTree = true)
        .fetchSemanticsNode().children.single()

    @Test
    fun everyRawLevelIsOneImageLikeElementWithItsSpokenLevel() {
        showRawStates()
        val meters = rule.onAllNodesWithTag("fst.songs.difficulty-meter", useUnmergedTree = true).fetchSemanticsNodes()
        assertEquals(7, meters.size)
        (1..7).forEach { level ->
            val node = meterIn(level)
            assertEquals("fst.songs.difficulty-meter", node.config[SemanticsProperties.TestTag])
            assertEquals(listOf("Difficulty $level of 7"), node.config[SemanticsProperties.ContentDescription])
            assertEquals(Role.Image, node.config.getOrNull(SemanticsProperties.Role))
            // Decorative polygons are drawn, never separate nodes.
            assertTrue(node.children.isEmpty())
        }
        rule.onAllNodesWithTag("fst.songs.difficulty-meter", useUnmergedTree = true).fetchSemanticsNodes().forEach { node ->
            assertEquals(62f * 3, node.size.width.toFloat(), 0.5f)
            assertEquals(20f * 3, node.size.height.toFloat(), 0.5f)
        }
    }

    @Test
    fun everyRawLevelFillsThatManyBarsInBrandColours() {
        showRawStates()
        val filled = Color(DifficultyMeterSpec.FILLED).toArgb()
        val unfilled = Color(DifficultyMeterSpec.UNFILLED).toArgb()
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        val density = 3f
        (1..7).forEach { level ->
            val origin = meterIn(level).positionInWindow
            fun at(x: Float) = bitmap.getPixel((origin.x + x * density).toInt(), (origin.y + 10 * density).toInt())
            (0 until DifficultyMeterSpec.BARS).forEach { bar ->
                // Each parallelogram's centre (x + 4, 10) is solid; the unit gap (x + 8.5, 10) shows the backdrop.
                assertEquals("level $level bar $bar", if (bar < level) filled else unfilled, at(bar * 9 + 4f))
                if (bar < DifficultyMeterSpec.BARS - 1) assertEquals("level $level gap $bar", backdrop.toArgb(), at(bar * 9 + 8.5f))
            }
        }
    }

    @Test
    fun displayLevelsKeepTheirFractionAndRawExtremesClamp() {
        rule.setContent {
            FestivalTheme {
                Column {
                    Box(Modifier.testTag("display")) { DifficultyMeter(3.5, raw = false) }
                    Box(Modifier.testTag("high")) { DifficultyMeter(99.0) }
                    Box(Modifier.testTag("low")) { DifficultyMeter(-3.0) }
                }
            }
        }
        rule.waitForIdle()
        fun spoken(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().children.single()
            .config[SemanticsProperties.ContentDescription]
        assertEquals(listOf("Difficulty 3.5 of 7"), spoken("display"))
        assertEquals(listOf("Difficulty 7 of 7"), spoken("high"))
        assertEquals(listOf("Difficulty 1 of 7"), spoken("low"))
    }

    @Test
    fun nonFiniteLevelsReadDifficultyUnavailableInsteadOfAFakeLevel() {
        rule.setContent {
            FestivalTheme {
                Column {
                    DifficultyMeter(Double.NaN)
                    DifficultyMeter(Double.POSITIVE_INFINITY, raw = false)
                }
            }
        }
        rule.waitForIdle()
        assertEquals(0, rule.onAllNodesWithTag("fst.songs.difficulty-meter", useUnmergedTree = true).fetchSemanticsNodes().size)
        val invalid = rule.onAllNodesWithTag("fst.songs.difficulty-unavailable", useUnmergedTree = true).fetchSemanticsNodes()
        assertEquals(2, invalid.size)
        invalid.forEach { assertEquals("Difficulty unavailable", it.config[SemanticsProperties.Text].single().text) }
    }

    @Test
    @Config(fontScale = 2.0f)
    fun atDoubleTextTheMeterKeepsItsGeometryAndUnavailableWrapsUnclipped() {
        rule.setContent {
            FestivalTheme {
                Column {
                    DifficultyMeter(3.0)
                    // A narrow Song Detail cell: the text wraps rather than clipping.
                    Box(Modifier.width(96.dp)) { DifficultyMeter(Double.NaN) }
                }
            }
        }
        rule.waitForIdle()
        rule.onNodeWithTag("fst.songs.difficulty-meter", useUnmergedTree = true).assertWidthIsEqualTo(62.dp).assertHeightIsEqualTo(20.dp)
        val layouts = mutableListOf<TextLayoutResult>()
        rule.onNodeWithTag("fst.songs.difficulty-unavailable", useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        val layout = layouts.single()
        assertTrue("wraps at 2.0", layout.lineCount > 1)
        assertFalse("not clipped", layout.hasVisualOverflow)
    }

    // region Songs filter intensity buckets

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String) {
        try {
            rule.waitUntil(20_000) {
                settle(100)
                rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
            }
        } catch (timeout: ComposeTimeoutException) {
            throw AssertionError("Timed out waiting for $tag", timeout)
        }
    }

    @Test
    fun songIntensityFilterRowsSpeakTheirLevelOnce() {
        val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
            on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "7")) {
                """{"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":0,"scores":[]}"""
            }
        }
        // A saved hidden "No intensity" bucket opens the Song Intensity group.
        val prefs = InMemoryPreferences(
            mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_FILTERS) to """{"instrument":"Solo_Guitar","excludedIntensities":[0]}"""),
        )
        val debug = DebugLaunch(profile = player, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = prefs)
        rule.setContent { FestivalApp(container, debug) }
        settle()
        waitForTag("fst.songs.row.s-alpha")
        rule.onNodeWithTag("fst.songs.filter.open").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        (1..7).forEach { level ->
            val tag = "fst.songs.filter.intensity.$level"
            rule.onNodeWithTag("fst.songs.filter.form").performScrollToNode(hasTestTag(tag))
            val row = rule.onNodeWithTag(tag).fetchSemanticsNode()
            assertEquals(listOf("Intensity $level of 7"), row.config[SemanticsProperties.ContentDescription])
            assertEquals(Role.Switch, row.config[SemanticsProperties.Role])
            assertEquals(ToggleableState.On, row.config[SemanticsProperties.ToggleableState])
        }
        rule.onNodeWithTag("fst.songs.filter.form").performScrollToNode(hasTestTag("fst.songs.filter.intensity.0"))
        val none = rule.onNodeWithTag("fst.songs.filter.intensity.0").fetchSemanticsNode()
        assertEquals(listOf("No Score"), none.config[SemanticsProperties.ContentDescription])
        assertEquals(ToggleableState.Off, none.config[SemanticsProperties.ToggleableState])
        // The handle hosting the sheet's collapse/dismiss actions keeps a 48 dp touch target.
        rule.onNode(hasContentDescription("drag handle", substring = true, ignoreCase = true))
            .assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
    }

    // endregion

    // region Song Detail Intensity card

    /**
     * Phone landscape at font scale 2.0 (FST_Phone finding): labelled Intensity cells keep
     * at least 8 dp between the instrument label's glyphs and the right-aligned meter. The
     * 870 dp width puts Robolectric's "Pro Drums + Cymbals" within 4 dp of the meter without
     * the end gap, as the device rendered it at 891 dp.
     */
    @Test
    @Config(qualifiers = "w870dp-h411dp-xxhdpi", fontScale = 2.0f)
    fun songDetailIntensityLabelsKeepAGapBeforeTheirMeter() {
        val debug = DebugLaunch(songQuery = "s-alpha", stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = FakeTransport.standard(), settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        settle()
        val cymbals = "fst.song-detail.intensity.Solo_PeripheralCymbals"
        rule.waitUntil(20_000) { settle(100); rule.onAllNodesWithTag(cymbals, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag(cymbals))
        settle()
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        val density = 3f
        val isCell = SemanticsMatcher("Intensity cell") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.song-detail.intensity.") == true }
        val cells = rule.onAllNodes(isCell, useUnmergedTree = true).fetchSemanticsNodes()
            .filter { it.boundsInWindow.width >= 200 * 3f && it.boundsInWindow.height >= 28 * 3f }
        assertTrue("labelled cells on screen", cells.size >= 2)
        val gaps = cells.associate { cell ->
            val bounds = cell.boundsInWindow
            val meterLeft = (bounds.right - 62 * density).toInt()
            val labelStart = (bounds.left + 38 * density).toInt()
            val top = bounds.top.toInt().coerceAtLeast(0)
            val bottom = bounds.bottom.toInt().coerceAtMost(bitmap.height)
            var rightmostGlyph = labelStart
            for (x in labelStart until meterLeft) for (y in top until bottom) {
                val p = bitmap.getPixel(x, y)
                if (android.graphics.Color.red(p) > 180 && android.graphics.Color.green(p) > 180 && android.graphics.Color.blue(p) > 180) rightmostGlyph = maxOf(rightmostGlyph, x)
            }
            cell.config[SemanticsProperties.ContentDescription].single() to (meterLeft - rightmostGlyph) / density
        }
        assertTrue("label-to-meter gaps (dp): $gaps", gaps.values.all { it >= 8f })
    }

    // endregion
}
