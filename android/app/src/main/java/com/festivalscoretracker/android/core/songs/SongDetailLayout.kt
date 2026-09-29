package com.festivalscoretracker.android.core.songs

// region Song Detail layout

/**
 * Pure Song Detail layout rules (web `SongDetailPage`): when the page may reveal and
 * how many instrument-card columns fit.
 */
object SongDetailLayout {
    /**
     * Content width from which instrument cards sit two per row (two ≥ 292 dp cards
     * plus the gap; the web's `minmax(420px, 50%)` grid at CSS px ≈ 1.4 dp).
     */
    const val TWO_COLUMN_MIN_DP = 600f

    /**
     * Whether everything the page waits for has settled (web `allReady`: every visible
     * chart's preview and the selected player's history, loaded or failed).
     *
     * @param previewsLoading Whether each preview is still loading.
     * @param historyLoading Whether the history is still loading, or null without a selected player.
     * @return True to reveal.
     */
    fun ready(previewsLoading: List<Boolean>, historyLoading: Boolean?): Boolean = previewsLoading.none { it } && historyLoading != true

    /**
     * Instrument-card columns.
     *
     * @param contentWidthDp Width inside the page margins.
     * @param cards Visible charts.
     * @param hinge A separating vertical hinge crosses the page (cards go either side of it).
     * @return 1 or 2.
     */
    fun columns(contentWidthDp: Float, cards: Int, hinge: Boolean): Int = when {
        cards < 2 -> 1
        hinge -> 2
        contentWidthDp >= TWO_COLUMN_MIN_DP -> 2
        else -> 1
    }
}

// endregion
