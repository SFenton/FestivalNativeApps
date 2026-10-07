package com.festivalscoretracker.android.core.profile

import com.festivalscoretracker.android.core.bands.PlayerBandEntry
import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.core.bands.PlayerBandListResponse
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
        return if (widths.all { it >= minColumn / 2 }) ColumnSpec(widths, spacing, split = true) else null
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

// region Stat tiles

/**
 * Column count for the player page's stat-tile grids: two on phones, three or four as
 * the grid widens (an adaptive grid with a minimum tile width, clamped), matching
 * Apple's `StatGridColumns` (Lane AP3).
 */
object StatGridColumns {
    /** Narrowest tile in dp before a column is dropped. */
    const val MIN_TILE_DP = 140f

    /** Space between tiles in dp, both axes. */
    const val SPACING_DP = 8f

    /** Phones get at least two columns (one only at large font scales, see [count]). */
    const val MIN_COLUMNS = 2

    /** Font scale from which a phone may drop to one column (`LARGE_TEXT_SCALE`). */
    const val LARGE_TEXT_SCALE = 1.3f

    /** Wide grids stop at four so tiles never shrink to a sliver of text. */
    const val MAX_COLUMNS = 4

    /**
     * Columns for a grid width. The minimum tile width grows with the font scale; at
     * [LARGE_TEXT_SCALE] and above a narrow grid may drop to one column, so tile labels
     * ("SONGS PLAYED" at 200%) are not broken mid-word.
     *
     * @param widthDp Grid width in dp.
     * @param fontScale User font scale.
     * @return Between [MIN_COLUMNS] (1 at large text) and [MAX_COLUMNS].
     */
    fun count(widthDp: Float, fontScale: Float = 1f): Int {
        val tile = MIN_TILE_DP * fontScale.coerceAtLeast(1f)
        val min = if (fontScale >= LARGE_TEXT_SCALE) 1 else MIN_COLUMNS
        return ((widthDp + SPACING_DP) / (tile + SPACING_DP)).toInt().coerceIn(min, MAX_COLUMNS)
    }
}

/** Stat-tile value colours (`0xRRGGBB`; web `StatBox` `color`). */
object StatTints {
    /** Default value colour (web `Colors.accentBlueBright`). */
    const val DEFAULT: Int = 0x4C7DFF

    /** Gold stars, 100% full combos, top-5% percentiles (web `Colors.gold`). */
    const val GOLD: Int = 0xFFD700

    /** Every catalogue song played (web `Colors.statusGreen`). */
    const val GREEN: Int = 0x2ECC71

    /** Scores over the CHOpt threshold (web `Colors.statusRed`). */
    const val RED: Int = 0xC62828

    /**
     * Web average-accuracy colour: gold for a perfect 100% with every chart full-combed,
     * else `accuracyColor` (red at 0% to green at 100%).
     *
     * @param percent Average accuracy percent.
     * @param allFullCombos Whether the FC share is 100%.
     * @return Colour.
     */
    fun accuracy(percent: Double, allFullCombos: Boolean): Int =
        if (percent >= 100 && allFullCombos) GOLD else RankHistoryColors.accuracy(percent)

    /**
     * Web `pctGold`: gold for "Top 1%" to "Top 5%".
     *
     * @param text Percentile text.
     * @return Colour, or null for the default.
     */
    fun percentile(text: String): Int? = if (Regex("^Top [1-5]%$").matches(text)) GOLD else null
}

// endregion

// region Sections and Quick Links

/** Player-page rows, in web order (`PlayerContent.tsx`). */
sealed interface ProfileRow {
    /** Stable lazy key. */
    val key: String

    /**
     * Select/Switch and selection notices, with no avatar or name (the top bar names the
     * page, issue #97). Only present when it has something to show.
     */
    data object Identity : ProfileRow {
        override val key: String get() = "identity"
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

    /** "{name}'s Bands" heading with See All, plus the preview's loading or failure state (Quick Links target). */
    data object Bands : ProfileRow {
        override val key: String get() = "bands"
    }

