package com.festivalscoretracker.android.core.rankings

import com.festivalscoretracker.android.core.model.LeaderboardPaging

// region Selected-row action

/**
 * What tapping the selected profile's own row does, shared by the solo and band song
 * leaderboards so a player and a band follow one rule (`leaderboard-row` R7, issue #307;
 * web `getLeaderboardPageForRank` footers, Apple `SelectedRowAction`):
 *
 * - a row shown *apart from* its page (Song Detail's row appended after a top-ten preview,
 *   or a full board's pinned footer while the row is on another page) jumps to the page
 *   containing its rank, where the board reveals the highlighted row;
 * - a selected row already on screen opens the profile: Statistics for the selected player,
 *   the Band page for a band.
 *
 * Rows of other players and bands always open that player's profile or band page.
 */
sealed interface SelectedRowAction {
    /**
     * Show the full board's page that contains the row, revealing it.
     *
     * @property page One-based page.
     */
    data class Jump(val page: Int) : SelectedRowAction

    /** Open the selected profile (Statistics, or the Band page). */
    data object OpenProfile : SelectedRowAction

    companion object {
        /**
         * The action for a full board's pinned footer row (web `LeaderboardPage` /
         * `SongBandLeaderboardPage` footer `onClick`).
         *
         * @param rank The selected row's one-based rank on this board.
         * @param isVisible Whether the row is on the page being shown.
         * @param currentPage The board's current one-based page.
         * @param pageSize Rows per page.
         * @return [Jump] to the page holding [rank] when the row isn't visible and that page
         *   isn't the current one; [OpenProfile] otherwise (also for an unusable rank).
         */
        fun footer(rank: Int, isVisible: Boolean, currentPage: Int, pageSize: Int = LeaderboardPaging.PAGE_SIZE): SelectedRowAction {
            if (isVisible || rank <= 0 || pageSize <= 0) return OpenProfile
            val target = LeaderboardPaging.pageForRank(rank, pageSize)
            return if (target == currentPage) OpenProfile else Jump(target)
        }

        /**
         * The action for Song Detail's selected row appended after a preview (it is never
         * on the board's page being shown, because no board is shown yet).
         *
         * @param rank The row's one-based rank on the full board.
         * @param pageSize Rows per page of the full board.
         * @return [Jump] to the page holding [rank], or [OpenProfile] for an unusable rank.
         */
        fun preview(rank: Int, pageSize: Int = LeaderboardPaging.PAGE_SIZE): SelectedRowAction =
            footer(rank, isVisible = false, currentPage = 0, pageSize = pageSize)
    }
}

/** Whose row a selected-row action belongs to. */
enum class SelectedRowSubject {
    /** The selected player's own score (solo boards). */
    Player,

    /** The selected player's band (band boards). */
    Band,
}

/**
 * TalkBack click label naming where the selected row leads (R7: "Jump to your band's
 * position" / "Open band").
 *
 * @param subject Player or band row.
 * @return Action label.
 */
fun SelectedRowAction.label(subject: SelectedRowSubject): String = when (subject) {
    SelectedRowSubject.Player -> if (this is SelectedRowAction.Jump) SelectedRowLabels.JUMP_TO_PLAYER else SelectedRowLabels.OPEN_STATISTICS
    SelectedRowSubject.Band -> if (this is SelectedRowAction.Jump) SelectedRowLabels.JUMP_TO_BAND else SelectedRowLabels.OPEN_BAND
}

/** The selected-row click labels (web `aria-label`s, Apple `footerLabel`). */
object SelectedRowLabels {
    /** Player row that jumps to its page. */
    const val JUMP_TO_PLAYER = "Jump to your position"

    /** Player row that opens Statistics. */
    const val OPEN_STATISTICS = "Open your statistics"

    /** Band row that jumps to its page. */
    const val JUMP_TO_BAND = "Jump to your band's position"

    /** Band row that opens the Band page. */
    const val OPEN_BAND = "Open band"
}

// endregion

// region Reveal

/** Scroll math for revealing the selected row on arrival (web `scrollIntoView({ block: 'center' })`). */
object SelectedRowReveal {
    /**
     * Scroll distance that centres a row in the part of the list not covered by the pinned
     * footer and pager.
     *
     * @param rowTop Row top in the list's item coordinates (px).
     * @param rowHeight Row height (px).
     * @param visibleStart First visible offset (the list's `viewportStartOffset`).
     * @param visibleEnd Last offset not under the pinned footer (px).
     * @return Pixels to scroll by (positive scrolls the content up); the list clamps it.
     */
    fun centerDelta(rowTop: Int, rowHeight: Int, visibleStart: Int, visibleEnd: Int): Float {
        val center = rowTop + rowHeight / 2f
        val visibleCenter = visibleStart + (visibleEnd - visibleStart).coerceAtLeast(0) / 2f
        return center - visibleCenter
    }

    /**
     * How long the reveal waits before scrolling: until the selected row's own entrance has
     * finished, like the web's `navToPlayer` / `navToBand`, which scroll after the row's
     * stagger plus its fade (load-transition R5, issue #323). Rows that have not faded in by
     * then are rushed by the reveal's scroll. No wait under Reduce Motion (R6).
     *
     * @param rowDelayMillis The selected row's stagger delay.
     * @param fadeMillis Fade duration.
     * @param reduceMotion Remove animations / Reduce Motion.
     * @return Milliseconds to wait.
     */
    fun entranceWaitMillis(rowDelayMillis: Int, fadeMillis: Int, reduceMotion: Boolean): Int =
        if (reduceMotion) 0 else rowDelayMillis.coerceAtLeast(0) + fadeMillis.coerceAtLeast(0)
}

// endregion
