package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection

// region Page items

/**
 * One Song Detail list item, in page order. [sections] are the Quick Links IDs the item
 * holds (web `registerSectionRef` IDs), so a jump or `?instrument=` scroll finds its row.
 */
sealed interface SongDetailItem {
    /** Stable lazy-list key. */
    val key: String

    /** Quick Links section IDs inside this item. */
    val sections: List<String>

    /** Album art, title and subtitle. */
    data object Header : SongDetailItem {
        override val key = "header"
        override val sections = emptyList<String>()
    }

    /** Paths / Item Shop buttons. */
    data object Actions : SongDetailItem {
        override val key = "actions"
        override val sections = emptyList<String>()
    }

    /** Full-width Intensity card. */
    data object Intensity : SongDetailItem {
        override val key = "intensity"
        override val sections = listOf(SongDetailLayout.INTENSITY_ID)
    }

    /** Full-width Score History card. */
    data object History : SongDetailItem {
        override val key = "history"
        override val sections = listOf(SongDetailLayout.HISTORY_ID)
    }

    /**
     * Intensity and Score History on either side of a separating hinge; without history
     * the Intensity grid itself is split across the hinge. Nothing straddles the fold.
     *
     * @property history Whether Score History takes the trailing side.
     */
    data class HingeSummary(val history: Boolean) : SongDetailItem {
        override val key = "summary"
        override val sections = listOfNotNull(SongDetailLayout.INTENSITY_ID, SongDetailLayout.HISTORY_ID.takeIf { history })
    }

    /**
     * One row of instrument leaderboard cards.
     *
     * @property charts Charts in this row (at most the column count).
     */
    data class Instruments(val charts: List<Instrument>) : SongDetailItem {
        override val key = "instruments:" + charts.joinToString(",") { it.wireId }
        override val sections = charts.map(SongDetailLayout::instrumentId)
    }

    /**
     * One row of band leaderboard previews (one per row, two either side of a hinge).
     *
     * @property types Band sizes in this row.
     */
    data class Bands(val types: List<BandType>) : SongDetailItem {
        override val key = "bands:" + types.joinToString(",") { it.wireId }
        override val sections = types.map(SongDetailLayout::bandId)
    }
}

// endregion

// region Song Detail layout

/**
 * Pure Song Detail layout rules (web `SongDetailPage`): when the page may reveal, how
 * many instrument-card columns fit, the item order and the Quick Links.
 */
object SongDetailLayout {
    /**
     * Content width from which instrument cards sit two per row (two ≥ 292 dp cards
     * plus the gap; the web's `minmax(420px, 50%)` grid at CSS px ≈ 1.4 dp).
     */
    const val TWO_COLUMN_MIN_DP = 600f

    /** Web `SONG_DETAIL_INTENSITY_QUICK_LINK_ID`. */
    const val INTENSITY_ID = "intensity"

    /** Web `SONG_DETAIL_SCORE_HISTORY_QUICK_LINK_ID`. */
    const val HISTORY_ID = "score-history"

    /**
     * Web `songDetailInstrumentQuickLinkId`.
     *
     * @param chart Chart.
     * @return `instrument-<wireId>`.
     */
    fun instrumentId(chart: Instrument): String = "instrument-${chart.wireId}"

    /**
     * Web `songDetailBandQuickLinkId`.
     *
     * @param type Band size.
     * @return `band-<wireId>`.
     */
    fun bandId(type: BandType): String = "band-${type.wireId}"

    /**
     * Whether everything the page waits for has settled (web `allReady`: every visible
     * chart's preview, every band preview and the selected player's history, loaded or failed).
     *
     * @param previewsLoading Whether each preview (instrument and band) is still loading.
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

    /**
     * The page's items in web order: header, actions, Intensity, Score History,
     * instrument rows, band previews last (web `trailingSongBandTypes`; promoting the
     * selected band's size needs a selected-band identity, which Android doesn't have yet).
     * At a separating hinge Intensity/History share one split row and bands pair up.
     *
     * @param charts Visible charted instruments.
     * @param columns Instrument columns ([columns]).
     * @param history Whether Score History shows.
     * @param hinge A separating vertical hinge crosses the page.
     * @param bands Band sizes with previews.
     * @return Items in order.
     */
    fun items(charts: List<Instrument>, columns: Int, history: Boolean, hinge: Boolean, bands: List<BandType>): List<SongDetailItem> = buildList {
        add(SongDetailItem.Header)
        add(SongDetailItem.Actions)
        if (hinge) {
            add(SongDetailItem.HingeSummary(history))
        } else {
            add(SongDetailItem.Intensity)
            if (history) add(SongDetailItem.History)
        }
        charts.chunked(columns.coerceAtLeast(1)).forEach { add(SongDetailItem.Instruments(it)) }
        bands.chunked(if (hinge) 2 else 1).forEach { add(SongDetailItem.Bands(it)) }
    }

    /**
     * Split the Intensity charts across a hinge: the leading side takes the first half
     * (rounded up), keeping the web's two-per-row cells on each side.
     *
     * @param charted Charted instruments.
     * @return Leading and trailing charts.
     */
    fun splitIntensity(charted: List<Instrument>): Pair<List<Instrument>, List<Instrument>> {
        val lead = (charted.size + 1) / 2
        return charted.take(lead) to charted.drop(lead)
    }

    /**
     * Web Song Detail Quick Links: Intensity, Score History (when shown), each chart,
     * then each band size.
     *
     * @param charts Visible charted instruments.
     * @param history Whether Score History shows.
     * @param bands Band sizes with previews.
     * @return Sections in order.
     */
    fun quickLinks(charts: List<Instrument>, history: Boolean, bands: List<BandType>): List<QuickLinkSection> = buildList {
        add(QuickLinkSection(INTENSITY_ID, "Intensity", icon = "chart", spokenTitle = "Song Intensity"))
        if (history) add(QuickLinkSection(HISTORY_ID, "Score History", icon = "timer"))
        charts.forEach { add(QuickLinkSection(instrumentId(it), it.label, instrument = it, spokenTitle = "${it.label} Leaderboard")) }
        bands.forEach { add(QuickLinkSection(bandId(it), it.label, icon = "people", spokenTitle = "${it.label} Band Leaderboard")) }
    }

    /**
     * The item holding a section.
     *
     * @param items Page items.
     * @param id Section ID.
     * @return Item index, or null.
     */
    fun indexOf(items: List<SongDetailItem>, id: String): Int? = items.indexOfFirst { id in it.sections }.takeIf { it >= 0 }

    /**
     * The `?instrument=` focus (web `resolvedDefaultInstrument`): only a visible chart counts.
     *
     * @param wireId Route instrument, or null.
     * @param charts Visible charted instruments.
     * @return The chart, or null.
     */
    fun focus(wireId: String?, charts: List<Instrument>): Instrument? = Instrument.fromWireId(wireId)?.takeIf { it in charts }
}

// endregion
