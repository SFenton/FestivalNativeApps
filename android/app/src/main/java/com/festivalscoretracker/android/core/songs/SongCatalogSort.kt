package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.shop.ShopSong
import java.text.Collator
import java.text.Normalizer
import java.util.Locale

// region Sort modes

/** Which sheet group offers a mode (web `SortModal` sections). */
enum class SongSortGroup {
    /** Catalogue and public Shop modes, offered to everyone. */
    Catalog,

    /** Selected-player modes across charts (Has FC, Last Played). */
    Player,

    /** Modes that need a single-chart filter (web "Filtered Instrument Sort Mode"). */
    SingleChart,
}

/**
 * Songs sort modes (web `SongSortMode`, minus band modes).
 *
 * @property label Sheet label.
 * @property webId Web mode ID (quick-link IDs are `webId:token`).
 * @property group Sheet group.
 * @property metadata Metadata field this mode sorts by (Settings visibility gates it; primary pill).
 */
enum class SongSortMode(
    val label: String,
    val webId: String,
    val group: SongSortGroup = SongSortGroup.Catalog,
    val metadata: MetadataField? = null,
) {
    Title("Title", "title"),
    Artist("Artist", "artist"),
    Year("Year", "year"),
    Duration("Duration", "duration"),
    Shop("Item Shop", "shop"),
    HasFC("Has FC", "hasfc", SongSortGroup.Player),
    LastPlayed("Last Played", "lastplayed", SongSortGroup.Player, MetadataField.LastPlayed),
    Score("Score", "score", SongSortGroup.SingleChart, MetadataField.Score),
    Percentage("Percentage", "percentage", SongSortGroup.SingleChart, MetadataField.Percentage),
    Percentile("Percentile", "percentile", SongSortGroup.SingleChart, MetadataField.Percentile),
    Stars("Stars", "stars", SongSortGroup.SingleChart, MetadataField.Stars),
    Season("Season", "seasonachieved", SongSortGroup.SingleChart, MetadataField.Season),
    Intensity("Intensity", "intensity", SongSortGroup.SingleChart, MetadataField.Intensity),
    Difficulty("Difficulty", "difficulty", SongSortGroup.SingleChart, MetadataField.Difficulty),
    MaxDistance("Max Score %", "maxdistance", SongSortGroup.SingleChart),
    MaxScoreDiff("Max Score Diff", "maxscorediff", SongSortGroup.SingleChart);

    /** Whether the mode reads the selected player's scores (everything but catalogue modes and Intensity). */
    val needsScores: Boolean get() = group != SongSortGroup.Catalog && this != Intensity

    /** Whether the mode needs a single-chart filter. */
    val needsChart: Boolean get() = group == SongSortGroup.SingleChart

    /** Whether the right-edge section index (not Quick Links) navigates this sort (Year uses decade headers, operator rule). */
    val usesSectionIndex: Boolean get() = this == Title || this == Artist

    /** Whether the mode compares the max-score metric (score / max primary pill). */
    val isMaxScoreMode: Boolean get() = this == MaxDistance || this == MaxScoreDiff

    companion object {
        /**
         * Parse a persisted value, falling back to [Title] for unknown or removed modes.
         *
         * @param raw Stored enum name.
         * @return The matching mode or [Title].
         */
        fun fromStored(raw: String?): SongSortMode = entries.firstOrNull { it.name == raw } ?: Title
    }
}

// endregion

// region Sorting

/**
 * The selected player's scores as score-aware sorts see them (a matching,
 * available index only; unavailable scores pause the sort instead).
 *
 * @property chart Chart single-chart modes and Has FC compare (filter chart, else the first visible chart).
 * @property visible Settings-visible charts in service order (unfiltered Last Played).
 * @property detail Effective score lookup.
 */
class SongSortScores(
    val chart: Instrument,
    val visible: List<Instrument>,
    val detail: (String, Instrument) -> SongScoreDetail?,
) {
    /**
     * The most recent last-played timestamp across [visible] charts (web `getBestLastPlayed`).
     *
     * @param songId Song.
     * @return Chart and ISO timestamp, or null when never played.
     */
    fun latestPlayed(songId: String): Pair<Instrument, String>? {
        var best: Pair<Instrument, String>? = null
        for (chart in visible) {
            val played = detail(songId, chart)?.lastPlayedAt ?: continue
            if (best == null || played > best.second) best = chart to played
        }
        return best
    }
}

