package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.rankings.LeaderboardColumnLayout
import com.festivalscoretracker.android.core.rankings.LeaderboardRowKind
import com.festivalscoretracker.android.core.rankings.LeaderboardSection
import com.festivalscoretracker.android.core.rankings.ScoreSectionTexts
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/** The shared per-section leaderboard column fitter (issue #37). */
class LeaderboardColumnLayoutTest {
    // region Fixtures

    private val scores = LeaderboardSection(
        kind = LeaderboardRowKind.Score,
        rankWidth = 40f,
        metaWidth = 30f,
        valueWidth = 70f,
        hasAccuracy = true,
        hasStars = true,
    )

    private val rankings = LeaderboardSection(LeaderboardRowKind.Ranking, rankWidth = 20f, metaWidth = 64f, valueWidth = 60f)

    // endregion

    // region Score sections

    @Test
    fun narrowRowTightensGapsAndKeepsOnlyCoreColumns() {
        val plan = LeaderboardColumnLayout.fit(scores, 360f)
        assertEquals(LeaderboardColumnLayout.COMPACT_GAP, plan.gap)
        assertEquals(plan.gap, LeaderboardColumnLayout.gapFor(360f))
        assertTrue(plan.compact)
        assertEquals(40f, plan.rankWidth)
        assertEquals(70f, plan.valueWidth)
        assertFalse(plan.showMeta)
        assertEquals(0f, plan.metaWidth)
        assertFalse(plan.showStars)
        assertEquals(0f, plan.starsWidth)
        // The accuracy slot is reserved even on narrow rows, so badges line up.
        assertTrue(plan.showAccuracy)
        assertEquals(LeaderboardColumnLayout.ACCURACY_WIDTH, plan.accuracyWidth)
    }

    @Test
    fun seasonShowsFromTheMediumBreakpoint() {
        assertFalse(LeaderboardColumnLayout.fit(scores, 519f).showMeta)
        val plan = LeaderboardColumnLayout.fit(scores, 520f)
        assertEquals(LeaderboardColumnLayout.WIDE_GAP, plan.gap)
        assertTrue(plan.showMeta)
        assertEquals(30f, plan.metaWidth)
        assertFalse(plan.showStars)
    }

    @Test
    fun wideRowShowsSeasonAndStars() {
        assertFalse(LeaderboardColumnLayout.fit(scores, 699f).showStars)
        val plan = LeaderboardColumnLayout.fit(scores, 900f)
        assertTrue(plan.showMeta)
        assertTrue(plan.showStars)
        assertEquals(LeaderboardColumnLayout.STARS_WIDTH, plan.starsWidth)
        assertFalse(plan.compact)
    }

    @Test
    fun unknownWidthShowsNoOptionalColumns() {
        val plan = LeaderboardColumnLayout.fit(scores, Float.NaN)
        assertEquals(LeaderboardColumnLayout.WIDE_GAP, plan.gap)
        assertFalse(plan.showMeta)
        assertFalse(plan.showStars)
        assertTrue(plan.showAccuracy)
        assertFalse(LeaderboardColumnLayout.fit(scores, 0f).showMeta)
    }

    @Test
    fun sectionWithoutValuesHidesTheirColumns() {
        val bare = scores.copy(metaWidth = 0f, hasAccuracy = false, hasStars = false)
        val plan = LeaderboardColumnLayout.fit(bare, 900f)
        assertFalse(plan.showMeta)
        assertFalse(plan.showAccuracy)
        assertEquals(0f, plan.accuracyWidth)
        assertFalse(plan.showStars)
    }

    @Test
    fun shortRanksGetTheMinimumAndMissingRanksNone() {
        assertEquals(LeaderboardColumnLayout.MIN_SCORE_RANK_WIDTH, LeaderboardColumnLayout.fit(scores.copy(rankWidth = 12f), 360f).rankWidth)
        assertEquals(0f, LeaderboardColumnLayout.fit(scores.copy(rankWidth = 0f), 360f).rankWidth)
    }

