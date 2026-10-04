package com.festivalscoretracker.android.core.compete

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rivals.RivalCombo
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import kotlinx.serialization.Serializable

// region Scopes

/**
 * One Compete ranking scope (web `utils/rankingScopes.ts` `RankingScope`): a single
 * chart, or a within-group combo of the visible charts in one family.
 */
sealed interface CompeteScope {
    /** Stable key (web `scopeKey`): the chart wire ID or the hex combo ID. */
    val key: String

    /** Charts in service order. */
    val instruments: List<Instrument>

    /** Label (web `rankingScopeLabel`): chart names joined with " + ". */
    val label: String get() = instruments.joinToString(" + ") { it.label }

    /** The rivals list this scope reads and carries into All Rivals / Rival Detail. */
    val rivalScope: RivalScope

    /**
     * One chart.
     *
     * @property instrument Chart.
     */
    data class Single(val instrument: Instrument) : CompeteScope {
        override val key: String get() = instrument.wireId
        override val instruments: List<Instrument> get() = listOf(instrument)
        override val rivalScope: RivalScope get() = RivalScopes.song(listOf(instrument))
    }

    /**
     * A within-group combo (OG band or Pro Strings).
     *
     * @property comboId Hex combo ID.
     * @property instruments Constituent charts.
     */
    data class Combo(val comboId: String, override val instruments: List<Instrument>) : CompeteScope {
        override val key: String get() = comboId
        override val rivalScope: RivalScope get() = RivalScope.Combo(comboId)
    }
}

/** Native port of `resolveSupportedRankingScopes`. */
object CompeteScopes {
    private data class Family(val instruments: List<Instrument>, val supportsCombo: Boolean)

    private val FAMILIES = listOf(
        Family(listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals), supportsCombo = true),
        Family(listOf(Instrument.ProLead, Instrument.ProBass), supportsCombo = true),
        Family(listOf(Instrument.Karaoke, Instrument.ProCymbals, Instrument.ProDrums), supportsCombo = false),
    )

    /**
     * Scopes for the visible charts: per family, the combo first (two or more charts
     * in a combo family), then each chart.
     *
     * @param visible Settings-visible charts.
     * @return Scopes in web order.
     */
    fun resolve(visible: Collection<Instrument>): List<CompeteScope> = FAMILIES.flatMap { family ->
        val selected = family.instruments.filter { it in visible }
        val singles = selected.map { CompeteScope.Single(it) }
        if (selected.size < 2 || !family.supportsCombo) singles else listOf(CompeteScope.Combo(RivalCombo.comboId(selected), selected)) + singles
    }
}

// endregion

// region Combo rankings

/**
 * One row of `GET /api/rankings/combo` (web `ComboRankingEntry`). Anonymous
 * production rows may lack an account ID or name.
 */
@Serializable
data class ComboRankingEntry(
    val rank: Int = 0,
    val accountId: String = "",
    val displayName: String? = null,
    val adjustedRating: Double = 0.0,
    val weightedRating: Double = 0.0,
    val fcRate: Double = 0.0,
    val totalScore: Long = 0,
    val maxScorePercent: Double = 0.0,
    val songsPlayed: Int = 0,
    val totalChartedSongs: Int = 0,
    val fullComboCount: Int = 0,
) {
    /**
     * The shared account-row shape so Compete reuses the Leaderboards row (Total Score).
     *
     * @return Equivalent account entry.
     */
    fun asAccountEntry(): AccountRankingEntry = AccountRankingEntry(
        accountId = accountId,
        displayName = displayName,
        songsPlayed = songsPlayed,
        totalChartedSongs = totalChartedSongs,
        fcRate = fcRate,
        totalScore = totalScore,
        totalScoreRank = rank,
        fullComboCount = fullComboCount,
    )
}