    /**
     * A band-size group's header (web `BandGroupHeader`: "Duos", "Trios", "Quads").
     *
     * @property group Group.
     */
    data class BandGroupHeader(val group: PlayerBandGroup) : ProfileRow {
        override val key: String get() = "bands:${group.wireId}"
    }

    /**
     * One band card (web `PlayerBandCard`, one grid column like the web's `span: false`).
     *
     * @property group Group the card belongs to.
     * @property index Position in the group (fade-in stagger).
     * @property entry Band.
     */
    data class BandCard(val group: PlayerBandGroup, val index: Int, val entry: PlayerBandEntry) : ProfileRow {
        override val key: String get() = "bands:${group.wireId}:$index:${entry.key}"
    }

    /**
     * "No Bands Yet" for a group without bands (web `InstrumentEmptyState`).
     *
     * @property group Group.
     */
    data class BandsEmpty(val group: PlayerBandGroup) : ProfileRow {
        override val key: String get() = "bands:${group.wireId}:empty"
    }

    /**
     * "View All Bands (N)" when the group has more bands than its preview.
     *
     * @property group Group the full list opens filtered to.
     * @property total Bands in the group.
     */
    data class BandsViewAll(val group: PlayerBandGroup, val total: Int) : ProfileRow {
        override val key: String get() = "bands:${group.wireId}:view-all"
    }

    /** Whether the row spans every column when no fold splits them. */
    val fullWidth: Boolean get() = this !is InstrumentStats && this !is TopSongs && this !is BandCard
}

/**
 * First page of one band-size group for the player page's Bands preview.
 *
 * @property group Group.
 * @property page First page (`GET /api/player/{id}/bands?group=`).
 */
data class ProfileBandGroup(val group: PlayerBandGroup, val page: PlayerBandListResponse)

/** Row order and Quick Links for the player page (web `PlayerContent` quick links). */
object ProfileSections {
    /**
     * Rows for a loaded profile.
     *
     * @param visible Settings-visible charts in service order.
     * @param showIdentity Whether an identity action, notice or error needs the [ProfileRow.Identity] row;
     *   without it Overview is the first row, so no empty gap sits under the title.
     * @param bands Loaded Bands preview groups (web `buildPlayerBandsItems`), or empty while loading or failed.
     * @return Rows in page order.
     */
    fun rows(visible: List<Instrument>, showIdentity: Boolean = false, bands: List<ProfileBandGroup> = emptyList()): List<ProfileRow> =
        listOfNotNull(ProfileRow.Identity.takeIf { showIdentity }, ProfileRow.Overview) +
            visible.map { ProfileRow.InstrumentStats(it) } +
            ProfileRow.TopSongsHeading +
            visible.map { ProfileRow.TopSongs(it) } +
            ProfileRow.Bands +
            bands.flatMap(::bandRows)

    /**
     * One group's rows: header, then its cards or "No Bands Yet", then "View All Bands (N)" when the
     * group has more bands than the preview shows.
     *
     * @param group Loaded group.
     * @return Rows in page order.
     */
    fun bandRows(group: ProfileBandGroup): List<ProfileRow> {
        val entries = group.page.entries
        return listOf(ProfileRow.BandGroupHeader(group.group)) +
            (if (entries.isEmpty()) listOf(ProfileRow.BandsEmpty(group.group)) else entries.mapIndexed { i, e -> ProfileRow.BandCard(group.group, i, e) }) +
            listOfNotNull(ProfileRow.BandsViewAll(group.group, group.page.totalCount).takeIf { group.page.totalCount > entries.size })
    }

    /** Band-size groups the player page previews, in web order (`PlayerBandsSection` duos, trios, quads). */
    val BAND_GROUPS: List<PlayerBandGroup> = listOf(PlayerBandGroup.Duos, PlayerBandGroup.Trios, PlayerBandGroup.Quads)

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
