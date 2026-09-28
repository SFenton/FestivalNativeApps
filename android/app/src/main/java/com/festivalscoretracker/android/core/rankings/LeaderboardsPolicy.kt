package com.festivalscoretracker.android.core.rankings

import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.StatisticsRoute

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