    @Test
    fun largeTextStacksRowsRatherThanDroppingSeasonOrStars() {
        // Issue #170 (web `resolveTopScoresColumns`: season from 520, stars from the mobile breakpoint, width only).
        val large = scores.copy(rankWidth = 80f, metaWidth = 60f, valueWidth = 140f)
        // 24 + 80 + 144 + 60 + 140 + 112 + 116 + 20 + 6 × 12 = 768 > 700: the row stacks and keeps both.
        val wide = LeaderboardColumnLayout.fit(large, 700f, fontScale = 2f)
        assertTrue(wide.showStars)
        assertTrue(wide.showMeta)
        assertTrue(wide.stacked)
        assertEquals(LeaderboardColumnLayout.ACCURACY_WIDTH * 2f, wide.accuracyWidth)
        // 520 and 600 (no stars): 24 + 80 + 144 + 60 + 140 + 112 + 20 + 5 × 12 = 640 > 600: stacked, season kept.
        for (width in listOf(520f, 600f)) {
            val medium = LeaderboardColumnLayout.fit(large, width, fontScale = 2f)
            assertTrue(medium.showMeta)
            assertEquals(60f, medium.metaWidth)
            assertFalse(medium.showStars)
            assertTrue(medium.stacked)
        }
        // Below 520 there's no season to keep, so the row does not stack for it.
        assertFalse(LeaderboardColumnLayout.fit(large, 519f, fontScale = 2f).stacked)
        // The same section at normal text fits on one line with both.
        val normal = LeaderboardColumnLayout.fit(large, 700f)
        assertTrue(normal.showStars)
        assertTrue(normal.showMeta)
        assertFalse(normal.stacked)
    }

    @Test
    fun oneLineScoreRowsDoNotStack() {
        for (width in listOf(Float.NaN, 0f, 200f, 360f, 520f, 900f)) assertFalse(LeaderboardColumnLayout.fit(scores, width).stacked)
    }

    @Test
    fun fontScaleBelowOneOrInvalidIsIgnored() {
        assertEquals(LeaderboardColumnLayout.fit(scores, 900f), LeaderboardColumnLayout.fit(scores, 900f, fontScale = 0.85f))
        assertEquals(LeaderboardColumnLayout.fit(scores, 900f), LeaderboardColumnLayout.fit(scores, 900f, fontScale = Float.NaN))
    }

    // endregion

    // region Rankings sections

    @Test
    fun rankingsKeepSongsWhileNamesFit() {
        for (width in listOf(Float.NaN, 300f, 900f)) {
            val plan = LeaderboardColumnLayout.fit(rankings, width)
            assertTrue(plan.showMeta)
            assertEquals(64f, plan.metaWidth)
            assertEquals(LeaderboardColumnLayout.MIN_RANKING_RANK_WIDTH, plan.rankWidth)
            assertFalse(plan.showAccuracy)
            assertFalse(plan.showStars)
        }
        assertEquals(LeaderboardColumnLayout.COMPACT_GAP, LeaderboardColumnLayout.fit(rankings, 300f).gap)
    }

    @Test
    fun rankingsDropSongsOnlyWhenNamesWouldCollapse() {
        // 16 + 44 + 32 + 64 + 60 + 20 + 4 × 12 = 284: names keep their minimum beside the songs label.
        assertTrue(LeaderboardColumnLayout.fit(rankings, 284f).showMeta)
        // Narrower (a card beside a hinge), the whole section drops songs so names don't collapse to "…".
        val narrow = LeaderboardColumnLayout.fit(rankings, 283f)
        assertFalse(narrow.showMeta)
        assertEquals(0f, narrow.metaWidth)
        assertEquals(LeaderboardColumnLayout.MIN_RANKING_RANK_WIDTH, narrow.rankWidth)
        assertEquals(60f, narrow.valueWidth)
        // Unknown widths (before the first layout) keep the songs label.
        assertTrue(LeaderboardColumnLayout.fit(rankings, 0f).showMeta)
        // Large text grows the name minimum.
        assertFalse(LeaderboardColumnLayout.fit(rankings, 284f, fontScale = 1.5f).showMeta)
        // Band Rankings (#116) keep their songs label and stack instead.
        val band = LeaderboardColumnLayout.fit(rankings.copy(stackNarrowNames = true), 283f)
        assertTrue(band.showMeta)
        assertTrue(band.stacked)
    }

    @Test
    fun rankingsNeverShowStarsEvenWhenFlagged() {
        assertFalse(LeaderboardColumnLayout.fit(rankings.copy(hasStars = true, hasAccuracy = true), 900f).showStars)
    }

