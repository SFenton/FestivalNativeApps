package com.festivalscoretracker.android.rivals

import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.nav.AllRivalsRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.RivalDetailRoute
import com.festivalscoretracker.android.core.nav.RivalryRoute
import com.festivalscoretracker.android.core.rivals.HingeColumns
import com.festivalscoretracker.android.core.rivals.LeaderboardRivalSummary
import com.festivalscoretracker.android.core.rivals.LeaderboardRivalsListResponse
import com.festivalscoretracker.android.core.rivals.RivalCategorization
import com.festivalscoretracker.android.core.rivals.RivalCombo
import com.festivalscoretracker.android.core.rivals.RivalCommonRivals
import com.festivalscoretracker.android.core.rivals.RivalDetailRequest
import com.festivalscoretracker.android.core.rivals.RivalDetailResponse
import com.festivalscoretracker.android.core.rivals.RivalDirection
import com.festivalscoretracker.android.core.rivals.RivalHeadToHead
import com.festivalscoretracker.android.core.rivals.RivalIdentity
import com.festivalscoretracker.android.core.rivals.RivalQuickLinks
import com.festivalscoretracker.android.core.rivals.RivalRankMetric
import com.festivalscoretracker.android.core.rivals.RivalCategory
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.core.rivals.RivalSentiment
import com.festivalscoretracker.android.core.rivals.RivalSettingsScope
import com.festivalscoretracker.android.core.rivals.RivalSongComparison
import com.festivalscoretracker.android.core.rivals.RivalSummary
import com.festivalscoretracker.android.core.rivals.RivalText
import com.festivalscoretracker.android.core.rivals.RivalrySort
import com.festivalscoretracker.android.core.rivals.RivalsListResponse
import com.festivalscoretracker.android.core.rivals.rivalEntries
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test

/** Pure Rivals logic: scopes, combos, common rivals, categories, formatting, columns and routes. */
class RivalsCoreTest {
    private val ids = RivalsFixtures.RIVALS

    private fun summary(id: String, score: Double, shared: Int = 10, name: String? = "N$score") =
        RivalSummary(id, name, score, shared, 1, 2, 0.0)

    private fun song(delta: Int, id: String = "s$delta", title: String? = "T$delta") =
        RivalSongComparison(id, title, "A", "Solo_Guitar", userRank = 10, rivalRank = 10 + delta, rankDelta = delta, userScore = 1000L + delta, rivalScore = 1000L)

    // region Combos

    @Test
    fun comboIdsMatchWebBitmasks() {
        assertEquals("03", RivalCombo.comboId(listOf(Instrument.Lead, Instrument.Bass)))
        assertEquals("0f", RivalCombo.comboId(listOf(Instrument.Vocals, Instrument.Drums, Instrument.Bass, Instrument.Lead)))
        assertEquals("30", RivalCombo.comboId(listOf(Instrument.ProLead, Instrument.ProBass)))
        assertEquals("180", RivalCombo.comboId(listOf(Instrument.ProCymbals, Instrument.ProDrums)))
        assertEquals(listOf(Instrument.Lead, Instrument.Bass), RivalCombo.fromMask(0x03))
    }

    @Test
    fun deriveTokenFollowsSettingsRules() {
        assertEquals("03", RivalCombo.deriveToken(setOf(Instrument.Lead, Instrument.Bass)))
        assertEquals(RivalCombo.PRO_DRUMS_TOKEN, RivalCombo.deriveToken(setOf(Instrument.ProDrums, Instrument.ProCymbals)))
        assertNull(RivalCombo.deriveToken(setOf(Instrument.Lead)))
        assertNull(RivalCombo.deriveToken(setOf(Instrument.Lead, Instrument.ProLead)))
        assertNull(RivalCombo.deriveToken(Instrument.entries))
        assertEquals("30", RivalCombo.deriveToken(setOf(Instrument.ProLead, Instrument.ProBass)))
    }