/**
 * Sort songs by catalogue fields, validated public Shop membership or the
 * selected player's effective scores (web `useFilteredSongs` comparator).
 *
 * @property collator Locale-aware string comparison; injectable for deterministic tests.
 */
class SongCatalogSort(private val collator: Collator = Collator.getInstance(Locale.getDefault())) {
    /**
     * Order songs. Ties break by title (then song ID for stability) in the sort
     * direction; Shop ties by title, artist, then year. Songs without a score sort
     * after scored ones ascending (web `compareByMode`); for Intensity, Max Score %
     * and Max Score Diff, measurable songs always come first.
     *
     * @param songs Songs after search and filtering.
     * @param mode Sort field.
     * @param ascending Direction.
     * @param shopIds Validated membership, required for [SongSortMode.Shop].
     * @param scores Effective scores, required for score modes (callers pause without them).
     * @param chart Chart single-chart modes compare (Intensity works without scores).
     * @return A new ordered list.
     */
    fun sorted(
        songs: List<Song>,
        mode: SongSortMode,
        ascending: Boolean,
        shopIds: Set<String> = emptySet(),
        scores: SongSortScores? = null,
        chart: Instrument? = scores?.chart,
    ): List<Song> {
        val dir = if (ascending) 1 else -1
        val comparator = Comparator<Song> { left, right ->
            val primary = compare(left, right, mode, dir, shopIds, scores, chart)
            when {
                primary != 0 -> primary * dir
                else -> {
                    val title = collator.compare(left.title, right.title)
                    (if (title != 0) title else left.songId.compareTo(right.songId)) * dir
                }
            }
        }
        return songs.sortedWith(comparator)
    }

    private fun compare(left: Song, right: Song, mode: SongSortMode, dir: Int, shopIds: Set<String>, scores: SongSortScores?, chart: Instrument?): Int {
        fun detail(song: Song) = if (scores != null && chart != null) scores.detail(song.songId, chart) else null
        return when (mode) {
            SongSortMode.Title -> collator.compare(left.title, right.title)
            SongSortMode.Artist -> collator.compare(left.artist, right.artist)
            SongSortMode.Year -> (left.year ?: 0).compareTo(right.year ?: 0)
            SongSortMode.Duration -> (left.durationSeconds ?: 0).compareTo(right.durationSeconds ?: 0)
            SongSortMode.Shop -> {
                var result = (right.songId in shopIds).compareTo(left.songId in shopIds)
                if (result == 0) result = collator.compare(left.title, right.title)
                if (result == 0) result = collator.compare(left.artist, right.artist)
                if (result == 0) result = (left.year ?: 0).compareTo(right.year ?: 0)
                result
            }
            SongSortMode.Intensity -> compareMeasured(
                chart?.let { left.difficulty?.chartedValue(it) },
                chart?.let { right.difficulty?.chartedValue(it) },
                dir,
            ) { collator.compare(left.title, right.title) }
            SongSortMode.MaxDistance, SongSortMode.MaxScoreDiff -> {
                val a = detail(left)
                val b = detail(right)
                compareMeasured(maxMetric(a, left, chart, mode), maxMetric(b, right, chart, mode), dir) {
                    compareByMode(SongSortMode.Score, a, b)
                }
            }
            SongSortMode.LastPlayed -> if (scores == null) {
                0
            } else {
                compareLastPlayed(scores.latestPlayed(left.songId)?.second, scores.latestPlayed(right.songId)?.second, dir)
            }
            else -> compareByMode(mode, detail(left), detail(right))
        }
    }

    /**
     * Web `compareByMode`: a missing score sorts after a present one (ascending sense).
     *
     * @param mode Score mode.
     * @param a Left detail.
     * @param b Right detail.
     * @return Comparison in the ascending sense.
     */
    internal fun compareByMode(mode: SongSortMode, a: SongScoreDetail?, b: SongScoreDetail?): Int {
        if (a == null && b == null) return 0
        if (a == null) return 1
        if (b == null) return -1
        return when (mode) {
            SongSortMode.Score -> a.score.compareTo(b.score)
            SongSortMode.Percentage -> {
                val byAccuracy = (a.accuracy ?: 0.0).compareTo(b.accuracy ?: 0.0)
                if (byAccuracy != 0) byAccuracy else (a.isFullCombo == true).compareTo(b.isFullCombo == true)
            }
            SongSortMode.Percentile -> percentileRatio(a).compareTo(percentileRatio(b))
            SongSortMode.Stars -> (a.stars ?: 0).compareTo(b.stars ?: 0)
            SongSortMode.Season -> (a.season ?: 0).compareTo(b.season ?: 0)
            SongSortMode.Difficulty -> (a.difficulty ?: -1.0).compareTo(b.difficulty ?: -1.0)
            SongSortMode.HasFC -> (a.isFullCombo == true).compareTo(b.isFullCombo == true)
            else -> 0
        }
    }