    @Test
    fun songsYieldToNamesOnlyWhenTheyWouldTruncateOne() {
        val compete = rankings.copy(nameWidth = 120f)
        // 16 + 44 + 120 + 64 + 60 + 20 + 4 × 12 = 372: every name fits beside the songs label.
        val fits = LeaderboardColumnLayout.fit(compete, 372f)
        assertTrue(fits.showMeta)
        assertEquals(64f, fits.metaWidth)
        // One dp narrower would truncate the widest name, so the whole section hides songs.
        val tight = LeaderboardColumnLayout.fit(compete, 371f)
        assertFalse(tight.showMeta)
        assertEquals(0f, tight.metaWidth)
        // Rank and rating keep their widths so every row stays aligned.
        assertEquals(fits.rankWidth, tight.rankWidth)
        assertEquals(fits.valueWidth, tight.valueWidth)
    }

    @Test
    fun songsYieldingToNamesWaitForTheFirstLayout() {
        val compete = rankings.copy(nameWidth = 40f)
        assertFalse(LeaderboardColumnLayout.fit(compete, Float.NaN).showMeta)
        assertFalse(LeaderboardColumnLayout.fit(compete, 0f).showMeta)
        assertTrue(LeaderboardColumnLayout.fit(compete, 900f).showMeta)
    }

    @Test
    fun songsYieldingToNamesNeedSongs() {
        assertFalse(LeaderboardColumnLayout.fit(rankings.copy(metaWidth = 0f, nameWidth = 40f), 900f).showMeta)
    }

    @Test
    fun scoreSectionsIgnoreNameWidth() {
        assertEquals(LeaderboardColumnLayout.fit(scores, 600f), LeaderboardColumnLayout.fit(scores.copy(nameWidth = 400f), 600f))
    }

    @Test
    fun bandRowsStackOnlyWhenTheNameWouldDropBelowItsMinimum() {
        val bands = rankings.copy(stackNarrowNames = true)
        // 16 + 44 + 64 + 60 + 20 + 4 × 12 = 252 fixed, so the name gets exactly 72 dp at 324.
        assertEquals(72f, LeaderboardColumnLayout.rankingNameRoom(bands, showMeta = true, rowWidth = 324f))
        assertFalse(LeaderboardColumnLayout.fit(bands, 324f).stacked)
        val narrow = LeaderboardColumnLayout.fit(bands, 323f)
        assertTrue(narrow.stacked)
        // The one-line columns are unchanged, so a wider pane switches straight back.
        assertTrue(narrow.showMeta)
        assertEquals(LeaderboardColumnLayout.fit(rankings, 323f), narrow.copy(stacked = false))
    }

    @Test
    fun bandRowsStayOnOneLineBeforeTheFirstLayoutOrWhenNotOptedIn() {
        val bands = rankings.copy(stackNarrowNames = true)
        assertFalse(LeaderboardColumnLayout.fit(bands, Float.NaN).stacked)
        assertFalse(LeaderboardColumnLayout.fit(bands, 0f).stacked)
        assertFalse(LeaderboardColumnLayout.fit(rankings, 200f).stacked)
        assertFalse(LeaderboardColumnLayout.fit(scores.copy(stackNarrowNames = true), 200f).stacked)
    }

    @Test
    fun nameRoomDropsHiddenColumns() {
        // Without songs or a rank: 16 + 60 + 20 + 2 × 12 = 120 fixed.
        assertEquals(180f, LeaderboardColumnLayout.rankingNameRoom(rankings.copy(rankWidth = 0f), showMeta = false, rowWidth = 300f))
    }

    @Test
    fun nameMinimumDropsSongsThenStacksRows() {
        val full = rankings.copy(keepsNameMinimum = true)
        // 16 + 44 + 72 + 64 + 60 + 20 + 4 × 12 = 324: the minimum name fits beside the songs label.
        val wide = LeaderboardColumnLayout.fit(full, 324f)
        assertTrue(wide.showMeta)
        assertFalse(wide.stacked)
        // Narrower: songs yield first, the row stays one line (16 + 44 + 72 + 60 + 20 + 3 × 12 = 248).
        val noSongs = LeaderboardColumnLayout.fit(full, 323f)
        assertFalse(noSongs.showMeta)
        assertEquals(0f, noSongs.metaWidth)
        assertFalse(noSongs.stacked)
        assertFalse(LeaderboardColumnLayout.fit(full, 248f).stacked)
        // Below that the name can't keep its minimum on one line, so rows stack.
        assertTrue(LeaderboardColumnLayout.fit(full, 247f).stacked)
    }