    @Test
    fun deriveTokensCoversEveryFamilyThenFirstChart() {
        assertEquals(listOf("0f", "30", "pro_drums"), RivalCombo.deriveTokens(Instrument.entries))
        assertEquals(listOf("Solo_PeripheralVocals"), RivalCombo.deriveTokens(setOf(Instrument.Karaoke, Instrument.ProDrums)))
        assertEquals(listOf("Solo_Guitar"), RivalCombo.deriveTokens(setOf(Instrument.Lead, Instrument.ProLead)))
        assertEquals(emptyList<String>(), RivalCombo.deriveTokens(emptySet()))
    }

    @Test
    fun comboTokensValidateAndLabel() {
        assertEquals(listOf(Instrument.ProCymbals, Instrument.ProDrums), RivalCombo.instrumentsFor("pro_drums"))
        assertEquals(listOf(Instrument.Lead, Instrument.Bass), RivalCombo.instrumentsFor("03"))
        listOf(null, "", "0", "zz", "12345", "1ff0", "../x").forEach { assertNull(it, RivalCombo.instrumentsFor(it)) }
        assertTrue(RivalCombo.isValidToken("0F"))
        assertEquals("Pro Drums Family", RivalCombo.label("pro_drums"))
        assertEquals("Lead + Bass", RivalCombo.label("03"))
        assertEquals(RivalText.COMBINED, RivalCombo.label("41"))
        assertEquals("Bass", RivalCombo.scopeLabel("Solo_Bass"))
        assertEquals("Pro Lead + Pro Bass", RivalCombo.scopeLabel("30"))
    }

    // endregion

    // region Scope

    @Test
    fun scopeTokensRoundTrip() {
        val scopes = listOf(
            RivalScopes.song(listOf(Instrument.Bass, Instrument.Lead)),
            RivalScope.Leaderboard(Instrument.Drums, RivalRankMetric.FcRate),
            RivalScope.Combo("03"),
            RivalScope.FromSettings(RivalSettingsScope.All),
            RivalScope.FromSettings(RivalSettingsScope.Common),
        )
        scopes.forEach { assertEquals(it, RivalScopes.fromToken(it.routeToken)) }
        assertEquals("song:Solo_Guitar,Solo_Bass", scopes[0].routeToken)
        assertEquals("leaderboard:Solo_Drums:fcrate", scopes[1].routeToken)
        assertEquals(RivalScope.Combo("03"), RivalScopes.fromToken("combo:03:Solo_Guitar,Solo_Bass"))
    }

    @Test
    fun malformedScopeTokensAreRejected() {
        listOf(null, "", "song", "song:", "song:Nope", "leaderboard:Solo_Guitar", "leaderboard:Nope:totalscore",
            "leaderboard:Solo_Guitar:nope", "combo:zz", "combo", "settings:nope", "other:1").forEach {
            assertNull(it, RivalScopes.fromToken(it))
        }
    }

    @Test
    fun listScopesResolveAgainstSettings() {
        val visible = setOf(Instrument.Lead, Instrument.Bass)
        assertEquals(RivalScopes.song(visible), RivalScopes.resolveList(RivalScope.FromSettings(RivalSettingsScope.Common), visible))
        assertNull(RivalScopes.resolveList(RivalScope.FromSettings(RivalSettingsScope.Common), setOf(Instrument.Lead)))
        assertEquals(RivalScope.Combo("03"), RivalScopes.resolveList(RivalScope.FromSettings(RivalSettingsScope.Combo), visible))
        assertNull(RivalScopes.resolveList(RivalScope.FromSettings(RivalSettingsScope.Combo), setOf(Instrument.Lead)))
        assertNull(RivalScopes.resolveList(RivalScope.FromSettings(RivalSettingsScope.All), visible))
        assertNull(RivalScopes.resolveList(RivalScope.Song(emptyList()), visible))
        assertNull(RivalScopes.resolveList(RivalScope.Combo("zz"), visible))
        assertNull(RivalScopes.resolveList(null, visible))
        val leaderboard = RivalScope.Leaderboard(Instrument.Lead)
        assertEquals(leaderboard, RivalScopes.resolveList(leaderboard, visible))
    }

