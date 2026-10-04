package com.festivalscoretracker.android.bands

import com.festivalscoretracker.android.core.bands.BandDetail
import com.festivalscoretracker.android.core.bands.BandDetailProjection
import com.festivalscoretracker.android.core.bands.BandFormatting
import com.festivalscoretracker.android.core.bands.BandLayout
import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.BandPaging
import com.festivalscoretracker.android.core.bands.BandProfileEnvelope
import com.festivalscoretracker.android.core.bands.BandRankHistoryEntry
import com.festivalscoretracker.android.core.bands.BandRankHistoryResponse
import com.festivalscoretracker.android.core.bands.BandRankingMetric
import com.festivalscoretracker.android.core.bands.BandSongExtremesResponse
import com.festivalscoretracker.android.core.bands.BandSongPerformance
import com.festivalscoretracker.android.core.bands.BandSongRow
import com.festivalscoretracker.android.core.bands.BandText
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.bands.PlayerBandEntry
import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.core.bands.PlayerBandListResponse
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardEntry
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardResponse
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.Fixtures
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BandsCoreTest {
    private val us = Locale.US

    // region Types

    @Test
    fun bandTypesMetricsAndGroups() {
        assertEquals(listOf("Band_Duets", "Band_Trios", "Band_Quad"), BandType.entries.map { it.wireId })
        assertEquals(listOf("Duos", "Trios", "Quads"), BandType.entries.map { it.label })
        assertEquals(listOf(2, 3, 4), BandType.entries.map { it.memberCount })
        assertEquals(BandType.Trios, BandType.fromWireId("Band_Trios"))
        assertNull(BandType.fromWireId("band_trios"))
        assertNull(BandType.fromWireId(null))
        assertEquals(BandRankingMetric.FcRate, BandRankingMetric.fromWireId("fcrate"))
        assertNull(BandRankingMetric.fromWireId("maxscore"))
        assertEquals(BandRankingMetric.TotalScore, BandRankingMetric.DEFAULT)
        assertEquals(listOf("all", "duos", "trios", "quads"), PlayerBandGroup.entries.map { it.wireId })
        assertEquals("All Bands", PlayerBandGroup.All.label)
        assertEquals(BandType.Quad, PlayerBandGroup.Quads.bandType)
        assertNull(PlayerBandGroup.All.bandType)
    }

    @Test
    fun teamKeyAndMemberValidation() {
        assertTrue(BandText.isValidMemberId(Fixtures.ACCOUNT_A))
        assertTrue(BandText.isValidMemberId("fixture-player-1"))
        assertFalse(BandText.isValidMemberId(""))
        assertFalse(BandText.isValidMemberId(null))
        assertFalse(BandText.isValidMemberId("a/b"))
        assertFalse(BandText.isValidMemberId("x".repeat(129)))
        assertTrue(BandText.isValidTeamKey(BandFixtures.DUO_KEY))
        assertTrue(BandText.isValidTeamKey("fixture-team-1"))
        assertTrue(BandText.isValidTeamKey("a:b:c:d"))
        assertFalse(BandText.isValidTeamKey("a:b:c:d:e"))
        assertFalse(BandText.isValidTeamKey("a::b"))
        assertFalse(BandText.isValidTeamKey("../x"))
        assertFalse(BandText.isValidTeamKey(null))
        assertFalse(BandText.isValidTeamKey(""))
        assertFalse(BandText.isValidTeamKey("a".repeat(601)))
    }

    // endregion

    // region Models

    @Test
    fun membersDecodeWithAnonymousFallbackAndDistinctInstruments() {
        val list = FestivalApi.JSON.decodeFromString(PlayerBandListResponse.serializer(), BandFixtures.playerBands(3, 1, 25))
        assertEquals(3, list.entries.size)
        val duo = list.entries[0]
        assertEquals(BandFixtures.DUO_ID, duo.key)
        assertEquals("Synthetic Lead + Synthetic Bass", duo.membersLabel)
        assertEquals(listOf("Lead"), duo.members[0].chartedInstruments.map { it.label })
        val trio = list.entries[1]
        assertEquals("Synthetic Lead + Synthetic Bass + Unknown User", trio.membersLabel)
        val anonymous = trio.members.last()
        assertFalse(anonymous.isLinkable)
        assertEquals(BandMember.UNKNOWN_USER, anonymous.resolvedName)
        assertEquals(BandMember.UNKNOWN_USER, BandMember(accountId = "x", displayName = "  ").resolvedName)
        // Anonymous members are never collapsed together; repeated IDs are.
        val repeated = listOf(BandMember("a"), BandMember("a"), BandMember(""), BandMember(""))
        assertEquals(3, BandMember.distinct(repeated).size)
        assertEquals("Band", BandMember.joinNames(emptyList()))
        assertEquals("teamKey-only", list.entries[0].copy(bandId = "", teamKey = "teamKey-only").key)
    }

    @Test
    fun playerBandListValidation() {
        val list = FestivalApi.JSON.decodeFromString(PlayerBandListResponse.serializer(), BandFixtures.playerBands(30, 1, 25))
        list.validate(BandFixtures.PLAYER, 25)
        assertEquals(2, list.pageCount(25))
        assertEquals(1, PlayerBandListResponse().pageCount(25))
        assertThrows(FestivalApiException.InvalidResponse::class.java) { list.validate(Fixtures.ACCOUNT_B, 25) }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { list.validate(BandFixtures.PLAYER, 10) }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { list.copy(totalCount = -1).validate(BandFixtures.PLAYER, 25) }
        assertThrows(FestivalApiException.InvalidResponse::class.java) {
            list.copy(entries = listOf(list.entries[0].copy(teamKey = ""))).validate(BandFixtures.PLAYER, 25)
        }
        assertEquals(1, BandPaging.pageCount(0, 25))
        assertEquals(1, BandPaging.pageCount(25, 25))
        assertEquals(2, BandPaging.pageCount(26, 25))
        assertEquals(26, BandPaging.pageCount(26, 0))
    }

    @Test
    fun bandDetailDecodesRanksAndDisplayMembers() {
        val envelope = FestivalApi.JSON.decodeFromString(BandProfileEnvelope.serializer(), BandFixtures.bandProfile())
        val detail = envelope.selectedBandEntry!!
        assertEquals(listOf(3, 4, 5, 2), BandRankingMetric.entries.map { detail.rank(it) })
        assertEquals(2, detail.displayMembers.size)
        val rosterOnly = BandDetail(teamMembers = listOf(BandMember("a", "Roster")))
        assertEquals("Roster", rosterOnly.displayMembers.single().resolvedName)
        assertTrue(BandDetail().displayMembers.isEmpty())
        assertNull(FestivalApi.JSON.decodeFromString(BandProfileEnvelope.serializer(), BandFixtures.bandProfile(teamKey = null)).selectedBandEntry)
    }

    @Test
    fun songBoardValidationAndPaging() {
        val board = FestivalApi.JSON.decodeFromString(SongBandLeaderboardResponse.serializer(), BandFixtures.songBoard("s-alpha", "Band_Duets", 30, 0, 25))
        board.validate("s-alpha", BandType.Duets, 25)
        assertEquals(2, board.pageCount(25))
        assertEquals("band-1:1", board.entries[0].key)
        assertEquals("Synthetic Lead + Unknown User", board.entries[0].membersLabel)
        assertEquals("t:3", board.entries[0].copy(bandId = "", teamKey = "t", rank = 3).key)
        assertEquals(0, board.copy(localEntries = null, totalEntries = -5).population)
        listOf(
            { board.validate("s-beta", BandType.Duets, 25) },
            { board.validate("s-alpha", BandType.Trios, 25) },
            { board.validate("s-alpha", BandType.Duets, 10) },
            { board.copy(count = 3).validate("s-alpha", BandType.Duets, 25) },
            { board.copy(totalEntries = -1).validate("s-alpha", BandType.Duets, 25) },
            { board.copy(localEntries = -1).validate("s-alpha", BandType.Duets, 25) },
        ).forEach { assertThrows(FestivalApiException.InvalidResponse::class.java) { it() } }
    }

    // endregion

    @Test
    fun wireModelDefaultsAreEmptyAndSafe() {
        assertEquals("", PlayerBandEntry().key)
        assertEquals("Band", PlayerBandEntry().membersLabel)
        assertNull(BandProfileEnvelope().selectedBandEntry)
        assertTrue(BandRankHistoryResponse().history.isEmpty())
        assertEquals(0, BandSongPerformance().rank)
        assertTrue(BandSongExtremesResponse().best.isEmpty() && BandSongExtremesResponse().worst.isEmpty())
        assertEquals(":0", SongBandLeaderboardEntry().key)
        assertEquals(1, SongBandLeaderboardResponse().pageCount(25))
        assertEquals(BandMember.UNKNOWN_USER, BandMember().resolvedName)
        assertFalse(BandMember().isLinkable)
    }

    // region Formatting

    @Test
    fun formatting() {
        assertEquals("12,345", BandFormatting.count(12345, us))
        assertEquals("#1,234", BandFormatting.rank(1234, us))
        assertEquals(BandFormatting.NONE, BandFormatting.rank(0, us))
        assertEquals("#1.5", BandFormatting.averageRank(1.5, us))
        assertEquals(BandFormatting.NONE, BandFormatting.averageRank(Double.NaN, us))
        assertEquals(BandFormatting.NONE, BandFormatting.averageRank(0.0, us))
        assertEquals("98.8%", BandFormatting.accuracy(987654.0, us))
        assertEquals(BandFormatting.NONE, BandFormatting.accuracy(null, us))
        assertEquals(BandFormatting.NONE, BandFormatting.accuracy(0.0, us))
        assertEquals("5.4", BandFormatting.stars(5.4, us))
        assertEquals(BandFormatting.NONE, BandFormatting.stars(0.0, us))
        assertEquals("30.0%", BandFormatting.percentage(0.3, us))
        assertEquals(BandFormatting.NONE, BandFormatting.percentage(Double.POSITIVE_INFINITY, us))
        assertEquals("Top 3%", BandFormatting.percentile(0.03, us))
        assertEquals("Top 0.40%", BandFormatting.percentile(0.004, us))
        assertEquals("Top 0.01%", BandFormatting.percentile(0.0, us))
        assertEquals("Top 100%", BandFormatting.percentile(4.0, us))
        assertEquals(BandFormatting.NONE, BandFormatting.percentile(Double.NaN, us))
        assertEquals("29 / 50", BandFormatting.fraction(29, 50, us))
        assertEquals("1 appearance", BandFormatting.appearances(1, us))
        assertEquals("2 appearances", BandFormatting.appearances(2, us))
        assertEquals("Top 5%", BandFormatting.metricValue(0.05, BandRankingMetric.Adjusted, us))
        assertEquals("Top 5%", BandFormatting.metricValue(0.05, BandRankingMetric.Weighted, us))
        assertEquals("30.0%", BandFormatting.metricValue(0.3, BandRankingMetric.FcRate, us))
        assertEquals("1,235", BandFormatting.metricValue(1234.6, BandRankingMetric.TotalScore, us))
        assertEquals(BandFormatting.NONE, BandFormatting.metricValue(null, BandRankingMetric.TotalScore, us))
        assertEquals(BandFormatting.NONE, BandFormatting.metricValue(Double.NaN, BandRankingMetric.TotalScore, us))
        assertEquals("Sep 27", BandFormatting.shortDate("2026-09-27", us))
        assertEquals("yesterday", BandFormatting.shortDate("yesterday", us))
    }

    // endregion

    // region Projection

    @Test
    fun summaryAndStatistics() {
        val detail = FestivalApi.JSON.decodeFromString(BandProfileEnvelope.serializer(), BandFixtures.bandProfile()).selectedBandEntry!!
        val summary = BandDetailProjection.summary(detail, BandType.Duets)
        assertEquals(listOf("Duos", "29", "2"), summary.map { it.value })
        val song = Fixtures.song("s-alpha", "Alpha Tune")
        val stats = BandDetailProjection.statistics(detail, BandType.Duets, BandRankingMetric.TotalScore, song)
        assertEquals(
            listOf("rank", "songs-played", "full-combos", "total-score", "fc-rate", "avg-accuracy", "avg-stars", "best-rank", "avg-rank"),
            stats.map { it.id },
        )
        assertEquals("Total Score Rank", stats[0].label)
        assertEquals(BandRankingsRoute("Band_Duets"), stats[0].route)
        assertEquals(SongDetailRoute("s-alpha"), stats[7].route)
        val unranked = BandDetailProjection.statistics(detail.copy(adjustedSkillRank = 0, bestRank = 0), BandType.Duets, BandRankingMetric.Adjusted, song)
        assertNull(unranked[0].route)
        assertEquals(BandFormatting.NONE, unranked[0].value)
        assertNull(unranked[7].route)
        assertNull(BandDetailProjection.statistics(detail, BandType.Duets, BandRankingMetric.Adjusted, null)[7].route)
    }

    @Test
    fun historyProjection() {
        val response = FestivalApi.JSON.decodeFromString(BandRankHistoryResponse.serializer(), BandFixtures.history())
        val ranked = BandDetailProjection.ranked(response.history, BandRankingMetric.TotalScore)
        assertEquals(listOf("2024-01-01", "2024-01-02", "2024-01-03"), ranked.map { it.snapshotDate })
        val points = BandDetailProjection.points(ranked, BandRankingMetric.TotalScore)
        assertEquals(listOf(0f, 0.5f, 1f), points.map { it.x })
        assertEquals(listOf(1f, 0.5f, 0f), points.map { it.y })
        assertEquals(0.5f, BandDetailProjection.points(ranked.take(1), BandRankingMetric.TotalScore).single().x)
        assertEquals(0.5f, BandDetailProjection.points(ranked.take(1), BandRankingMetric.TotalScore).single().y)
        assertTrue(BandDetailProjection.points(emptyList(), BandRankingMetric.TotalScore).isEmpty())
        val rows = BandDetailProjection.recentRows(ranked, BandRankingMetric.Adjusted, us)
        assertEquals(listOf("2024-01-03", "2024-01-02", "2024-01-01"), rows.map { it.date })
        assertEquals("Jan 3", rows[0].dateText)
        assertEquals("#1", rows[0].rankText)
        assertEquals("Top 2%", rows[0].valueText)
        val many = (1..15).map { BandRankHistoryEntry(snapshotDate = "2024-02-%02d".format(it), totalScoreRank = it) }
        assertEquals(BandDetailProjection.RECENT_ROWS, BandDetailProjection.recentRows(many, BandRankingMetric.TotalScore, us).size)
        val entry = BandRankHistoryEntry(adjustedSkillRank = 1, weightedRank = 2, fcRateRank = 3, totalScoreRank = 4, adjustedSkillRating = 0.1, weightedRating = 0.2, fcRate = 0.3, totalScore = 5)
        assertEquals(listOf(1, 2, 3, 4), BandRankingMetric.entries.map { entry.rank(it) })
        assertEquals(listOf(0.1, 0.2, 0.3, 5.0), BandRankingMetric.entries.map { entry.value(it) })
    }

    @Test
    fun historyNotes() {
        fun note(status: String?, message: String? = null) = BandDetailProjection.historyNote(BandRankHistoryResponse(historyStatus = status, historyMessage = message))
        assertNull(note(null))
        assertNull(note("current"))
        assertEquals("Rank history is temporarily unavailable.", note("failed", "ignored"))
        assertEquals("Custom", note("stale", " Custom "))
        assertEquals("History is catching up. Current rankings are already fresh.", note("catching_up"))
        assertEquals("Rank history is behind the latest current rankings.", note("stale"))
        assertEquals("Rank history is disabled while current rankings remain available.", note("disabled"))
        assertNull(note(null, "  "))
    }

    @Test
    fun songRows() {
        val song = Fixtures.song("s-alpha", "Alpha Tune", artist = "Synthetic Artist", year = 2021)
        val known = BandSongRow(BandSongPerformance(songId = "s-alpha"), song)
        assertEquals("Alpha Tune", known.title)
        assertEquals("Synthetic Artist · 2021", known.subtitle)
        assertEquals(SongDetailRoute("s-alpha"), known.route)
        val unknown = BandSongRow(BandSongPerformance(songId = "s-x"), null)
        assertEquals("Unknown Song", unknown.title)
        assertEquals("", unknown.subtitle)
        assertNull(unknown.route)
        assertEquals("2020", BandSongRow(BandSongPerformance(), Fixtures.song("a", "A", artist = "", year = 2020)).subtitle)
    }

    // endregion

    // region Layout

    @Test
    fun paneAndGridGeometry() {
        // Book fold half-open: rail 80 dp, fold at 532 dp in the window, 771 dp of content.
        val half = BandLayout.hingeInContent(532f, 532f, 80f, 771f, separating = true)!!
        assertEquals(452f, half.left)
        assertEquals(BandLayout.Panes(true, 452f, 0f), BandLayout.panes(851f, 771f, half))
        val halfGrid = BandLayout.grid(771f, half)
        assertEquals(2, halfGrid.columns)
        val column = (771f - halfGrid.start - halfGrid.end - halfGrid.gutter) / 2
        assertEquals(452f - BandLayout.EDGE, halfGrid.start + column)
        assertEquals(452f + BandLayout.EDGE, halfGrid.start + column + halfGrid.gutter)
        // Unfolded (flat fold): expanded window splits at the fold; a two-column grid meets at it.
        val flat = half.copy(separating = false)
        assertEquals(BandLayout.Panes(true, 452f, 0f), BandLayout.panes(851f, 771f, flat))
        assertEquals(2, BandLayout.grid(771f, flat).columns)
        // A flat fold in a wide window with room for more columns keeps the natural grid.
        assertEquals(BandLayout.Grid(4, 16f, 16f, 12f), BandLayout.grid(1400f, BandLayout.Hinge(700f, 700f, false)))
        // Medium window without a separating hinge: single pane.
        assertEquals(BandLayout.Panes(false, null, 0f), BandLayout.panes(700f, 771f, flat))
        assertEquals(BandLayout.Panes(false, null, 0f), BandLayout.panes(411f, 411f, null))
        assertEquals(BandLayout.Panes(true, null, BandLayout.PANE_GAP), BandLayout.panes(1280f, 1200f, null))
        // Phone: one column; hinge too close to an edge is ignored.
        assertEquals(BandLayout.Grid(1, 16f, 16f, 12f), BandLayout.grid(411f, null))
        assertEquals(null, BandLayout.hingeInContent(250f, 250f, 80f, 771f, true))
        assertEquals(null, BandLayout.hingeInContent(700f, 700f, 80f, 771f, true))
        // Tri-fold unfolded: two flat folds; the central one is picked, and an unbalanced flat fold never anchors panes.
        val folds = listOf(BandLayout.Hinge(280f, 280f, false), BandLayout.Hinge(640f, 640f, false))
        assertEquals(640f, BandLayout.central(folds, 1000f)!!.left)
        assertEquals(null, BandLayout.central(emptyList(), 1000f))
        assertEquals(BandLayout.Panes(true, null, BandLayout.PANE_GAP), BandLayout.panes(1080f, 1000f, folds[0]))
        assertEquals(BandLayout.Panes(true, null, BandLayout.PANE_GAP), BandLayout.panes(1080f, 1000f, folds[1]))
        assertEquals(BandLayout.Panes(true, 450f, 0f), BandLayout.panes(1080f, 1000f, BandLayout.Hinge(450f, 450f, false)))
        // ...nor the card grid (issue #117: 280 dp of the leading panel stayed empty); a balanced flat fold still does.
        assertEquals(BandLayout.Grid(2, 16f, 16f, 12f), BandLayout.grid(984f, BandLayout.Hinge(624f, 624f, false)))
        assertEquals(BandLayout.Grid(2, 16f, 16f, 12f), BandLayout.grid(984f, BandLayout.Hinge(264f, 264f, false)))
        assertEquals(2, BandLayout.grid(984f, BandLayout.Hinge(624f, 624f, true)).columns)
        assertEquals(BandLayout.Grid(2, 16f, 16f, 32f), BandLayout.grid(1000f, BandLayout.Hinge(500f, 500f, false)))
        // A separating hinge anchors panes even when unbalanced.
        assertEquals(BandLayout.Panes(true, 300f, 0f), BandLayout.panes(900f, 1000f, BandLayout.Hinge(300f, 300f, true)))
        // A physical hinge with width becomes the gutter.
        val hinge = BandLayout.hingeInContent(500f, 520f, 0f, 1000f, true)!!
        assertEquals(BandLayout.Panes(true, 500f, 20f), BandLayout.panes(1000f, 1000f, hinge))
        assertEquals(52f, BandLayout.grid(1000f, hinge).gutter)
    }

    @Test
    fun songBandLeaderboardSplitsOnlyAcrossASeparatingHinge() {
        // Half-open book fold: controls pane ends at the fold, rows start after it.
        assertEquals(BandLayout.Panes(true, 452f, 0f), BandLayout.listSplit(BandLayout.Hinge(452f, 452f, true)))
        // A physical hinge with width becomes the gap.
        assertEquals(BandLayout.Panes(true, 500f, 20f), BandLayout.listSplit(BandLayout.Hinge(500f, 520f, true)))
        // Flat folds (unfolded book, tri-fold) and no hinge keep one centred column.
        assertEquals(BandLayout.Panes(false, null, 0f), BandLayout.listSplit(BandLayout.Hinge(452f, 452f, false)))
        assertEquals(BandLayout.Panes(false, null, 0f), BandLayout.listSplit(null))
    }

    // endregion

    // region Song band leaderboard rows

    @Test
    fun bandScoreAnnouncementReadsWhatTheRowShows() {
        val entry = SongBandLeaderboardEntry(
            bandId = "b",
            members = listOf(
                BandMember("a".repeat(32), "Rekayy", listOf("Solo_Guitar"), score = 156_912),
                BandMember("", null, emptyList()),
            ),
            score = 931_020,
            rank = 1,
            accuracy = 1_000_000.0,
            isFullCombo = true,
            stars = 6,
        )
        val text = com.festivalscoretracker.android.ui.bands.bandScoreAnnouncement(entry)
        assertTrue(text, text.startsWith("Rank 1, Rekayy, Lead, 156,912, Unknown User, No observed instrument, band score 931,020, full combo, "))
        assertTrue(text, text.endsWith("% accuracy, Gold stars"))
        assertFalse(text, text.contains("6 stars"))
        // No accuracy, FC or stars: only rank, members and score.
        val bare = com.festivalscoretracker.android.ui.bands.bandScoreAnnouncement(entry.copy(accuracy = 0.0, isFullCombo = false, stars = 0, members = entry.members.take(1)))
        assertEquals("Rank 1, Rekayy, Lead, 156,912, band score 931,020", bare)
        assertTrue(com.festivalscoretracker.android.ui.bands.bandScoreAnnouncement(entry.copy(stars = 4)).endsWith(", 4 stars"))
    }

    // endregion

    @Test
    fun bandQuickLinksMatchTheWeb() {
        val links = com.festivalscoretracker.android.core.bands.BandQuickLinks.sections()
        assertEquals(listOf("members", "summary", "statistics", "rank-history", "songs"), links.map { it.id })
        assertEquals(listOf("Members", "Summary", "Statistics", "Rank History", "Songs"), links.map { it.title })
        assertEquals(listOf("Members", "Band Summary", "Band Statistics", "Band Rank History", "Band Songs"), links.map { it.accessibleTitle })
    }
}