    @Test
    fun nameMinimumGrowsWithFontScale() {
        val full = rankings.copy(keepsNameMinimum = true)
        assertTrue(LeaderboardColumnLayout.fit(full, 324f).showMeta)
        assertFalse(LeaderboardColumnLayout.fit(full, 324f, fontScale = 1.3f).showMeta)
    }

    @Test
    fun nameMinimumWaitsForTheFirstLayoutAndIsOptIn() {
        val full = rankings.copy(keepsNameMinimum = true)
        val unknown = LeaderboardColumnLayout.fit(full, Float.NaN)
        assertTrue(unknown.showMeta)
        assertFalse(unknown.stacked)
        // Without the opt-in a narrow row never stacks (Leaderboards cards); it only drops the
        // songs label so names don't collapse (issue #114).
        val plain = LeaderboardColumnLayout.fit(rankings, 200f)
        assertFalse(plain.showMeta)
        assertFalse(plain.stacked)
        assertTrue(LeaderboardColumnLayout.fit(rankings, 300f).showMeta)
        // Score sections never stack.
        assertFalse(LeaderboardColumnLayout.fit(scores.copy(keepsNameMinimum = true), 100f).stacked)
    }

    // endregion

    // region Section texts

    @Test
    fun sectionTextsCollectEveryRowIncludingThePinnedOne() {
        val rows = listOf(
            LeaderboardEntry(accountId = "a", score = 412_345, rank = 1, accuracy = 990_000.0, stars = 6, season = 15),
            LeaderboardEntry(accountId = "b", score = 99_900, rank = 25),
            LeaderboardEntry(accountId = "me", score = 1_000, rank = 1_234, season = 3),
        )
        val texts = ScoreSectionTexts.of(rows, Locale.US)
        assertEquals(listOf("#1", "#25", "#1,234"), texts.ranks)
        assertEquals(listOf("S15", "S3"), texts.seasons)
        assertEquals(listOf("412,345", "99,900", "1,000"), texts.scores)
        assertTrue(texts.hasAccuracy)
        assertTrue(texts.hasStars)
    }

    @Test
    fun starsOutsideOneToSixDrawNothing() {
        val rows = listOf(
            LeaderboardEntry(accountId = "a", score = 1, rank = 1, stars = 0),
            LeaderboardEntry(accountId = "b", score = 1, rank = 2, stars = 7),
            LeaderboardEntry(accountId = "c", score = 1, rank = 3),
        )
        val texts = ScoreSectionTexts.of(rows, Locale.US)
        assertFalse(texts.hasStars)
        assertFalse(texts.hasAccuracy)
        assertTrue(texts.seasons.isEmpty())
    }

    @Test
    fun aFullComboWithoutAccuracyKeepsTheAccuracyColumn() {
        val rows = listOf(
            LeaderboardEntry(accountId = "a", score = 1, rank = 1, isFullCombo = true),
            LeaderboardEntry(accountId = "b", score = 1, rank = 2, isFullCombo = false),
        )
        assertTrue(ScoreSectionTexts.of(rows, Locale.US).hasAccuracy)
        assertFalse(ScoreSectionTexts.of(rows.drop(1), Locale.US).hasAccuracy)
    }

    @Test
    fun gapTightensOnlyForAKnownNarrowRow() {
        assertEquals(LeaderboardColumnLayout.COMPACT_GAP, LeaderboardColumnLayout.gapFor(419f))
        assertEquals(LeaderboardColumnLayout.WIDE_GAP, LeaderboardColumnLayout.gapFor(420f))
        assertEquals(LeaderboardColumnLayout.WIDE_GAP, LeaderboardColumnLayout.gapFor(Float.NaN))
        assertEquals(LeaderboardColumnLayout.WIDE_GAP, LeaderboardColumnLayout.gapFor(0f))
    }

    // endregion
}