    @Test
    fun detailScopesFollowTheWeb() {
        val visible = setOf(Instrument.Lead, Instrument.Bass)
        assertEquals(RivalDetailRequest.Scopes(listOf("03")), RivalScopes.resolveDetail(null, visible))
        assertEquals(RivalDetailRequest.Scopes(listOf("Solo_Drums")), RivalScopes.resolveDetail(null, setOf(Instrument.Drums)))
        assertEquals(RivalDetailRequest.Scopes(listOf("Solo_Guitar")), RivalScopes.resolveDetail(null, emptySet()))
        assertEquals(RivalDetailRequest.Leaderboard(Instrument.Bass, RivalRankMetric.TotalScore), RivalScopes.resolveDetail(RivalScope.Leaderboard(Instrument.Bass), visible))
        assertEquals(RivalDetailRequest.Scopes(listOf("Solo_Guitar", "Solo_Bass")), RivalScopes.resolveDetail(RivalScopes.song(visible), emptySet()))
        assertEquals(RivalDetailRequest.Scopes(listOf("pro_drums")), RivalScopes.resolveDetail(RivalScope.Combo("pro_drums"), visible))
        assertEquals(RivalDetailRequest.Scopes(listOf("03")), RivalScopes.resolveDetail(RivalScope.Combo("zz"), visible))
        assertEquals(RivalDetailRequest.Scopes(listOf("Solo_Guitar", "Solo_Bass")), RivalScopes.resolveDetail(RivalScope.FromSettings(RivalSettingsScope.Common), visible))
        assertEquals(RivalDetailRequest.Scopes(listOf("03")), RivalScopes.resolveDetail(RivalScope.FromSettings(RivalSettingsScope.Combo), visible))
        assertEquals(RivalDetailRequest.Scopes(listOf("0f", "30", "pro_drums")), RivalScopes.resolveDetail(RivalScope.FromSettings(RivalSettingsScope.All), Instrument.entries.toSet()))
        assertEquals(RivalDetailRequest.Scopes(listOf("Solo_Guitar")), RivalScopes.resolveDetail(RivalScope.FromSettings(RivalSettingsScope.All), emptySet()))
    }

    @Test
    fun titlesAndSingleInstrument() {
        assertEquals("Common Rivals", RivalScopes.listTitle(RivalScopes.song(listOf(Instrument.Lead, Instrument.Bass))))
        assertEquals("Lead Rivals", RivalScopes.listTitle(RivalScopes.song(listOf(Instrument.Lead))))
        assertEquals("Drums Rivals", RivalScopes.listTitle(RivalScope.Leaderboard(Instrument.Drums)))
        assertEquals("Pro Drums Family Rivals", RivalScopes.listTitle(RivalScope.Combo("pro_drums")))
        assertEquals("Common Rivals", RivalScopes.listTitle(RivalScope.FromSettings(RivalSettingsScope.Common)))
        assertEquals("Combined Rivals", RivalScopes.listTitle(RivalScope.FromSettings(RivalSettingsScope.Combo)))
        assertEquals("Rivals", RivalScopes.listTitle(null))
        assertEquals(Instrument.Lead, RivalScopes.singleInstrument(RivalScopes.song(listOf(Instrument.Lead))))
        assertEquals(Instrument.Bass, RivalScopes.singleInstrument(RivalScope.Leaderboard(Instrument.Bass)))
        assertNull(RivalScopes.singleInstrument(RivalScope.Combo("03")))
        assertEquals(listOf(Instrument.Lead, Instrument.Bass), RivalScope.Combo("03").instruments)
        assertEquals(emptyList<Instrument>(), RivalScope.Combo("zz").instruments)
    }

    // endregion

    // region Common rivals