/** `GET /api/rankings/combo?combo=&rankBy=&page=&pageSize=` envelope. */
@Serializable
data class ComboRankingsResponse(
    val comboId: String = "",
    val rankBy: String = "",
    val page: Int = 1,
    val pageSize: Int = 0,
    val totalAccounts: Int = 0,
    val entries: List<ComboRankingEntry> = emptyList(),
) {
    /**
     * Reject a page for another combo or with impossible ranks.
     *
     * @param comboId Requested combo.
     * @throws FestivalApiException.InvalidResponse when inconsistent.
     */
    fun validate(comboId: String) {
        if (!this.comboId.equals(comboId, ignoreCase = true) || entries.any { it.rank < 1 } || totalAccounts < 0) {
            throw FestivalApiException.InvalidResponse()
        }
    }
}

// endregion

// region Text

/** Compete copy from the web `en.json` `compete.*` table. */
object CompeteText {
    const val TITLE = "Compete"
    const val LEADERBOARDS = "Leaderboards"
    const val RIVALS = "Rivals"
    const val NO_RIVALS_TITLE = "No Rivals Yet"
    const val NO_RANKINGS_TITLE = "No Scores Yet"
    const val VIEW_FULL_LEADERBOARDS = "View Full Leaderboards"
    const val VIEW_ALL_RIVALS = "View All Rivals"

    /**
     * `compete.noRivalsSubtitle`.
     *
     * @param scope Scope label.
     * @return Text.
     */
    fun noRivals(scope: String) = "No rivals found for $scope yet."

    /**
     * `compete.noRivalsTrackSubtitle`.
     *
     * @param scope Scope label.
     * @return Text.
     */
    fun trackForRivals(scope: String) = "Track a player to see your closest rivals for $scope."

    /**
     * `compete.noRankingsSubtitle`.
     *
     * @param scope Scope label.
     * @return Text.
     */
    fun noRankings(scope: String) = "No scores recorded yet for $scope."
}

// endregion

// region Header layout

/**
 * Whether a Compete card's scope header stacks its instrument icons above the title.
 *
 * Side by side, the 36 dp icons and the optional "See All" link take a fixed width; in a
 * narrow lane (a half-open book fold's panel, a 360 dp cover screen, a phone card with
 * See All) a four-instrument combo title was left a few dp and broke after every word.
 * Large text always stacks.
 */
object CompeteHeaderLayout {
    /** Instrument icon size (web `InstrumentHeader` SM). */
    const val ICON_DP = 36f

    /** Gap between icons. */
    const val ICON_GAP_DP = 2f

    /** Gap between the icons, the title and the link. */
    const val GAP_DP = 8f

    /** Narrowest width a single-instrument title ("Pro Cymbals") may take beside its icon. */
    const val MIN_TITLE_DP = 100f

    /**
     * Narrowest width a combo title may take beside its icons: about half the longest name
     * ("Lead + Bass + Drums + Tap Vocals", ~250 dp), so it wraps to two lines at most.
     */
    const val MIN_COMBO_TITLE_DP = 140f

    /** Width of the "See All ›" text button at the default font scale. */
    const val SEE_ALL_DP = 80f

    /**
     * Decide whether the header stacks.
     *
     * @param widthDp Header width in dp.
     * @param instruments Instrument icons in the header.
     * @param hasSeeAll Whether the "See All" link is shown.
     * @param largeText Whether the app's large-text mode is on (`isLargeText()`).
     * @return True to put the icons on their own line above the title.
     */
    fun stacks(widthDp: Float, instruments: Int, hasSeeAll: Boolean, largeText: Boolean): Boolean {
        if (largeText) return true
        val icons = instruments * ICON_DP + (instruments - 1).coerceAtLeast(0) * ICON_GAP_DP
        val link = if (hasSeeAll) GAP_DP + SEE_ALL_DP else 0f
        val title = if (instruments > 1) MIN_COMBO_TITLE_DP else MIN_TITLE_DP
        return widthDp < icons + GAP_DP + title + link
    }
}

// endregion
