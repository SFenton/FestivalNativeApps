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
    fun largeTextDropsStarsBeforeSeason() {
        val large = scores.copy(rankWidth = 80f, metaWidth = 60f, valueWidth = 140f)
        // 24 + 80 + 144 + 60 + 140 + 112 + 116 + 20 + 6 × 12 = 768 > 700: stars go, the season stays (640).
        val wide = LeaderboardColumnLayout.fit(large, 700f, fontScale = 2f)
        assertFalse(wide.showStars)
        assertTrue(wide.showMeta)
        assertEquals(LeaderboardColumnLayout.ACCURACY_WIDTH * 2f, wide.accuracyWidth)
        // At 600 the season no longer fits either.
        val medium = LeaderboardColumnLayout.fit(large, 600f, fontScale = 2f)
        assertFalse(medium.showStars)
        assertFalse(medium.showMeta)
        // The same section at normal text keeps both.
        val normal = LeaderboardColumnLayout.fit(large, 700f)
        assertTrue(normal.showStars)
        assertTrue(normal.showMeta)
    }

    @Test
    fun fontScaleBelowOneOrInvalidIsIgnored() {
        assertEquals(LeaderboardColumnLayout.fit(scores, 900f), LeaderboardColumnLayout.fit(scores, 900f, fontScale = 0.85f))
        assertEquals(LeaderboardColumnLayout.fit(scores, 900f), LeaderboardColumnLayout.fit(scores, 900f, fontScale = Float.NaN))
    }

    // endregion

    // region Rankings sections

    @Test
    fun rankingsKeepSongsAtAnyWidth() {
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

    // endregion
}