    private fun percentileRatio(detail: SongScoreDetail): Double {
        val rank = detail.rank ?: 0
        val total = detail.totalEntries ?: 0
        return if (rank > 0 && total > 0) rank.toDouble() / total else Double.POSITIVE_INFINITY
    }

    /**
     * A measurable value always comes first regardless of direction (the result is
     * multiplied by the direction afterwards, so `-dir` means "left first").
     */
    private fun compareMeasured(a: Double?, b: Double?, dir: Int, fallback: () -> Int): Int = when {
        a != null && b != null -> a.compareTo(b)
        a != null -> -dir
        b != null -> dir
        else -> fallback()
    }

    private fun compareLastPlayed(a: String?, b: String?, dir: Int): Int = when {
        a != null && b == null -> -dir
        a == null && b != null -> dir
        a == null || b == null -> 0
        else -> a.compareTo(b)
    }

    private fun maxMetric(detail: SongScoreDetail?, song: Song, chart: Instrument?, mode: SongSortMode): Double? {
        val max = chart?.let(song::maxScore) ?: return null
        val score = detail?.score?.takeIf { it > 0 } ?: return null
        return if (mode == SongSortMode.MaxDistance) score.toDouble() / max else (score - max).toDouble()
    }
}

// endregion

// region Section index

/**
 * One nonempty jump-to bucket for the right-edge index scrubber.
 *
 * @property id Stable position index (labels may legitimately repeat).
 * @property label Uppercase letter, `#` or a year.
 * @property firstIndex Position of the section's first song in the list.
 * @property count Songs in the section.
 */
data class SongSection(val id: Int, val label: String, val firstIndex: Int, val count: Int)

/** Contacts-style drag-to-jump index for Title/Artist (Apple `SongSectionIndex`). */
object SongSectionIndex {
    /**
     * Chunk an already-sorted list on **consecutive** key changes.
     *
     * @param songs Songs in on-screen order.
     * @param mode Active sort; only Title and Artist group (Year uses decade headers).
     * @return Order-preserving sections; empty for other modes or fewer than two songs.
     */
    fun sections(songs: List<Song>, mode: SongSortMode): List<SongSection> {
        if (songs.size < 2) return emptyList()
        val key: (Song) -> String = when (mode) {
            SongSortMode.Title -> { song -> firstLetter(song.title) }
            SongSortMode.Artist -> { song -> firstLetter(song.artist) }
            else -> return emptyList()
        }
        return chunk(songs, key)
    }

    /**
     * Chunk rows on consecutive key changes.
     *
     * @param songs Rows in order.
     * @param key Section key.
     * @return Sections.
     */
    internal fun chunk(songs: List<Song>, key: (Song) -> String): List<SongSection> {
        if (songs.isEmpty()) return emptyList()
        val result = mutableListOf<SongSection>()
        var start = 0
        var label = key(songs[0])
        for (index in 1 until songs.size) {
            val next = key(songs[index])
            if (next != label) {
                result += SongSection(result.size, label, start, index - start)
                start = index
                label = next
            }
        }
        result += SongSection(result.size, label, start, songs.size - start)
        return result
    }

    /**
     * Diacritic-folded first character when it is A–Z, otherwise `#`.
     *
     * @param text Raw title or artist.
     * @return One uppercase ASCII letter or `#`.
     */
    fun firstLetter(text: String): String {
        val first = text.trim().firstOrNull() ?: return "#"
        val folded = Normalizer.normalize(first.toString(), Normalizer.Form.NFD)
            .firstOrNull()?.uppercaseChar() ?: return "#"
        return if (folded in 'A'..'Z') folded.toString() else "#"
    }
}

// endregion

// region Shop buckets

