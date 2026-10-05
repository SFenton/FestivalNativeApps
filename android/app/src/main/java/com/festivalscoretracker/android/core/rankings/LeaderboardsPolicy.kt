package com.festivalscoretracker.android.core.rankings

import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardEntry
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardResponse
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.SongLeaderboardRoute
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.profile.PlayerScore

// region Navigation

/** Where a rankings row leads (web `getPlayerRoute` / band row links). */
object RankingNavigation {
    /**
     * Route for a player row: Statistics for the selected player (web
     * `RankingCard.tsx` `getPlayerRoute`), their profile otherwise.
     *
     * @param accountId Row account.
     * @param displayName Row name, carried for the destination title.
     * @param selectedAccountId Selected player, or null.
     * @return Route, or null for anonymous/malformed rows (not interactive).
     */
    fun playerRoute(accountId: String, displayName: String?, selectedAccountId: String?): AppRoute? = when {
        !ProfileSearchText.isValidAccountId(accountId) -> null
        RankingSpotlight.isSelected(selectedAccountId, accountId) -> StatisticsRoute
        else -> PlayerRoute(accountId, displayName?.takeIf { it.isNotBlank() })
    }

    /**
     * TalkBack click label for a player row, named after where it actually leads (iOS
     * `SongPreviewSpotlightPolicy.hint`, issue #63): the selected player's in-place row opens
     * Statistics, their appended row past the preview opens their page of the full board.
     *
     * @param route Row destination from [playerRoute] or the spotlight row's board page.
     * @return Action label.
     */
    fun actionLabel(route: AppRoute): String = when (route) {
        StatisticsRoute -> "Open your statistics"
        is SongLeaderboardRoute -> "Open your page of the full leaderboard"
        is BandRoute -> "Open band"
        else -> "Open profile"
    }

    /**
     * Route for a band row. Carries `bandType`/`teamKey` so Band Detail resolves via
     * the safe `?teamKey=` rankings read, never the side-effecting `/api/bands/{id}`.
     *
     * @param entry Band row.
     * @param bandType Board's band size.
     * @return Route, or null when the row lacks a usable identity.
     */
    fun bandRoute(entry: BandRankingEntry, bandType: BandType): AppRoute? =
        if (entry.hasDetail) BandRoute(entry.bandId, name = null, bandType = bandType.wireId, teamKey = entry.teamKey) else null
}

// endregion

// region Adaptive layout

/** Width rules for the Leaderboards surfaces (Material 3 window size classes). */
object LeaderboardsLayoutPolicy {
    /** Minimum overview card width before another column is added. */
    const val MIN_CARD_DP = 340

    /** Gap between cards and around the grid. */
    const val GAP_DP = 16

    /** Maximum overview columns. */
    const val MAX_COLUMNS = 4

    /** Content width at which paginated boards gain a supporting pane (expanded class). */
    const val SUPPORTING_PANE_MIN_DP = 840

    /** Supporting pane width on expanded boards. */
    const val SUPPORTING_PANE_DP = 360

    /**
     * Overview card columns for the available content width: one on compact,
     * more on medium/expanded; exactly two around a separating vertical hinge so no
     * card straddles the fold.
     *
     * @param widthDp Content width in dp.
     * @param separatingHinge Whether a vertical separating hinge crosses the content.
     * @return Column count in `1..MAX_COLUMNS`.
     */
    fun columns(widthDp: Int, separatingHinge: Boolean = false): Int {
        if (separatingHinge) return 2
        val usable = widthDp - 2 * GAP_DP + GAP_DP
        return (usable / (MIN_CARD_DP + GAP_DP)).coerceIn(1, MAX_COLUMNS)
    }

    /**
     * Whether a paginated board shows its controls in a supporting pane beside the list.
     *
     * @param widthDp Content width in dp.
     * @param separatingHinge Whether a vertical separating hinge crosses the content.
     * @return True on expanded widths or around a hinge (list on one side, controls on the other).
     */
    fun showsSupportingPane(widthDp: Int, separatingHinge: Boolean = false): Boolean =
        separatingHinge || widthDp >= SUPPORTING_PANE_MIN_DP
}

// endregion

// region Song leaderboard footer

