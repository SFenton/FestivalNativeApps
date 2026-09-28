package com.festivalscoretracker.android.core.profile

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import com.festivalscoretracker.android.core.rivals.ColumnSpec
import com.festivalscoretracker.android.core.rivals.HingeColumns
import kotlin.math.max
import kotlin.math.roundToInt

// region Fold-aware columns

/**
 * Resolved player-page columns.
 *
 * @property spec Column widths and spacing in pixels.
 * @property splitAtFold Whether every crossing fold sits in a gap between columns, so
 *   full-width rows (header, headings, Bands) must stay in one lane or they would straddle it.
 */
data class ProfileGridSpec(val spec: ColumnSpec, val splitAtFold: Boolean)

/**
 * The player page's column policy: [HingeColumns] (one column per [minColumn], or two
 * columns meeting at one separating vertical hinge), extended to several separating
 * vertical hinges (a tri-fold partly folded) with one column per panel, so no card
 * straddles any fold. Only WindowManager hinge bounds participate, never device names.
 */
object ProfileColumns {
    /**
     * Resolve columns for the grid's window bounds.
     *
     * @param contentStart Grid's left edge in window pixels.
     * @param contentWidth Grid width in pixels.
     * @param hinges Separating vertical hinges as (left, right) window pixels, any order.
     * @param minColumn Minimum column width in pixels.
     * @param gutter Normal gap between columns in pixels.
     * @param maxColumns Upper bound on columns without hinges.
     * @return Columns and whether they are split at the folds.
     */
    fun resolve(contentStart: Int, contentWidth: Int, hinges: List<Pair<Int, Int>>, minColumn: Int, gutter: Int, maxColumns: Int): ProfileGridSpec {
        val width = max(contentWidth, 1)
        val crossing = hinges
            .map { (left, right) -> (left - contentStart) to (right - contentStart) }
            .filter { (left, right) -> right > 0 && left < width }
            .sortedBy { it.first }
        val spec = when {
            crossing.size <= 1 -> {
                val hinge = crossing.firstOrNull()
                HingeColumns.resolve(0, width, hinge?.first, hinge?.second, minColumn, gutter, maxColumns)
            }
            else -> panels(width, crossing, minColumn, gutter) ?: HingeColumns.resolve(0, width, null, null, minColumn, gutter, maxColumns)
        }
        return ProfileGridSpec(spec, crossing.isNotEmpty() && crossing.all { gapContains(spec, it) })
    }

    /** One column per panel between folds, or null when a panel is too narrow for a column. */
    private fun panels(width: Int, crossing: List<Pair<Int, Int>>, minColumn: Int, gutter: Int): ColumnSpec? {
        val spacing = max(gutter, crossing.maxOf { (left, right) -> max(right - left, 0) })
        val cuts = crossing.flatMap { (left, right) ->
            val center = (left + right) / 2.0
            listOf((center - spacing / 2.0).roundToInt(), (center - spacing / 2.0).roundToInt() + spacing)
        }
        val edges = listOf(0) + cuts + width
        val widths = edges.chunked(2).map { (start, end) -> end - start }
        return if (widths.all { it >= minColumn / 2 }) ColumnSpec(widths, spacing) else null
    }

    /** Whether a gap between two columns covers a fold (grid-relative pixels). */
    private fun gapContains(spec: ColumnSpec, hinge: Pair<Int, Int>): Boolean {
        if (spec.count < 2) return false
        var x = 0
        for (index in 0 until spec.count - 1) {
            x += spec.widths[index]
            if (hinge.first >= x && hinge.second <= x + spec.spacing) return true
            x += spec.spacing
        }
        return false
    }
}

// endregion

// region Sections and Quick Links

/** Player-page rows, in web order (`PlayerContent.tsx`). */
sealed interface ProfileRow {
    /** Stable lazy key. */
    val key: String

    /** Header with identity actions. */
    data object Header : ProfileRow {
        override val key: String get() = "header"
    }

    /** Overview tiles (web Global Statistics). */
    data object Overview : ProfileRow {
        override val key: String get() = "overview"
    }

    /**
     * One chart's statistics card.
     *
     * @property instrument Chart.
     */
    data class InstrumentStats(val instrument: Instrument) : ProfileRow {
        override val key: String get() = "instrument:${instrument.wireId}"
    }

    /** "Top Songs Per Instrument" heading. */
    data object TopSongsHeading : ProfileRow {
        override val key: String get() = "top-songs"
    }

    /**
     * One chart's top/bottom five card.
     *
     * @property instrument Chart.
     */
    data class TopSongs(val instrument: Instrument) : ProfileRow {
        override val key: String get() = "top-songs:${instrument.wireId}"
    }

    /** Link to the player's bands. */
    data object Bands : ProfileRow {
        override val key: String get() = "bands"
    }

    /** Whether the row spans every column when no fold splits them. */
    val fullWidth: Boolean get() = this !is InstrumentStats && this !is TopSongs
}

/** Row order and Quick Links for the player page (web `PlayerContent` quick links). */
object ProfileSections {
    /**
     * Rows for a loaded profile.
     *
     * @param visible Settings-visible charts in service order.
     * @return Rows in page order.
     */
    fun rows(visible: List<Instrument>): List<ProfileRow> =
        listOf(ProfileRow.Header, ProfileRow.Overview) +
            visible.map { ProfileRow.InstrumentStats(it) } +
            ProfileRow.TopSongsHeading +
            visible.map { ProfileRow.TopSongs(it) } +
            ProfileRow.Bands

    /**
     * Quick Links, in web order: Global Statistics, one per visible chart, Top Songs, Bands.
     * IDs are the web's (`global`, `instrument:<wire>`, `top-songs`, `bands`) and equal the row keys they jump to.
     *
     * @param visible Settings-visible charts in service order.
     * @param displayName Player name (Bands landmark label).
     * @return Sections.
     */
    fun quickLinks(visible: List<Instrument>, displayName: String): List<QuickLinkSection> =
        listOf(QuickLinkSection("global", "Global Statistics", icon = "chart")) +
            visible.map { QuickLinkSection("instrument:${it.wireId}", it.label, instrument = it, spokenTitle = "${it.label} statistics") } +
            QuickLinkSection("top-songs", "Top Songs", icon = "music", spokenTitle = "Top Songs Per Instrument") +
            QuickLinkSection("bands", "Bands", icon = "people", spokenTitle = "$displayName's Bands")

    /**
     * The row a Quick Link jumps to.
     *
     * @param id Section ID.
     * @return Row key.
     */
    fun rowKey(id: String): String = if (id == "global") ProfileRow.Overview.key else id
}

// endregion