    @Test
    fun commonRivalsIntersectWithMajorityDirection() {
        val lead = RivalsListResponse("Solo_Guitar", listOf(summary(ids[0], 90.0), summary(ids[1], 80.0)), listOf(summary(ids[2], 70.0), summary("", 5.0)))
        val bass = RivalsListResponse("Solo_Bass", listOf(summary(ids[1], 85.0, shared = 40)), listOf(summary(ids[0], 60.0), summary(ids[3], 50.0), summary("", 4.0)))
        val drums = RivalsListResponse("Solo_Drums", emptyList(), listOf(summary(ids[0], 30.0), summary(ids[1], 20.0)))
        val (above, below) = RivalCommonRivals.intersect(listOf(lead, bass))
        assertEquals(listOf(ids[0], ids[1]), above.map { it.accountId })
        assertEquals(40, above[1].sharedSongCount)
        assertEquals(above to below, RivalCommonRivals.intersect(listOf(lead, bass, RivalsListResponse.empty("Solo_Vocals"))))
        assertTrue(below.isEmpty())
        val (above3, below3) = RivalCommonRivals.intersect(listOf(lead, bass, drums))
        assertEquals(listOf(ids[1]), above3.map { it.accountId })
        assertEquals(listOf(ids[0]), below3.map { it.accountId })
        assertEquals(emptyList<RivalSummary>() to emptyList<RivalSummary>(), RivalCommonRivals.intersect(listOf(lead)))
    }

    // endregion

    // region Models

    @Test
    fun rowNamesAndNavigability() {
        assertEquals(RivalText.UNKNOWN_USER, summary("", 1.0).shownName)
        assertFalse(summary("", 1.0).isNavigable)
        assertEquals(RivalText.UNKNOWN_USER, summary("bad id", 1.0).shownName)
        assertEquals(RivalText.UNKNOWN_PLAYER, summary(ids[0], 1.0, name = " ").shownName)
        assertEquals("Name", summary(ids[0], 1.0, name = " Name ").shownName)
        val entries = rivalEntries(listOf(summary(ids[0], 1.0), summary(ids[1], 1.0)), listOf(summary("", 1.0)), limit = 1)
        assertEquals(listOf(RivalDirection.Above, RivalDirection.Below), entries.map { it.direction })
        assertEquals("Above:${ids[0]}", entries[0].key(0))
        assertEquals("Below:anon:1", entries[1].key(1))
    }

    @Test
    fun listValidationDropsNegativeCounts() {
        val list = RivalsListResponse("x", listOf(summary(ids[0], Double.NaN), summary(ids[1], 1.0)), listOf(RivalSummary(ids[2], null, 1.0, -1, 0, 0, 0.0))).validated()
        assertEquals(listOf(ids[1]), list.above.map { it.accountId })
        assertTrue(list.below.isEmpty())
        assertTrue(RivalsListResponse.empty("x").isEmpty)
        val leaderboard = LeaderboardRivalsListResponse(
            above = listOf(LeaderboardRivalSummary(ids[0], "A", 1, 1, 0), LeaderboardRivalSummary(ids[1], "B", -1)),
            below = listOf(LeaderboardRivalSummary(ids[2], "C", 1, -1)),
        ).validated()
        assertEquals(1, leaderboard.above.size)
        assertTrue(leaderboard.below.isEmpty())
        assertTrue(LeaderboardRivalsListResponse.empty(Instrument.Lead).isEmpty)
        assertEquals("Solo_Guitar", LeaderboardRivalsListResponse.empty(Instrument.Lead).instrument)
    }

    @Test
    fun detailValidationAndMerge() {
        val detail = RivalDetailResponse(
            RivalIdentity(ids[0].uppercase(), "  "),
            songs = listOf(song(1), song(2).copy(instrument = "Nope"), song(3).copy(songId = ""), song(4).copy(userRank = -1)),
        ).validated(ids[0])
        assertNull(detail.rival.displayName)
        assertEquals(listOf("s1"), detail.songs.map { it.songId })
        assertThrows(FestivalApiException.InvalidResponse::class.java) { RivalDetailResponse(RivalIdentity(ids[1])).validated(ids[0]) }
        val merged = RivalDetailResponse.merge(
            listOf(
                RivalDetailResponse(RivalIdentity(ids[0], null), songs = listOf(song(1), song(2))),
                RivalDetailResponse(RivalIdentity(ids[0], "Named"), songs = listOf(song(2), song(3).copy(instrument = "Solo_Bass"))),
            ),
            listOf("Solo_Guitar", "Solo_Bass"),
        )
        assertEquals("Named", merged.rival.displayName)
        assertEquals(3, merged.totalSongs)
        assertEquals("Solo_Guitar,Solo_Bass", merged.combo)
        assertEquals(0, RivalDetailResponse.empty(ids[0]).songs.size)
        val mixed = song(1).copy(userInstrument = "Solo_PeripheralCymbals", rivalInstrument = "Solo_PeripheralDrums")
        assertEquals(Instrument.ProCymbals, mixed.userChart)
        assertEquals(Instrument.ProDrums, mixed.rivalChart)
        assertEquals(Instrument.Lead, mixed.chart)
    }