/**
 * Source Shop buckets (Apple `SongShopSectionKind`).
 *
 * @property id Stable test/scroll token.
 * @property label Section header.
 */
enum class SongShopBucket(val id: String, val label: String) {
    LeavingTomorrow("leaving-tomorrow", "Leaving Tomorrow"),
    InShop("in-shop", "In Shop"),
    NotInShop("not-in-shop", "Not In Shop"),
}

/** Shop bucket rule shared by headers and Quick Links. */
object SongShopSections {
    /**
     * Bucket for one song; a leaving offer is never also "In Shop".
     *
     * @param song Song.
     * @param offers Validated offers.
     * @return Bucket.
     */
    fun bucket(song: Song, offers: Map<String, ShopSong>): SongShopBucket = when (offers[song.songId]?.leavingTomorrow) {
        true -> SongShopBucket.LeavingTomorrow
        false -> SongShopBucket.InShop
        null -> SongShopBucket.NotInShop
    }
}

// endregion

// region Pipeline

/**
 * Everything that shapes the Songs list, captured once per rebuild.
 *
 * @property songs Validated catalogue rows.
 * @property search Applied (debounced) search text.
 * @property filter Public chart/difficulty filter.
 * @property shopFilter Saved Shop filter.
 * @property playerFilter Saved selected-player filter.
 * @property sort Saved sort mode.
 * @property ascending Saved direction.
 * @property visible Settings-visible charts.
 * @property hideShop Hide Item Shop setting.
 * @property offers Same-publication offers, or null when unavailable.
 * @property shopPublicationMismatch A Shop feed exists but from a different publication.
 * @property hasPlayer A player is selected.
 * @property filterInvalidScores Filter Invalid Scores setting (enables Over CHOpt Threshold checks).
 * @property scores Effective scores for a matching, available index; null when unavailable.
 * @property invalid Per-song reasons shown scores differ from raw ones (marks Over CHOpt Threshold rows).
 * @property nowEpochMillis Clock for Last Played buckets.
 */
data class SongListInputs(
    val songs: List<Song>,
    val search: String = "",
    val filter: SongFilter = SongFilter(),
    val shopFilter: SongShopFilter = SongShopFilter(),
    val playerFilter: SongPlayerScoreFilter = SongPlayerScoreFilter(),
    val sort: SongSortMode = SongSortMode.Title,
    val ascending: Boolean = true,
    val visible: Set<Instrument> = Instrument.entries.toSet(),
    val hideShop: Boolean = false,
    val offers: Map<String, ShopSong>? = null,
    val shopPublicationMismatch: Boolean = false,
    val hasPlayer: Boolean = false,
    val filterInvalidScores: Boolean = false,
    val scores: ((String, Instrument) -> SongScoreDetail?)? = null,
    val invalid: (String) -> Map<Instrument, InvalidScoreReason> = { emptyMap() },
    val nowEpochMillis: Long = System.currentTimeMillis(),
)

/**
 * Rows plus the pause notices explaining any saved choice not currently applied.
 *
 * @property songs Rows in order (grouped by first-seen bucket when headers apply).
 * @property sections Scrubber sections (Title/Artist/Year only).
 * @property headers In-list bucket headers, also the Quick Links targets.
 * @property effectiveSort Sort actually applied (a paused sort shows Title order).
 * @property sortPaused Why a saved sort is paused (none for a player sort while no player is selected).
 * @property shopFilterPaused Why a saved Shop filter is paused.
 * @property scoreFilterPaused Why saved player filters are paused (none while no player is selected).
 * @property filtersApplied Whether any filter actually narrowed the pipeline.
 * @property sortChart Chart score sorts compared, when any.
 */
data class SongListResult(
    val songs: List<Song>,
    val sections: List<SongSection>,
    val headers: List<SongListHeader>,
    val effectiveSort: SongSortMode,
    val sortPaused: String?,
    val shopFilterPaused: String?,
    val scoreFilterPaused: String?,
    val filtersApplied: Boolean,
    val sortChart: Instrument? = null,
) {
    /** Every pause notice, in display order. */
    val notices: List<String> get() = listOfNotNull(sortPaused, shopFilterPaused, scoreFilterPaused)
}

