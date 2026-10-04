package com.festivalscoretracker.android.songs

import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.model.SongDifficulty
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.songs.InvalidScoreReason
import com.festivalscoretracker.android.core.songs.InvalidScoreWarning
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongRowModel
import com.festivalscoretracker.android.core.songs.SongRowProjector
import com.festivalscoretracker.android.core.songs.SongScoreDetail
import com.festivalscoretracker.android.core.songs.SongScoreSource
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.ui.songs.SongRow
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.util.Locale
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The selected-player Songs metadata control on a real device (issue #135): what TalkBack's
 * linear order reads for each reachable row state, Accessibility Test Framework checks, and
 * wrapping at real glyph widths at 1.0 and 2.0 text and across a pane-width change (Robolectric
 * does not wrap at device glyph widths). Run with `device.py test
 * com.festivalscoretracker.android.songs.SongScoreMetadataDeviceTest --avd <AVD>`; reading orders
 * go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
class SongScoreMetadataDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Fixtures

    private fun song(id: String, title: String) = Song(
        songId = id,
        title = title,
        artist = "Synthetic Artist",
        year = 2021,
        durationSeconds = 185,
        difficulty = SongDifficulty(guitar = 3.0, bass = 2.0, drums = 1.0, vocals = 4.0, proGuitar = 4.0, proBass = 0.0, proDrums = 5.0, proCymbals = 5.0, proVocals = null),
        maxScores = mapOf(Instrument.Lead.wireId to 1_300_000),
    )

    private val player = AppSettings(selectedPlayer = SelectedPlayer("acct-synthetic", "Synthetic Player"), showInstrumentIcons = false)

    private val full = SongScoreDetail(
        score = 1_234_567,
        accuracy = 987_000.0,
        isFullCombo = false,
        stars = 6,
        season = 15,
        difficulty = 0.0,
        rank = 3,
        totalEntries = 1_000,
        lastPlayedAt = "2026-09-01T12:00:00Z",
    )

    private fun source(detail: SongScoreDetail?, invalid: Map<Instrument, InvalidScoreReason> = emptyMap()) =
        SongScoreSource(hasPlayer = true, detail = { _, _ -> detail }, invalid = { invalid })

    private fun project(
        song: Song,
        scores: SongScoreSource,
        settings: AppSettings = player,
        filter: SongFilter = SongFilter(),
        sort: SongSortMode = SongSortMode.Title,
    ): SongRowModel = SongRowProjector(settings, filter, 15, null, scores, sort, locale = Locale.US).project(song)

    // endregion

    // region Helpers

    private var shownRows by mutableStateOf(emptyList<SongRowModel>())
    private var shownScale by mutableStateOf(1f)
    private var shownWidth by mutableStateOf(Int.MAX_VALUE)
    private var composed = false

    /** Shows [rows]; later calls swap state in the one composition (a rule sets content once). */
    private fun show(rows: List<SongRowModel>, fontScale: Float = 1f, maxWidthDp: Int = Int.MAX_VALUE, onWarning: (() -> Unit)? = null) {
        shownRows = rows
        shownScale = fontScale
        shownWidth = maxWidthDp
        if (!composed) {
            composed = true
            rule.setContent {
                DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(shownScale)) {
                    FestivalTheme {
                        Column(
                            Modifier.fillMaxSize().background(BrandTokens.cardBackground).safeDrawingPadding().padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            shownRows.forEach { row ->
                                key(row.song.songId) {
                                    Column(Modifier.widthIn(max = shownWidth.dp).fillMaxWidth()) { SongRow(row, artUrl = null, onWarning = onWarning, onClick = {}) }
                                }
                            }
                        }
                    }
                }
            }
        }
        rule.waitForIdle()
        h.waitForTag("fst.songs.row.${rows.last().song.songId}")
    }

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot

    private fun pillTags(row: SongRowModel) = row.metadata.map { "fst.songs.metadata.${it.kind.name.lowercase()}.${row.song.songId}" }

    /** Whether the tagged pills share one line (their vertical extents overlap). */
    private fun oneLine(tags: List<String>): Boolean {
        val rects = tags.map { bounds(it) }
        return rects.maxOf { it.top } < rects.minOf { it.bottom }
    }

    /** Every pill sits inside its card; the wrapped pills end at the flow's right edge; the title column keeps at least the primary value's width. */
    private fun assertLaidOut(row: SongRowModel) {
        val id = row.song.songId
        val card = bounds("fst.songs.row.$id")
        pillTags(row).forEach { tag ->
            val b = bounds(tag)
            assertTrue("$tag $b escapes $card", b.left >= card.left - 1 && b.right <= card.right + 1 && b.bottom <= card.bottom + 1)
        }
        val rest = if (row.lastPlayed == null && row.maxScore == null) pillTags(row).drop(1) else pillTags(row)
        if (rest.isNotEmpty()) {
            val flow = bounds("fst.songs.metadata.$id")
            assertTrue("$id wrapped pills are right-aligned", abs(rest.maxOf { bounds(it).right } - flow.right) <= 2f)
        }
        val title = rule.onNode(hasText(row.song.title), useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val primary = bounds(
            when {
                row.lastPlayed != null -> "fst.songs.last-played.$id"
                row.maxScore != null -> "fst.songs.max-score.$id"
                else -> pillTags(row).first()
            },
        )
        assertTrue("$id title column (${primary.left - title.left}) keeps at least the primary's width (${primary.width})", primary.left - title.left >= primary.width)
    }

    /** The platform accessibility cache lags a state swap; poll briefly before asserting [expected]. */
    private fun assertSpoken(expected: List<String>, screen: String) {
        runCatching { rule.waitUntil(5_000) { h.readingOrder(screen) == expected } }
        assertEquals(expected, h.readingOrder(screen))
    }

    // endregion

    @Test
    fun everyRowStateIsOneLabelledStopInOrder() {
        h.enableAccessibilityChecks()
        val rows = listOf(
            project(song("m-score", "Score Song"), source(full)),
            project(song("m-fc", "Combo Song"), source(full.copy(accuracy = null, isFullCombo = true)), settings = player.copy(visibleMetadata = MetadataField.entries.toSet() - MetadataField.Score)),
            project(song("m-bass", "Bass Song"), source(full.copy(rank = 400, season = 9, stars = 3, difficulty = 3.0)), settings = player.copy(visibleInstruments = Instrument.entries.toSet() - Instrument.Lead)),
            project(song("m-none", "Zero Song"), source(SongScoreDetail(0))),
            project(song("m-paused", "Paused Song"), SongScoreSource.PAUSED),
        )
        show(rows)
        assertEquals(rows.map { it.announcement }, h.readingOrder("song-score-metadata"))
        assertTrue(rows[0].announcement.contains("Score 1,234,567, Accuracy 98.7%, Top 1%, 5 gold stars, Current season 15, Song intensity 4 of 7, Easy difficulty"))
        assertTrue(rows[1].announcement.contains("Full combo, accuracy unavailable"))
        assertTrue(rows[2].announcement.contains("Bass chart, Score 1,234,567"))
        assertTrue(rows[3].announcement.endsWith("No score"))
        assertTrue(rows[4].announcement.endsWith("Player scores paused until songs update"))
        h.assertAccessible()
    }

    @Test
    fun filteredScoreAddsTheInvalidScoreIconAsASecondStop() {
        h.enableAccessibilityChecks()
        val row = project(song("m-invalid", "Filtered Song"), source(SongScoreDetail(0), mapOf(Instrument.Lead to InvalidScoreReason.NoFallback)))
        show(listOf(row), onWarning = {})
        assertEquals(listOf(row.announcement, InvalidScoreWarning.LABEL), h.readingOrder("song-score-metadata-invalid"))
        h.assertAccessible()
    }

    @Test
    fun regularAndDoubleTextWrapRightAlignedWithoutClipping() {
        val score = project(song("m-score", "Score Song"), source(full))
        val date = project(song("m-date", "Last Played Song"), source(full), filter = SongFilter(Instrument.Lead), sort = SongSortMode.LastPlayed)
        val dual = project(song("m-dual", "Max Score Song"), source(full), filter = SongFilter(Instrument.Lead), sort = SongSortMode.MaxDistance)
        val entry = project(song("m-entry", "The Way Life Goes"), source(full), settings = player.copy(showInstrumentIcons = true), sort = SongSortMode.LastPlayed)
        listOf(score, date, dual, entry).forEach { row ->
            show(listOf(row))
            assertLaidOut(row)
            show(listOf(row), fontScale = 2f)
            assertLaidOut(row)
            assertSpoken(listOf(row.announcement), "song-score-metadata-font-2-${row.song.songId}")
        }
        show(listOf(score), fontScale = 2f, maxWidthDp = 400)
        assertFalse("2.0 text wraps a phone-width row", oneLine(pillTags(score).drop(1)))
    }

    @Test
    fun paneWidthChangeRewraps() {
        val row = project(song("m-score", "Score Song"), source(full))
        show(listOf(row), maxWidthDp = 720)
        val wide = rule.activity.resources.configuration.screenWidthDp >= 752
        if (wide) assertTrue("A 720 dp pane keeps one line", oneLine(pillTags(row).drop(1)))
        show(listOf(row), maxWidthDp = 300)
        assertFalse("A 300 dp pane wraps", oneLine(pillTags(row).drop(1)))
        assertLaidOut(row)
        show(listOf(row), maxWidthDp = 720)
        if (wide) assertTrue(oneLine(pillTags(row).drop(1)))
        assertLaidOut(row)
    }
}