/** The selected player's pinned row on a per-song solo leaderboard (web `LeaderboardPage.tsx` footer). */
object SongScoreSpotlight {
    /**
     * Build the pinned footer row from the selected player's score index.
     *
     * Only projects a score observed under the same publication as the board
     * (never a newer score index onto an older page, or the reverse), and only when
     * the player's row is not already on the page.
     *
     * @param player Selected player, or null.
     * @param score Their score on this song and chart, or null.
     * @param scorePublicationId Publication the score index was observed under.
     * @param boardPublicationId Publication the page was read under.
     * @param visible Rows on the current page.
     * @return Footer row, or null when nothing should be pinned.
     */
    fun footer(
        player: SelectedPlayer?,
        score: PlayerScore?,
        scorePublicationId: Int?,
        boardPublicationId: Int,
        visible: List<LeaderboardEntry>,
    ): LeaderboardEntry? {
        if (player == null || score == null || scorePublicationId != boardPublicationId) return null
        if (visible.any { RankingSpotlight.isSelected(player.accountId, it.accountId) }) return null
        return LeaderboardEntry(
            accountId = player.accountId,
            displayName = player.displayName,
            score = score.score,
            rank = score.rank ?: 0,
            accuracy = score.accuracy,
            isFullCombo = score.isFullCombo,
            stars = score.stars,
            season = score.season,
            difficulty = score.difficulty,
        )
    }
}

// endregion

// region Song band leaderboard footer

/**
 * The selected player's band pinned above the pager on a song's full Duos/Trios/Quads board
 * (web `SongBandLeaderboardPage` `FixedLeaderboardPlayerFooter`, issue #306). Like the web
 * (`hasSelectedFooter = !!selectedEntry`), it is pinned on every page while the response
 * carries the selected band; on the band's own page its row is also highlighted in place.
 */
object SongBandSpotlight {
    /**
     * The selected player's band row from a page read with their `accountId`.
     *
     * @param response Page.
     * @param selectedAccountId Selected player, or null.
     * @return Their band row (on or off this page), or null when no player is selected, the
     *   response is for another player or band size, or they have no score at this size.
     */
    fun selected(response: SongBandLeaderboardResponse, selectedAccountId: String?): SongBandLeaderboardEntry? {
        val band = response.selectedPlayerEntry ?: return null
        if (selectedAccountId.isNullOrBlank() || band.bandType != response.bandType) return null
        val ids = band.members.map { it.accountId } + band.teamKey.split(':')
        return band.takeIf { ids.any { it.equals(selectedAccountId, ignoreCase = true) } }
    }

    /**
     * Whether a page row is the selected player's band (purple in-place highlight).
     *
     * @param entry Page row.
     * @param selected [selected] for the page, or null.
     * @return True for the same band.
     */
    fun isSelected(entry: SongBandLeaderboardEntry, selected: SongBandLeaderboardEntry?): Boolean =
        selected != null && entry.sameBand(selected)

    /**
     * The pinned footer row, shaped like the solo footer's row (web passes the band to the
     * solo `LeaderboardEntry`: rank, joined member names, score, season, accuracy, FC, stars).
     *
     * @param response Page.
     * @param selectedAccountId Selected player, or null.
     * @return Footer row (whether or not the band is on this page), or null when there is
     *   nothing to pin.
     */
    fun footer(response: SongBandLeaderboardResponse, selectedAccountId: String?): LeaderboardEntry? {
        val band = selected(response, selectedAccountId) ?: return null
        return LeaderboardEntry(
            // Non-empty, so the row shows the names rather than "Unknown User".
            accountId = band.bandId.ifEmpty { band.teamKey }.ifEmpty { selectedAccountId.orEmpty() },
            displayName = band.membersLabel,
            score = band.score.coerceIn(0L, Int.MAX_VALUE.toLong()).toInt(),
            rank = band.rank,
            // A band's 0 accuracy is "not recorded" (BandScoreRow reads it the same way).
            accuracy = band.accuracy?.takeIf { it > 0 },
            isFullCombo = band.isFullCombo,
            stars = band.stars?.takeIf { it > 0 },
            season = band.season,
        )
    }

    /**
     * Band Detail for a band row (web `getBandProfileRoute`): carries size and team key so the
     * page resolves through the safe `?teamKey=` rankings read.
     *
     * @param entry Band row.
     * @return Route.
     */
    fun route(entry: SongBandLeaderboardEntry): BandRoute =
        BandRoute(entry.bandId.ifEmpty { entry.teamKey }, entry.membersLabel, entry.bandType, entry.teamKey)
}

// endregion