    @Test
    fun defaultsAndCopy() {
        assertTrue(RivalsListResponse().isEmpty)
        assertEquals("", RivalIdentity().accountId)
        assertEquals(0, RivalDetailResponse().songs.size)
        assertEquals(0, com.festivalscoretracker.android.core.compete.ComboRankingEntry().rank)
        assertEquals(0, RivalSongComparison("s", instrument = "Solo_Guitar").rankDelta)
        assertEquals(RivalText.NO_RIVALS_SINGLE, RivalText.noRivalsSubtitle(1))
        assertEquals(RivalText.NO_RIVALS_PLURAL, RivalText.noRivalsSubtitle(3))
        assertNull(RivalText.noRivalsSubtitle(0))
        assertEquals(RivalRankMetric.MaxScore, RivalRankMetric.fromWireId("maxscore"))
        assertNull(RivalRankMetric.fromWireId("x"))
    }

    // endregion

    // region Categories

    @Test
    fun categoriesSplitLikeTheWeb() {
        val songs = listOf(1, -2, 3, -40, 60, 120, -9, 7, 0).map { song(it) }
        val categories = RivalCategorization.categorize(songs)
        assertEquals(listOf("closest_battles", "almost_passed", "slipping_away", "barely_winning", "pulling_forward", "dominating_them"), categories.map { it.key })
        assertEquals(listOf(0, 1, -2, 3, 7), categories[0].songs.map { it.rankDelta })
        assertEquals(listOf(-2, -9), categories[1].songs.map { it.rankDelta })
        assertEquals(listOf(-40), categories[2].songs.map { it.rankDelta })
        assertEquals(listOf(1, 3), categories[3].songs.map { it.rankDelta })
        assertEquals(listOf(7, 60), categories[4].songs.map { it.rankDelta })
        assertEquals(listOf(120), categories[5].songs.map { it.rankDelta })
        assertEquals(RivalSentiment.Negative, categories[1].sentiment)
        assertEquals(RivalSentiment.Positive, categories[5].sentiment)
        assertEquals("Songs where you and your rival are neck and neck.", categories[0].description)
        assertTrue(RivalCategorization.categorize(emptyList()).isEmpty())
        assertEquals(listOf("closest_battles", "barely_winning"), RivalCategorization.categorize(listOf(song(4))).map { it.key })
        assertEquals("Almost Passed", RivalCategorization.title("almost_passed"))
        assertEquals("weird", RivalCategorization.title("weird"))
        assertNull(RivalCategorization.description("weird"))
        assertEquals(6, RivalCategorization.keys.size)
    }

    // endregion

    // region Head to head

    @Test
    fun sortsAndSummaries() {
        val songs = listOf(song(5, title = "b"), song(-20, title = "A"), song(1, title = null, id = "c"))
        assertEquals(songs, RivalHeadToHead.sort(songs, RivalrySort.Category))
        assertEquals(listOf(1, 5, -20), RivalHeadToHead.sort(songs, RivalrySort.Closest).map { it.rankDelta })
        assertEquals(listOf(5, 1, -20), RivalHeadToHead.sort(songs, RivalrySort.YouLead).map { it.rankDelta })
        assertEquals(listOf(-20, 1, 5), RivalHeadToHead.sort(songs, RivalrySort.TheyLead).map { it.rankDelta })
        assertEquals(listOf("A", "b", null), RivalHeadToHead.sort(songs, RivalrySort.Title).map { it.title })
        assertEquals("3 shared songs · 2 ahead / 1 behind", RivalHeadToHead.summary(songs, Locale.US))
        assertEquals("Your Biggest Leads", RivalrySort.YouLead.label)
    }