/** Search → chart filter → Shop filter → player filter → sort → group, pausing rather than guessing. */
object SongListPipeline {
    /**
     * Run the pipeline.
     *
     * @param input Captured inputs.
     * @param sorter Sorter.
     * @return Rows, sections and notices.
     */
    fun run(input: SongListInputs, sorter: SongCatalogSort = SongCatalogSort()): SongListResult {
        val filter = input.filter.scopedTo(input.visible)
        var rows = input.songs.filter { SongSearch.matches(it, input.search) && filter.matches(it) }

        val shopPaused = if (input.shopFilter.isActive) shopPauseReason(input, "filters") else null
        if (input.shopFilter.isActive && shopPaused == null) rows = input.shopFilter.filter(rows, input.offers.orEmpty())

        val scorePaused = scorePauseReason(input)
        val scoped = input.playerFilter.scopedTo(input.visible).effective(input.filterInvalidScores)
        val scores = input.scores
        if (scorePaused == null && scoped.isActive && scores != null) {
            val facts = { id: String, chart: Instrument ->
                scores(id, chart)?.facts?.let { if (input.invalid(id)[chart] == InvalidScoreReason.OverThreshold) it.copy(overThreshold = true) else it }
            }
            rows = scoped.filter(rows, facts, input.visible, filter.instrument)
        }

        val chart = filter.instrument ?: Instrument.entries.firstOrNull { it in input.visible }
        val sortPaused = sortPauseReason(input, filter.instrument)
        val effective = if (sortPaused != null) SongSortMode.Title else input.sort
        val played = filter.instrument?.let(::listOf) ?: Instrument.entries.filter { it in input.visible }
        val sortScores = if (scores != null && chart != null) SongSortScores(chart, played, scores) else null
        val sorted = sorter.sorted(rows, effective, input.ascending, input.offers?.keys.orEmpty(), sortScores, chart)
        val context = SongBucketContext(effective, chart, input.offers.orEmpty(), sortScores, input.nowEpochMillis)
        val (ordered, headers) = if (effective.usesSectionIndex) sorted to emptyList() else SongQuickLinkBuckets.group(sorted, context)
        val applied = filter.isActive || (input.shopFilter.isActive && shopPaused == null) || (scoped.appliesTo(filter.instrument) && scorePaused == null)
        // Without a player, player-dependent choices simply don't apply (web shows no notice).
        val sortNotice = sortPaused.takeUnless { !input.hasPlayer && input.sort.needsScores }
        val scoreNotice = scorePaused.takeIf { input.hasPlayer }
        return SongListResult(
            ordered, SongSectionIndex.sections(ordered, effective), headers, effective,
            sortNotice, shopPaused, scoreNotice, applied,
            sortChart = if (effective.needsChart || effective == SongSortMode.HasFC) chart else null,
        )
    }

    private fun sortPauseReason(input: SongListInputs, filterChart: Instrument?): String? {
        val sort = input.sort
        val label = sort.label
        return when {
            sort == SongSortMode.Shop -> shopPauseReason(input, "sort")
            sort.needsChart && filterChart == null ->
                "$label sort needs a single-instrument filter. Showing title order; your choice is saved."
            !sort.needsScores -> null
            !input.hasPlayer -> "$label sort paused until a player is selected. Showing title order; your choice is saved."
            input.scores == null ->
                "$label sort paused until the player's scores and songs are from the same update. Showing title order; your choice is saved."
            else -> null
        }
    }

    private fun shopPauseReason(input: SongListInputs, what: String): String? {
        val fallback = if (what == "sort") "Showing title order" else "Showing all songs"
        return when {
            input.hideShop -> "Item Shop $what paused while the Item Shop is hidden. $fallback; your choice is saved."
            input.shopPublicationMismatch ->
                "Item Shop $what paused until songs and Item Shop data update together. $fallback; your choice is saved."
            input.offers == null -> "Item Shop $what paused until Item Shop data loads. $fallback; your choice is saved."
            else -> null
        }
    }

    private fun scorePauseReason(input: SongListInputs): String? {
        val scoped = input.playerFilter.scopedTo(input.visible)
        return when {
            !input.playerFilter.effective(input.filterInvalidScores).isActive -> null
            !scoped.effective(input.filterInvalidScores).isActive ->
                "Player score filters paused while their instruments are hidden in Settings. Your choices are saved."
            !input.hasPlayer -> "Player score filters paused until a player is selected."
            input.scores == null ->
                "Player score filters paused until the player's scores and songs are from the same update. Showing songs without score filters."
            else -> null
        }
    }
}

// endregion
