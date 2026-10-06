package com.festivalscoretracker.android.ui.design

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.ViewGroup
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.format.ScoreAccuracyBadge
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.leaderboards.LeaderboardSectionMember
import com.festivalscoretracker.android.ui.leaderboards.rememberScoreColumns
import com.festivalscoretracker.android.ui.shell.FestivalApp
import com.festivalscoretracker.android.ui.songdetail.ScoreRow
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import kotlin.math.abs
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
 * The score-accuracy control (`fst.score.accuracy.*`, `.agents/controls/score-accuracy/android.md`):
 * one test per reachable state — absent, graded low/mid/high, full combo with and without
 * accuracy, invalid, aligned columns (also when a row has no accuracy), badge contrast, the
 * Song Detail preview and the full chart, and large text.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ScoreAccuracyUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val rows = listOf(
        LeaderboardEntry("acct-low", "Low Player", 99_000, 1, accuracy = 120_000.0, isFullCombo = false),
        LeaderboardEntry("acct-mid", "Mid Player", 98_000, 2, accuracy = 550_000.0, isFullCombo = false),
        LeaderboardEntry("acct-high", "High Player", 97_000, 3, accuracy = 987_654.0, isFullCombo = false),
        LeaderboardEntry("acct-fc", "Full Combo", 96_000, 4, accuracy = 1_000_000.0, isFullCombo = true),
        LeaderboardEntry("acct-fcna", "Combo No Acc", 95_000, 5, accuracy = null, isFullCombo = true),
        LeaderboardEntry("acct-none", "No Accuracy", 94_000, 6, accuracy = null, isFullCombo = null),
        LeaderboardEntry("acct-bad", "Bad Accuracy", 93_000, 7, accuracy = Double.NaN, isFullCombo = false),
    )

    // region Helpers

    private fun board(fontScale: Float = 1f, width: Int = 400) {
        rule.setContent {
            FestivalTheme {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                    val columns = rememberScoreColumns(rows)
                    LeaderboardSectionMember(columns, "card", Modifier.width(width.dp).background(BrandTokens.cardBackground)) {
                        rows.forEach { entry -> Box(Modifier.testTag("row.${entry.accountId}")) { ScoreRow(entry, columns = columns.plan) } }
                    }
                }
            }
        }
        rule.waitForIdle()
    }

    private fun tag(id: String) = "${ACCURACY_TAG_PREFIX}$id"

    private fun label(id: String): String? =
        rule.onNodeWithTag(tag(id), useUnmergedTree = true).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.single()

    private fun widthDp(id: String) = rule.onNodeWithTag(tag(id), useUnmergedTree = true).getUnclippedBoundsInRoot().width.value

    /** The badge's pixels, drawn in software (Robolectric's `captureToImage` never gets a frame). */
    private fun capture(id: String): Bitmap {
        val view = rule.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
        val whole = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(whole))
        val b = rule.onNodeWithTag(tag(id), useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        return Bitmap.createBitmap(whole, b.left.toInt(), b.top.toInt(), b.width.toInt(), b.height.toInt())
    }

    /** Pixels per dp at the test's xxhdpi qualifier. */
    private val density = 3

    /** Whether any captured pixel of the badge is within [tolerance] of [rgb] per channel. */
    private fun hasColour(id: String, rgb: Int, tolerance: Int = 12): Boolean {
        val pixels = capture(id)
        for (x in 0 until pixels.width) for (y in 0 until pixels.height) {
            if (ScoreAccuracyContrast.close(pixels.getPixel(x, y) and 0xFFFFFF, rgb, tolerance)) return true
        }
        return false
    }

    private fun exists(id: String) = rule.onAllNodesWithTag(tag(id), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun centreX(id: String) = rule.onNodeWithTag(tag(id), useUnmergedTree = true).getUnclippedBoundsInRoot().let { (it.left + it.right).value / 2 }

    // endregion

    @Test
    fun absentRowDrawsNothingButKeepsTheColumn() {
        board()
        assertTrue(!exists("acct-none"))
        rule.onNodeWithTag("row.acct-none").assertIsDisplayed()
        // missing-accuracy-aligned: every score ends at the same x, with or without a badge.
        val scoreRights = rule.onAllNodesWithTag("fst.score", useUnmergedTree = true).fetchSemanticsNodes().map { it.boundsInRoot.right }
        assertEquals(rows.size, scoreRights.size)
        assertTrue("score column ragged: $scoreRights", scoreRights.all { abs(it - scoreRights.first()) < 1f })
    }

    @Test
    fun gradedLowMidHighShowThePercentAndSayAccuracy() {
        board()
        assertEquals("Accuracy 12%", label("acct-low"))
        assertEquals("Accuracy 55%", label("acct-mid"))
        assertEquals("Accuracy 98.8%", label("acct-high"))
    }

    @Test
    fun fullComboShowsGoldPercentWithoutAnFcChip() {
        board()
        assertEquals("Full combo, accuracy 100%", label("acct-fc"))
        assertEquals("Full combo; accuracy unavailable", label("acct-fcna"))
    }

    @Test
    fun invalidAccuracyShowsANeutralDash() {
        board()
        assertEquals("Accuracy unavailable", label("acct-bad"))
    }

    @Test
    fun alignedColumnsCentreEveryBadgeOnOneLine() {
        board()
        val centres = listOf("acct-low", "acct-mid", "acct-high", "acct-fc", "acct-fcna", "acct-bad").map(::centreX)
        assertTrue("badges ragged: $centres", centres.all { abs(it - centres.first()) < 0.5f })
    }

    @Test
    fun fullComboOnlySectionKeepsTheAccuracyColumn() {
        rule.setContent {
            FestivalTheme {
                val only = listOf(LeaderboardEntry("acct-fcna", "Combo", 1, 1, accuracy = null, isFullCombo = true))
                val columns = rememberScoreColumns(only)
                Column(Modifier.width(400.dp)) { ScoreRow(only.single(), columns = columns.plan) }
            }
        }
        assertEquals("Full combo; accuracy unavailable", label("acct-fcna"))
    }

    @Test
    fun badgeContrastMeetsTextMinimumOverTheCard() {
        board()
        listOf("acct-low", "acct-mid", "acct-high").forEach { id ->
            val pixels = capture(id)
            // A padding pixel left of the centred text: the 25% tint over the card.
            val fill = pixels.getPixel(2 * density, pixels.height / 2)
            val expected = ScoreAccuracyContrast.composite(
                ScoreAccuracyBadge.of(rows.first { it.accountId == id }.accuracy, false)!!.tint!!,
                ScoreAccuracyBadge.GRADED_TINT_ALPHA,
                BrandTokens.cardBackground.toArgb() and 0xFFFFFF,
            )
            assertTrue("$id fill ${Integer.toHexString(fill)} vs ${Integer.toHexString(expected)}", ScoreAccuracyContrast.close(fill and 0xFFFFFF, expected, 3))
            val ratio = ScoreAccuracyContrast.ratio(0xFFFFFF, fill and 0xFFFFFF)
            assertTrue("$id contrast $ratio", ratio >= 4.5)
        }
    }

    @Test
    fun largeTextShowsTheSpokenLabelInsideTheRow() {
        board(fontScale = 2f)
        assertEquals("Full combo, accuracy 100%", label("acct-fc"))
        assertTrue(!exists("acct-none"))
        // Expanded: the visible label is the spoken one, far wider than the compact "XX.X%" pill.
        assertTrue("fc width ${widthDp("acct-fc")}", widthDp("acct-fc") > 2 * 56f)
        // The stacked row lays every badge inside the 400 dp row.
        listOf("acct-low", "acct-fc", "acct-fcna").forEach {
            val bounds = rule.onNodeWithTag(tag(it), useUnmergedTree = true).getUnclippedBoundsInRoot()
            assertTrue("$it overflows: $bounds", bounds.right.value <= 400f && bounds.width.value > 0f)
        }
    }

    /**
     * Issue #149: stacked (font 2.0) rows give every rank the section's slot, so a bold pinned
     * row and a longer rank (#10 after #9) indent their names like the rest.
     */
    @Test
    fun largeTextNamesLineUpWhateverTheRankWidth() {
        val section = listOf(
            LeaderboardEntry("acct-9", "Nine Player", 99_000, 9, accuracy = 990_000.0, isFullCombo = false),
            LeaderboardEntry("acct-10", "Ten Player", 98_000, 10, accuracy = 980_000.0, isFullCombo = false),
            LeaderboardEntry("acct-28", "Pinned Player", 97_000, 28, accuracy = 970_000.0, isFullCombo = false),
        )
        rule.setContent {
            FestivalTheme {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                    val columns = rememberScoreColumns(section)
                    Column(Modifier.width(400.dp)) {
                        LeaderboardSectionMember(columns, "rows") {
                            section.dropLast(1).forEach { ScoreRow(it, columns = columns.plan) }
                        }
                        LeaderboardSectionMember(columns, "footer") { ScoreRow(section.last(), isSelected = true, columns = columns.plan) }
                    }
                }
            }
        }
        rule.waitForIdle()
        val lefts = section.map { rule.onNodeWithText(it.displayName!!, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.left }
        assertTrue("names ragged: $lefts", lefts.all { abs(it - lefts.first()) < 0.5f })
    }

    @Test
    fun compactBadgeKeepsTheColumnWidth() {
        board()
        listOf("acct-low", "acct-high", "acct-fc", "acct-fcna", "acct-bad").forEach {
            assertEquals(it, 56f, widthDp(it), 0.5f)
        }
    }

    @Test
    fun fullComboIsGoldOutlinedAndGradedIsNot() {
        rule.setContent {
            FestivalTheme {
                Column(Modifier.background(BrandTokens.cardBackground)) {
                    AccuracyPill(1_000_000.0, isFullCombo = true, id = "fc")
                    AccuracyPill(null, isFullCombo = true, id = "fcna")
                    AccuracyPill(500_000.0, isFullCombo = false, id = "graded")
                    AccuracyPill(null, isFullCombo = false, id = "absent")
                }
            }
        }
        rule.waitForIdle()
        assertTrue(exists("fc") && exists("fcna") && exists("graded") && !exists("absent"))
        val gold = BrandTokens.gold.toArgb() and 0xFFFFFF
        val stroke = BrandTokens.goldStroke.toArgb() and 0xFFFFFF
        listOf("fc", "fcna").forEach { assertTrue("$it gold", hasColour(it, gold) && hasColour(it, stroke, 6)) }
        assertTrue(!hasColour("graded", gold) && !hasColour("graded", stroke, 6))
    }

    // region Whole app: preview and full chart

    private val boardJson = """{"songId":"s-alpha","instrument":"Solo_Guitar","count":4,"totalEntries":4,"localEntries":4,"entries":[
      {"accountId":"${Fixtures.ACCOUNT_B}","displayName":"Combo Player","score":99999,"rank":1,"accuracy":1000000,"isFullCombo":true},
      {"accountId":"abcdefabcdefabcdefabcdefabcdef01","displayName":"Graded Player","score":99998,"rank":2,"accuracy":873000,"isFullCombo":false},
      {"accountId":"abcdefabcdefabcdefabcdefabcdef02","displayName":"Missing Player","score":99997,"rank":3,"isFullCombo":true},
      {"accountId":"abcdefabcdefabcdefabcdefabcdef03","displayName":"Absent Player","score":99996,"rank":4}]}"""

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4)); rule.waitForIdle()
    }

    private fun waitForTag(tag: String) = rule.waitUntil(20_000) {
        settle(100); rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    }

    @Test
    fun previewAndFullChartTagEveryBadgeAndMergeItIntoTheRow() {
        val transport = FakeTransport.standard().apply {
            on("/api/leaderboard/s-alpha/Solo_Guitar", headers = mapOf("X-FST-Publication-Id" to "7")) { boardJson }
        }
        val debug = DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), songQuery = "s-alpha", stillBackground = true)
        rule.setContent { FestivalApp(AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences()), debug) }
        settle()
        waitForTag("fst.song-detail.list")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.view-all.Solo_Guitar"))
        waitForTag(tag(Fixtures.ACCOUNT_B))

        // preview: tags exist, and each row's single TalkBack stop includes the badge label.
        assertEquals("Full combo, accuracy 100%", label(Fixtures.ACCOUNT_B))
        assertTrue(!exists("abcdefabcdefabcdefabcdefabcdef03"))
        val row = rule.onNodeWithTag("fst.song-detail.preview-row.Solo_Guitar.abcdefabcdefabcdefabcdefabcdef01").fetchSemanticsNode()
        assertTrue(row.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().contains("Accuracy 87.3%"))

        // full-chart: the same badges on the full leaderboard.
        rule.onNodeWithTag("fst.song-detail.view-all.Solo_Guitar").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.song-leaderboard.list")
        waitForTag(tag("abcdefabcdefabcdefabcdefabcdef01"))
        assertEquals("Full combo, accuracy 100%", label(Fixtures.ACCOUNT_B))
        assertEquals("Accuracy 87.3%", label("abcdefabcdefabcdefabcdefabcdef01"))
        assertEquals("Full combo; accuracy unavailable", label("abcdefabcdefabcdefabcdefabcdef02"))
        assertTrue(!exists("abcdefabcdefabcdefabcdefabcdef03"))
    }

    // endregion
}