    @Test
    fun rankDeltaFormattingMatchesWeb() {
        assertEquals("+12", RivalHeadToHead.formatRankDelta(12, Locale.US))
        assertEquals("−9,999", RivalHeadToHead.formatRankDelta(-9_999, Locale.US))
        assertEquals("0", RivalHeadToHead.formatRankDelta(0, Locale.US))
        assertEquals("−15K", RivalHeadToHead.formatRankDelta(-15_400, Locale.US))
        assertEquals("+1.5M", RivalHeadToHead.formatRankDelta(1_500_000, Locale.US))
        assertEquals("+2M", RivalHeadToHead.formatRankDelta(2_000_000, Locale.US))
        assertEquals("−12M", RivalHeadToHead.formatRankDelta(-12_345_678, Locale.US))
        assertEquals("+20", RivalHeadToHead.formatScoreDiff(song(20), Locale.US))
        assertEquals("−7,000", RivalHeadToHead.formatScoreDiff(song(0).copy(userScore = 1000, rivalScore = 8000), Locale.US))
        assertEquals("+0", RivalHeadToHead.formatScoreDiff(song(0).copy(userScore = null, rivalScore = null), Locale.US))
        assertEquals(-7000L, RivalHeadToHead.scoreDiff(song(0).copy(userScore = 1000, rivalScore = 8000)))
    }

    @Test
    fun spokenScoreGapsUseFullCountsWithoutSignsAndSingularNouns() {
        assertEquals("Rival leads by 15,400 ranks", RivalHeadToHead.leaderPhrase(-15_400, "Rival", Locale.US))
        assertEquals("your score is 20 points higher", RivalHeadToHead.spokenScoreDiff(song(20), Locale.US))
        assertEquals("your score is 1 point higher", RivalHeadToHead.spokenScoreDiff(song(1), Locale.US))
        assertEquals("your score is 7,000 points lower", RivalHeadToHead.spokenScoreDiff(song(0).copy(userScore = 1000, rivalScore = 8000), Locale.US))
        assertEquals("your score is 1 point lower", RivalHeadToHead.spokenScoreDiff(song(0).copy(userScore = 999, rivalScore = 1000), Locale.US))
        assertEquals("same score", RivalHeadToHead.spokenScoreDiff(song(0).copy(userScore = null, rivalScore = null), Locale.US))
    }

    @Test
    fun leaderPhraseIsSpokenUnsignedAndPluralised() {
        assertEquals("you lead by 1 rank", RivalHeadToHead.leaderPhrase(1, "Rival", Locale.US))
        assertEquals("you lead by 12,345 ranks", RivalHeadToHead.leaderPhrase(12_345, "Rival", Locale.US))
        assertEquals("Rival leads by 1 rank", RivalHeadToHead.leaderPhrase(-1, "Rival", Locale.US))
        assertEquals("Rival leads by 3 ranks", RivalHeadToHead.leaderPhrase(-3, "Rival", Locale.US))
        assertEquals("tied", RivalHeadToHead.leaderPhrase(0, "Rival", Locale.US))
    }

    // endregion

    // region Columns

    @Test
    fun columnsFollowWidthAndHinge() {
        assertEquals(listOf(400), HingeColumns.resolve(0, 400, null, null, 360, 16, 3).widths)
        val two = HingeColumns.resolve(0, 800, null, null, 360, 16, 3)
        assertEquals(2, two.count)
        assertEquals(800, two.widths.sum() + two.spacing)
        assertEquals(3, HingeColumns.resolve(0, 1400, null, null, 360, 16, 3).count)
        assertEquals(2, HingeColumns.resolve(0, 1400, null, null, 360, 16, 2).count)
        // A 20 px hinge at window x=1000..1020 over content starting at x=100.
        val split = HingeColumns.resolve(100, 1800, 1000, 1020, 360, 16, 3)
        assertEquals(listOf(900, 880), split.widths)
        assertEquals(20, split.spacing)
        // Zero-width fold uses the normal gutter centred on the fold.
        val flat = HingeColumns.resolve(0, 2000, 1000, 1000, 360, 16, 3)
        assertEquals(listOf(992, 992), flat.widths)
        // A fold near the content edge does not split.
        assertEquals(1, HingeColumns.resolve(0, 400, 390, 400, 360, 16, 3).count)
        assertEquals(1, HingeColumns.resolve(0, 0, null, null, 360, 16, 0).count)
    }

