package com.festivalscoretracker.android.ui.songs

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertTouchHeightIsEqualTo
import androidx.compose.ui.test.assertTouchWidthIsEqualTo
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.shop.ShopSong
import com.festivalscoretracker.android.core.songs.InvalidScoreReason
import com.festivalscoretracker.android.core.songs.InvalidScoreWarning
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongRowModel
import com.festivalscoretracker.android.core.songs.SongRowProjector
import com.festivalscoretracker.android.core.songs.SongScoreDetail
import com.festivalscoretracker.android.core.songs.SongScoreSource
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The selected-player Songs metadata control (`fst.songs.metadata.*`,
 * `.agents/controls/song-score-metadata/android.md`): one test per reachable Android state of
 * the contract — anonymous, loading/syncing/failed/paused, no score, primary Score or
 * Accuracy, FC, graded and missing accuracy, percentile tiers, stars, seasons, intensity,
 * game difficulty, Last Played, named non-Lead chart, filtered chart, Filter Invalid Scores,
 * the Shop badge, narrow/regular widths, 2.0 text, a pane-width change and contrast.
 * Wrapping at real glyph widths is proven on the emulator (`SongScoreMetadataDeviceTest`).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w880dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SongScoreMetadataUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Fixtures

    private val song: Song = Fixtures.song("s-meta", "Metadata Song", artist = "Band One", year = 2021, duration = 185, lead = 3.0)

    private val player = AppSettings(
        selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"),
        showInstrumentIcons = false,
    )

    private val full = SongScoreDetail(
        score = 1_234_567,
        accuracy = 987_000.0,
        isFullCombo = false,
        stars = 5,
        season = 15,
        difficulty = 3.0,
        rank = 30,
        totalEntries = 1_000,
        lastPlayedAt = "2026-09-01T12:00:00Z",
    )

    private fun source(
        detail: SongScoreDetail?,
        chart: Instrument? = null,
        invalid: Map<Instrument, InvalidScoreReason> = emptyMap(),
    ) = SongScoreSource(
        hasPlayer = true,
        detail = { id, c -> if (id == song.songId && (chart == null || c == chart)) detail else null },
        invalid = { invalid },
    )

    private fun project(
        scores: SongScoreSource,
        settings: AppSettings = player,
        filter: SongFilter = SongFilter(),
        sort: SongSortMode = SongSortMode.Title,
        offers: Map<String, ShopSong>? = null,
        target: Song = song,
    ): SongRowModel = SongRowProjector(settings, filter, 15, offers, scores, sort, locale = Locale.US).project(target)

    // endregion

    // region Helpers

    private var shownRows by mutableStateOf(emptyList<SongRowModel>())
    private var shownWidth by mutableStateOf(400)
    private var shownScale by mutableStateOf(1f)
    private var shownWarning by mutableStateOf<(() -> Unit)?>(null)
    private var composed = false

    /** Shows [rows]; later calls swap state in the one composition (a rule sets content once). */
    private fun show(vararg rows: SongRowModel, width: Int = 400, fontScale: Float = 1f, onWarning: (() -> Unit)? = null) {
        shownRows = rows.toList()
        shownWidth = width
        shownScale = fontScale
        shownWarning = onWarning
        if (!composed) {
            composed = true
            rule.setContent {
                FestivalTheme {
                    val density = LocalDensity.current
                    CompositionLocalProvider(LocalDensity provides Density(density.density, shownScale)) {
                        Column(Modifier.width(shownWidth.dp)) {
                            shownRows.forEach { key(it.song.songId, it) { SongRow(it, artUrl = null, onWarning = shownWarning, onClick = {}) } }
                        }
                    }
                }
            }
        }
        rule.waitForIdle()
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot

    private fun announcement(id: String = song.songId): String =
        rule.onNodeWithTag("fst.songs.row.$id").fetchSemanticsNode().config[SemanticsProperties.ContentDescription].single()

    /** Visible text of the tagged node and its descendants. */
    private fun text(tag: String): String {
        fun gather(node: SemanticsNode): String =
            (node.config.getOrNull(SemanticsProperties.Text)?.joinToString("") { it.text } ?: "") + node.children.joinToString("") { gather(it) }
        return gather(rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode())
    }

    /** Whether all tagged pills share one line (their vertical extents overlap). */
    private fun oneLine(tags: List<String>): Boolean {
        val rects = tags.map { bounds(it) }
        return rects.maxOf { it.top } < rects.minOf { it.bottom }
    }

    private fun layout(tag: String): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action!!.invoke(results)
        return results.single()
    }

    private fun pillTag(field: String, id: String = song.songId) = "fst.songs.metadata.$field.$id"

    /** Every rendered pill tag of the row, in projection order. */
    private fun pillTags(row: SongRowModel) = row.metadata.map { pillTag(it.kind.name.lowercase(), row.song.songId) }

    /** The rendered pixels, drawn in software (Robolectric's `captureToImage` never gets a frame). */
    private fun capture(tag: String): Bitmap {
        val view = rule.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
        val whole = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(whole))
        val b = bounds(tag)
        return Bitmap.createBitmap(whole, b.left.toInt(), b.top.toInt(), b.width.toInt().coerceAtLeast(1), b.height.toInt().coerceAtLeast(1))
    }

    private fun hasColour(bitmap: Bitmap, colour: Color, tolerance: Int = 14): Boolean {
        val target = colour.toArgb()
        for (x in 0 until bitmap.width) for (y in 0 until bitmap.height) {
            val p = bitmap.getPixel(x, y)
            if (abs(android.graphics.Color.red(p) - android.graphics.Color.red(target)) <= tolerance &&
                abs(android.graphics.Color.green(p) - android.graphics.Color.green(target)) <= tolerance &&
                abs(android.graphics.Color.blue(p) - android.graphics.Color.blue(target)) <= tolerance
            ) {
                return true
            }
        }
        return false
    }

    private fun contrast(a: Color, b: Color): Double {
        val l1 = a.luminance().toDouble()
        val l2 = b.luminance().toDouble()
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private fun assertInside(inner: Rect, outer: Rect, what: String) {
        assertTrue("$what $inner escapes $outer", inner.left >= outer.left - 1 && inner.right <= outer.right + 1 && inner.top >= outer.top - 1 && inner.bottom <= outer.bottom + 1)
    }

    /** Every rendered pill is inside its card and every text pill lays out without overflow. */
    private fun assertNoClipping(row: SongRowModel) {
        val card = bounds("fst.songs.row.${row.song.songId}")
        pillTags(row).forEach { tag ->
            assertInside(bounds(tag), card, tag)
            val config = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config
            if (config.getOrNull(SemanticsActions.GetTextLayoutResult) != null) {
                // Robolectric reports didOverflowWidth for any text narrower than its constraint, so
                // check that every laid-out line fits the drawn box and nothing is ellipsized instead.
                val result = runCatching { layout(tag) }.getOrElse { throw AssertionError("$tag has no text layout at ${bounds(tag)} in ${bounds("fst.songs.metadata.${row.song.songId}")}", it) }
                assertFalse("$tag clipped vertically", result.didOverflowHeight)
                (0 until result.lineCount).forEach { line ->
                    assertFalse("$tag line $line ellipsized", result.isLineEllipsized(line))
                    val width = result.getLineRight(line) - result.getLineLeft(line)
                    assertTrue("$tag line $line is $width px in a ${result.size.width} px box", width <= result.size.width + 1)
                }
            }
        }
    }

    // endregion

    // region Non-scored states

    @Test
    fun anonymousShowsNoMetadataOrScoreState() {
        val row = project(SongScoreSource.NONE)
        show(row)
        assertFalse(exists("fst.songs.metadata.${song.songId}"))
        assertFalse(exists(pillTag("score")))
        assertFalse(exists("fst.songs.score-state.${song.songId}"))
        assertEquals("Metadata Song, ${song.subtitle}", announcement())
    }

    @Test
    fun loadingSyncingFailedAndPausedAreExplicitText() {
        val states = listOf(
            SongScoreSource.LOADING to "Loading scores",
            SongScoreSource.SYNCING to "Scores syncing",
            SongScoreSource.failed("HTTP 403") to "Scores unavailable",
            SongScoreSource.PAUSED to "Player scores paused until songs update",
        )
        states.forEach { (scores, expected) ->
            val row = project(scores)
            assertTrue(row.metadata.isEmpty())
            show(row)
            assertEquals(expected, text("fst.songs.score-state.${song.songId}"))
            assertFalse(exists(pillTag("score")))
            assertTrue(announcement().endsWith(expected))
        }
        // The paused state carries the gold pause glyph and gold text, not only words.
        show(project(SongScoreSource.PAUSED))
        assertTrue(hasColour(capture("fst.songs.score-state.${song.songId}"), BrandTokens.gold))
    }

    @Test
    fun zeroScoreAndMissingChartShowExplicitStatesWithTheIntensityMeter() {
        val zero = project(source(SongScoreDetail(0)))
        show(zero)
        assertEquals("No score", text("fst.songs.score-state.${song.songId}"))
        assertFalse(exists("fst.songs.metadata.${song.songId}"))
        assertTrue(announcement().contains("Lead, "))
        assertTrue(announcement().endsWith("No score"))

        val keysOnly = song.copy(difficulty = song.difficulty!!.copy(bass = null))
        val missing = project(source(full, chart = Instrument.Lead), settings = player.copy(visibleInstruments = setOf(Instrument.Bass)), target = keysOnly)
        show(missing)
        assertEquals("No Bass chart", text("fst.songs.score-state.${song.songId}"))
        assertNull(missing.chartRaw)
    }

    // endregion

    // region Primary value and fields

    @Test
    fun scoreIsThePrimaryTopTrailingTabularValue() {
        val row = project(source(full))
        show(row)
        assertEquals(MetadataField.Score, row.metadata.first().kind)
        assertEquals("1,234,567", text(pillTag("score")))
        assertEquals("tnum", layout(pillTag("score")).layoutInput.style.fontFeatureSettings)
        val score = bounds(pillTag("score"))
        val flow = bounds("fst.songs.metadata.${song.songId}")
        val card = bounds("fst.songs.row.${song.songId}")
        assertTrue("Score sits above the wrapped pills", score.bottom <= flow.top + 1)
        assertTrue("Score is trailing", score.left > card.center.x)
        // The wrapped pills are right-aligned to the same trailing edge as the Score.
        val lastRight = pillTags(row).drop(1).maxOf { bounds(it).right }
        assertTrue("Wrapped pills end at the Score edge ($lastRight vs ${score.right})", abs(lastRight - score.right) <= 2f)
        assertTrue(announcement().contains("Score 1,234,567, Accuracy 98.7%, Top 3%, 5 stars, Current season 15, Song intensity 4 of 7, Expert difficulty"))
    }

    @Test
    fun hiddenScoreMakesAccuracyPrimary() {
        val row = project(source(full), settings = player.copy(visibleMetadata = MetadataField.entries.toSet() - MetadataField.Score))
        show(row)
        assertFalse(exists(pillTag("score")))
        assertEquals(MetadataField.Percentage, row.metadata.first().kind)
        val accuracy = bounds(pillTag("percentage"))
        assertTrue("Accuracy is the top value", accuracy.bottom <= bounds("fst.songs.metadata.${song.songId}").top + 1)
    }

    @Test
    fun fullComboShowsGoldFcAccuracy() {
        val row = project(source(full.copy(accuracy = 1_000_000.0, isFullCombo = true)))
        show(row)
        assertEquals("100% FC", text(pillTag("percentage")))
        assertTrue(announcement().contains("Full combo, accuracy 100%"))
        assertTrue(hasColour(capture(pillTag("percentage")), BrandTokens.gold))
    }

    @Test
    fun fcOnlyWhenPercentageHiddenOrAccuracyMissing() {
        val hidden = project(source(full.copy(isFullCombo = true)), settings = player.copy(visibleMetadata = MetadataField.entries.toSet() - MetadataField.Percentage))
        show(hidden)
        assertEquals("FC", text(pillTag("percentage")))
        assertTrue(announcement().contains("Full combo, Top 3%"))

        val missing = project(source(full.copy(accuracy = null, isFullCombo = true)))
        show(missing)
        assertEquals("FC", text(pillTag("percentage")))
        assertTrue(announcement().contains("Full combo, accuracy unavailable"))
    }

    @Test
    fun gradedAccuracyIsTintedAndMissingAccuracyIsAbsent() {
        show(project(source(full.copy(accuracy = 120_000.0))))
        assertEquals("12%", text(pillTag("percentage")))
        assertTrue("Low accuracy is tinted red", capture(pillTag("percentage")).let { b -> (0 until b.width).any { x -> android.graphics.Color.red(b.getPixel(x, b.height / 2)) > android.graphics.Color.green(b.getPixel(x, b.height / 2)) + 20 } })

        val none = project(source(full.copy(accuracy = null, isFullCombo = false)))
        show(none)
        assertFalse(exists(pillTag("percentage")))
        assertFalse(announcement().contains("ccuracy"))
    }

    @Test
    fun percentileTiersUseGoldFillGoldOutlineOrNeutral() {
        show(project(source(full.copy(rank = 1, totalEntries = 1_000))))
        assertEquals("Top 1%", text(pillTag("percentile")))
        val one = capture(pillTag("percentile"))
        assertTrue(hasColour(one, BrandTokens.gold))
        assertTrue(hasColour(one, SongsTokens.darkGlyph, tolerance = 40))

        show(project(source(full.copy(rank = 50, totalEntries = 1_000))))
        assertEquals("Top 5%", text(pillTag("percentile")))
        assertTrue(hasColour(capture(pillTag("percentile")), BrandTokens.gold))

        show(project(source(full.copy(rank = 400, totalEntries = 1_000))))
        assertEquals("Top 40%", text(pillTag("percentile")))
        val ordinary = capture(pillTag("percentile"))
        assertTrue(hasColour(ordinary, BrandTokens.surfaceMuted, tolerance = 8))
        assertFalse(hasColour(ordinary, BrandTokens.gold, tolerance = 8))

        show(project(source(full.copy(rank = null))))
        assertFalse(exists(pillTag("percentile")))
    }

    @Test
    fun starsSpeakTheirCountAndGoldIsDistinct() {
        show(project(source(full.copy(stars = 6))))
        assertTrue(exists(pillTag("stars")))
        assertTrue(announcement().contains("5 gold stars"))
        assertTrue(hasColour(capture(pillTag("stars")), BrandTokens.gold, tolerance = 40))

        // Large text keeps the exact count spoken (Android star images do not scale with text).
        show(project(source(full.copy(stars = 3))), fontScale = 2f)
        assertTrue(announcement().contains("3 stars"))
        assertFalse(announcement().contains("gold"))
    }

    @Test
    fun currentSeasonIsInvertedAndOldSeasonNeutral() {
        show(project(source(full.copy(season = 15))))
        assertEquals("S15", text(pillTag("season")))
        assertTrue(announcement().contains("Current season 15"))
        assertTrue(hasColour(capture(pillTag("season")), BrandTokens.textPrimary, tolerance = 4))

        show(project(source(full.copy(season = 9))))
        assertEquals("S9", text(pillTag("season")))
        assertTrue(announcement().contains("Season 9"))
        assertFalse(announcement().contains("Current season"))
        assertTrue(hasColour(capture(pillTag("season")), BrandTokens.surfaceMuted, tolerance = 8))
    }

    @Test
    fun catalogueIntensityUsesTheChartMeterOnce() {
        val row = project(source(full))
        show(row)
        assertTrue(exists(pillTag("intensity")))
        assertEquals(1, row.metadata.count { it.kind == MetadataField.Intensity })
        assertTrue(announcement().contains("Song intensity 4 of 7"))
    }

    @Test
    fun gameDifficultyGlyphsHaveReadableContrast() {
        val expected = listOf(
            Triple("E", SongsTokens.diffEasy, SongsTokens.darkGlyph),
            Triple("M", SongsTokens.diffMedium, BrandTokens.textPrimary),
            Triple("H", SongsTokens.diffHard, SongsTokens.darkGlyph),
            Triple("X", SongsTokens.diffExpert, BrandTokens.textPrimary),
        )
        expected.forEachIndexed { index, (letter, fill, glyph) ->
            show(project(source(full.copy(difficulty = index.toDouble()))))
            assertEquals(letter, text(pillTag("difficulty")))
            assertTrue(announcement().contains("${listOf("Easy", "Medium", "Hard", "Expert")[index]} difficulty"))
            assertTrue("$letter fill drawn", hasColour(capture(pillTag("difficulty")), fill, tolerance = 6))
            assertTrue("$letter glyph contrast", contrast(fill, glyph) >= 4.5)
        }
        show(project(source(full.copy(difficulty = 1.5))))
        assertFalse(exists(pillTag("difficulty")))
    }

    @Test
    fun lastPlayedLeadsOnlyUnderItsSort() {
        val title = project(source(full), filter = SongFilter(Instrument.Lead))
        assertTrue(title.metadata.none { it.kind == MetadataField.LastPlayed })

        val sorted = project(source(full), filter = SongFilter(Instrument.Lead), sort = SongSortMode.LastPlayed)
        show(sorted)
        assertEquals(MetadataField.LastPlayed, sorted.metadata.first().kind)
        assertEquals("1 Sep 2026", text(pillTag("lastplayed")))
        assertTrue(announcement().contains(", Last played 1 Sep 2026, Score"))
        val date = bounds(pillTag("lastplayed"))
        assertTrue("Date is the top trailing value", date.bottom <= bounds("fst.songs.metadata.${song.songId}").top + 1)

        // Unfiltered Last Played sort: the most recent chart's date beside the title instead.
        val unfiltered = project(source(full), sort = SongSortMode.LastPlayed)
        show(unfiltered)
        assertTrue(exists("fst.songs.last-played.${song.songId}"))
        assertFalse(exists(pillTag("lastplayed")))
        assertTrue(announcement().contains("Last played 1 Sep 2026 on Lead"))
    }

    @Test
    fun nonLeadChartIsShownAndSpoken() {
        val row = project(source(full, chart = Instrument.Bass), settings = player.copy(visibleInstruments = Instrument.entries.toSet() - Instrument.Lead))
        show(row)
        assertEquals("Bass chart", text("fst.songs.metadata.chart.${song.songId}"))
        assertTrue(announcement().contains(", Bass chart, Score 1,234,567"))
    }

    @Test
    fun filteredChartReplacesChipsEvenWithIconsOn() {
        val row = project(source(full, chart = Instrument.Drums), settings = player.copy(showInstrumentIcons = true), filter = SongFilter(Instrument.Drums))
        show(row)
        assertTrue(row.chips.isEmpty())
        assertTrue(exists(pillTag("score")))
        assertEquals("Drums chart", text("fst.songs.metadata.chart.${song.songId}"))
        assertTrue(announcement().contains("Song intensity 2 of 7"))
    }

    @Test
    fun filterInvalidScoresShowsNoValidScoreAndASecondStop() {
        var opened = 0
        val row = project(source(SongScoreDetail(0), invalid = mapOf(Instrument.Lead to InvalidScoreReason.NoFallback)))
        show(row, onWarning = { opened++ })
        assertEquals("No valid score", text("fst.songs.score-state.${song.songId}"))
        assertTrue(announcement(), announcement().endsWith("No valid score, Filtered score"))
        val icon = rule.onNodeWithTag("fst.songs.invalid-score.${song.songId}").fetchSemanticsNode()
        assertEquals(InvalidScoreWarning.LABEL, icon.config[SemanticsProperties.ContentDescription].single())
        // M3 IconButton: a 40 dp container inside a 48 dp minimum interactive (touch and accessibility) target.
        rule.onNodeWithTag("fst.songs.invalid-score.${song.songId}").assertTouchWidthIsEqualTo(48.dp).assertTouchHeightIsEqualTo(48.dp)
        icon.config[SemanticsActions.OnClick].action!!.invoke()
        assertEquals(1, opened)
    }

    @Test
    fun shopBadgeSitsBesideMetadataAndIsSpoken() {
        val offer = ShopSong(song.songId, song.title, song.artist, shopUrl = "https://example.invalid/s", leavingTomorrow = true)
        val row = project(source(full), offers = mapOf(song.songId to offer))
        show(row)
        val badge = bounds("fst.songs.shop-badge.${song.songId}")
        val score = bounds(pillTag("score"))
        assertTrue("Badge is trailing after the Score", badge.left >= score.right - 1)
        assertTrue(announcement().contains("Item Shop: Leaving Tomorrow"))
        assertTrue(exists("fst.songs.metadata.${song.songId}"))
    }

    // endregion

    // region Layout, text size and accessibility

    @Test
    fun narrowWrapsAndRegularFitsOneLine() {
        val row = project(source(full))
        show(row, width = 320)
        assertFalse("Narrow card wraps", oneLine(pillTags(row).drop(1)))
        assertNoClipping(row)

        show(row, width = 840)
        assertTrue("Regular card keeps the pills on one line", oneLine(pillTags(row).drop(1)))
        assertNoClipping(row)
    }

    @Test
    fun doubleTextGrowsWithoutClipping() {
        val row = project(source(full), filter = SongFilter(Instrument.Lead), sort = SongSortMode.LastPlayed)
        show(row, width = 360, fontScale = 2f)
        assertNoClipping(row)
        val flow = bounds("fst.songs.metadata.${song.songId}")
        // The wrapped date stays trailing: its right edge is the flow's right edge.
        val date = bounds(pillTag("lastplayed"))
        assertTrue("Primary date is top-trailing", date.right > bounds("fst.songs.row.${song.songId}").center.x)
        val rightmost = pillTags(row).drop(1).maxOf { bounds(it).right }
        assertTrue("Wrapped pills are right-aligned", abs(rightmost - flow.right) <= 2f)
        assertTitleKeepsRoom()
    }

    @Test
    fun largeTextPrimaryValuesLeaveTheTitleRoom() {
        val score = project(source(full))
        show(score, width = 320, fontScale = 2f)
        assertNoClipping(score)
        assertTitleKeepsRoom()

        val maxed = song.copy(maxScores = mapOf(Instrument.Lead.wireId to 1_300_000))
        val dual = project(source(full), filter = SongFilter(Instrument.Lead), sort = SongSortMode.MaxDistance, target = maxed)
        assertNotNull(dual.maxScore)
        show(dual, width = 360, fontScale = 2f)
        assertTrue(exists("fst.songs.max-score.${song.songId}"))
        assertEquals("1,234,567 / 1,300,000", text("fst.songs.max-score.${song.songId}"))
        assertTitleKeepsRoom()

        // Unfiltered Last Played sort (icons on): the chart icon and date wrap inside half the
        // header, so the title column keeps at least as much width as the date.
        val entry = project(source(full), settings = player.copy(showInstrumentIcons = true), sort = SongSortMode.LastPlayed)
        show(entry, width = 360, fontScale = 2f)
        val date = bounds("fst.songs.last-played.${song.songId}")
        val title = rule.onNode(hasText(song.title), useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("Title column ${date.left - title.left} px vs date ${date.width} px", date.left - title.left >= date.width)
    }

    /** The title column keeps a readable share of the card beside a large primary value. */
    private fun assertTitleKeepsRoom() {
        val card = bounds("fst.songs.row.${song.songId}")
        val title = rule.onNode(hasText(song.title), useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("Title keeps room (${title.width} px of ${card.width} px)", title.width >= card.width * 0.25f)
    }

    @Test
    fun paneWidthChangeRewrapsWithoutClipping() {
        // One composition whose pane narrows (list-detail sidebar opening / window resize).
        val row = project(source(full))
        show(row, width = 840)
        assertTrue(oneLine(pillTags(row).drop(1)))
        show(row, width = 320)
        assertFalse(oneLine(pillTags(row).drop(1)))
        assertNoClipping(row)
        show(row, width = 840)
        assertTrue(oneLine(pillTags(row).drop(1)))
    }

    @Test
    fun rowIsOneTalkBackStopReadingTheFieldsInOrder() {
        val row = project(source(full), settings = player.copy(visibleInstruments = Instrument.entries.toSet() - Instrument.Lead), filter = SongFilter())
        show(row)
        val node = rule.onNodeWithTag("fst.songs.row.${song.songId}").fetchSemanticsNode()
        assertNotNull(node.config.getOrNull(SemanticsActions.OnClick))
        assertTrue(node.boundsInRoot.height >= 48 * 3)
        val spoken = announcement()
        val order = listOf("Metadata Song", "Bass chart", "Score", "Accuracy", "Top", "stars", "season", "Song intensity", "difficulty")
        val positions = order.map { spoken.indexOf(it) }
        assertTrue("All fields spoken: $spoken", positions.none { it < 0 })
        assertEquals("Spoken in visual order: $spoken", positions.sorted(), positions)
        // No pill is its own focus stop: the merged tree exposes only the row.
        assertTrue(rule.onAllNodesWithTag(pillTag("score")).fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun pillTokensMeetContrast() {
        val card = BrandTokens.cardBackground
        assertTrue(contrast(BrandTokens.textPrimary, BrandTokens.surfaceMuted) >= 4.5)
        assertTrue(contrast(SongsTokens.darkGlyph, BrandTokens.gold) >= 4.5)
        assertTrue(contrast(BrandTokens.gold, card) >= 4.5)
        assertTrue(contrast(SongsTokens.darkGlyph, BrandTokens.textPrimary) >= 4.5)
        assertTrue(contrast(BrandTokens.textSecondary, card) >= 4.5)
        // Gold outline (Top 5%) and FC edge stand off the card by at least 3:1.
        assertTrue(contrast(BrandTokens.gold, card) >= 3.0)
        // Worst accuracy tint (25% red over the card) still keeps white text readable.
        val red = Color(0xFFDC2828).copy(alpha = 0.25f)
        val blended = Color(
            red = red.red * red.alpha + card.red * (1 - red.alpha),
            green = red.green * red.alpha + card.green * (1 - red.alpha),
            blue = red.blue * red.alpha + card.blue * (1 - red.alpha),
        )
        assertTrue(contrast(BrandTokens.textPrimary, blended) >= 4.5)
    }

    // endregion
}