    @Test
    fun fullLineItemsKeepToTheLeadingPaneOnlyWhenSplit() {
        // Issue #343: titles and subtitles stay on their side of a separating hinge.
        val split = HingeColumns.resolve(100, 1800, 1000, 1020, 360, 16, 3)
        assertTrue(split.split)
        assertEquals(900, split.leadingPane(rtl = false))
        assertEquals(880, split.leadingPane(rtl = true))
        // Flat (no hinge) and a fold too near the edge to split fill the line.
        assertNull(HingeColumns.resolve(0, 2000, null, null, 360, 16, 3).leadingPane(rtl = false))
        assertNull(HingeColumns.resolve(0, 400, 390, 400, 360, 16, 3).leadingPane(rtl = false))
    }

    // endregion

    // region Routes

    @Test
    fun routesCarryTypedScope() {
        val scope = RivalScope.Leaderboard(Instrument.Bass)
        assertEquals(AllRivalsRoute("leaderboard:Solo_Bass:totalscore"), RivalRoutes.allRivals(scope))
        val detail = RivalRoutes.detail(ids[0], "N", RivalScope.FromSettings(RivalSettingsScope.All), allowLiveFallback = true)
        assertEquals(RivalDetailRoute(ids[0], "N", "settings:all", true), detail)
        assertEquals(RivalryRoute(ids[0], "almost_passed", "N", "settings:all", true), RivalRoutes.rivalry(detail, "almost_passed", null))
        assertEquals(RivalDetailRoute(ids[0], null, null, false), RivalRoutes.detail(ids[0], null, null))
    }

    @Test
    fun debugRoutesParse() {
        assertEquals(AllRivalsRoute("song:Solo_Guitar"), DebugLaunch.parseRoute("allRivals:song:Solo_Guitar"))
        assertEquals(RivalDetailRoute(ids[0], scope = "leaderboard:Solo_Bass:totalscore"), DebugLaunch.parseRoute("rivalDetail:${ids[0]}:leaderboard:Solo_Bass:totalscore"))
        assertEquals(RivalDetailRoute(ids[0]), DebugLaunch.parseRoute("rivalDetail:${ids[0]}"))
        assertEquals(RivalryRoute(ids[0], "closest_battles", scope = "combo:03"), DebugLaunch.parseRoute("rivalry:${ids[0]}:closest_battles:combo:03"))
        assertEquals(RivalryRoute(ids[0], "closest_battles"), DebugLaunch.parseRoute("rivalry:${ids[0]}:closest_battles"))
        listOf("allRivals", "allRivals:song:Nope", "rivalDetail:bad id", "rivalDetail:${ids[0]}:song:Nope", "rivalry:${ids[0]}", "rivalry:bad id:x", "rivalry:${ids[0]}:x:nope").forEach {
            assertNull(it, DebugLaunch.parseRoute(it))
        }
        assertNull(RivalRoutes.parseDebug("other", "x"))
    }

    // endregion

    @Test
    fun quickLinksMatchTheWebItems() {
        // Compete: the two groups, trophy then people.
        assertEquals(listOf("leaderboards" to "trophy", "rivals" to "people"), RivalQuickLinks.compete().map { it.id to it.icon })
        // Hub: Common → people, combo → notes, a chart → its icon.
        assertEquals("people", RivalQuickLinks.hub("common", "Common Rivals", null).icon)
        assertEquals("music", RivalQuickLinks.hub("combo", "Lead + Bass Rivals", null).icon)
        val lead = RivalQuickLinks.hub("leaderboard.Solo_Guitar", "Lead Rivals", Instrument.Lead)
        assertEquals(Instrument.Lead, lead.instrument)
        assertNull(lead.icon)
        // Rival Detail: web `rival-category:<key>` with the category title.
        val categories = listOf(RivalCategory("almost_passed", "Almost Passed", "d", RivalSentiment.entries.first(), emptyList()))
        assertEquals(listOf("rival-category:almost_passed" to "Almost Passed"), RivalQuickLinks.rivalDetail(categories).map { it.id to it.title })
    }
}
