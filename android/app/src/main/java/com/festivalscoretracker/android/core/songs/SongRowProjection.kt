package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.format.DifficultyMeterSpec
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.settings.SettingsOrder
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.core.shop.ShopPresentationPolicy
import com.festivalscoretracker.android.core.shop.ShopPulse
import com.festivalscoretracker.android.core.shop.ShopSong
import java.text.NumberFormat
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlin.math.floor

// region Score detail

/**
 * The selected player's validated score for one chart, reduced to what Songs rows use.
 *
 * @property score Score (0 = no score).
 * @property accuracy Expanded accuracy (ten-thousandths of a percent).
 * @property isFullCombo Explicit FC flag.
 * @property stars Stars (6 = gold).
 * @property season Season achieved.
 * @property difficulty Game difficulty 0–3.
 * @property rank One-based rank.
 * @property totalEntries Chart population.
 * @property lastPlayedAt ISO-8601 timestamp (valid variant preferred).
 */
data class SongScoreDetail(
    val score: Long,
    val accuracy: Double? = null,
    val isFullCombo: Boolean? = null,
    val stars: Int? = null,
    val season: Int? = null,
    val difficulty: Double? = null,
    val rank: Int? = null,
    val totalEntries: Int? = null,
    val lastPlayedAt: String? = null,
) {
    /** Facts used by filters and chips. */
    val facts: ChartScoreFacts get() = ChartScoreFacts(score, isFullCombo, stars = stars, season = season, rank = rank, totalEntries = totalEntries)
}

/**
 * The selected player's score index as Songs sees it: available only when scores,
 * catalogue and session share one observed publication. Anything else is an
 * explicit state, never an empty success.
 *
 * @property hasPlayer A player is selected.
 * @property detail Effective-score lookup for a matching, available index; null otherwise.
 * @property rowState Per-row text while unavailable ("Scores syncing"…).
 * @property notice List-level notice while unavailable.
 * @property invalid Per-song reasons the shown scores differ from the raw ones (Filter Invalid Scores).
 */
data class SongScoreSource(
    val hasPlayer: Boolean,
    val detail: ((String, Instrument) -> SongScoreDetail?)? = null,
    val rowState: String? = null,
    val notice: String? = null,
    val invalid: (String) -> Map<Instrument, InvalidScoreReason> = { emptyMap() },
) {
    /** Whether a matching, available index backs [detail]. */
    val available: Boolean get() = detail != null

    /** Facts lookup for filters, only when available; marks raw scores shown over the CHOpt maximum. */
    val facts: ((String, Instrument) -> ChartScoreFacts?)?
        get() = detail?.let { lookup ->
            { songId, chart ->
                lookup(songId, chart)?.facts?.let { facts ->
                    if (invalid(songId)[chart] == InvalidScoreReason.OverThreshold) facts.copy(overThreshold = true) else facts
                }
            }
        }

    companion object {
        /** No player selected. */
        val NONE = SongScoreSource(hasPlayer = false)

        /** Scores loading. */
        val LOADING = SongScoreSource(hasPlayer = true, rowState = "Loading scores")

        /** HTTP 202: the service is still syncing this player. */
        val SYNCING = SongScoreSource(
            hasPlayer = true,
            rowState = "Scores syncing",
            notice = "This player's scores are still syncing. Scores appear once they're published.",
        )

        /** Scores and catalogue belong to different publications. */
        val PAUSED = SongScoreSource(
            hasPlayer = true,
            rowState = "Player scores paused until songs update",
            notice = "Player scores paused until songs and scores are from the same update.",
        )

        /**
         * A failed score read.
         *
         * @param message Readable failure.
         * @return Source.
         */
        fun failed(message: String) = SongScoreSource(hasPlayer = true, rowState = "Scores unavailable", notice = "Player scores unavailable: $message")
    }
}

// endregion

// region Status chips

/**
 * One chart's Songs status; color is the only visual cue, so the row
 * announcement carries the words (see the status-chips spec).
 *
 * @property spoken Status words.
 */
enum class SongInstrumentStatus(val spoken: String) {
    Unavailable("not charted"),
    FullCombo("full combo"),
    Scored("scored"),
    NoScore("no score"),
    InconsistentFullCombo("score missing despite a reported full combo"),
}

/**
 * One chip.
 *
 * @property instrument Chart.
 * @property status Status.
 */
data class SongInstrumentBadge(val instrument: Instrument, val status: SongInstrumentStatus) {
    /** "Lead, full combo". */
    val announcement: String get() = "${instrument.label}, ${status.spoken}"
}

/** When chips show and how each status is derived (Apple `SongInstrumentStatusPolicy`). */
object SongInstrumentStatusPolicy {
    /**
     * Chips need an available index, icons on and no single-chart filter. Under
     * Filter Invalid Scores they reflect the effective (next valid) scores.
     *
     * @param hasPlayer A player is selected.
     * @param scoresAvailable Matching 200 scores are loaded.
     * @param iconsEnabled Show Instrument Icons.
     * @param instrumentFilter Single-chart filter.
     * @param visible Settings-visible charts.
     * @return True when chips replace metadata.
     */
    fun showsChips(
        hasPlayer: Boolean,
        scoresAvailable: Boolean,
        iconsEnabled: Boolean,
        instrumentFilter: Instrument?,
        visible: Set<Instrument>,
    ): Boolean = hasPlayer && scoresAvailable && iconsEnabled && instrumentFilter == null && visible.isNotEmpty()

    /**
     * One badge per visible chart, in service order.
     *
     * @param song Catalogue row.
     * @param visible Settings-visible charts.
     * @param facts This song's facts for a chart.
     * @return At most nine badges.
     */
    fun badges(song: Song, visible: Set<Instrument>, facts: (Instrument) -> ChartScoreFacts?): List<SongInstrumentBadge> =
        Instrument.entries.filter { it in visible }.map { SongInstrumentBadge(it, status(song, it, facts(it))) }

    /**
     * Status for one chart; an uncharted part is "not charted" even if a score exists.
     *
     * @param song Row.
     * @param chart Chart.
     * @param facts Score facts, if a row exists.
     * @return Status.
     */
    fun status(song: Song, chart: Instrument, facts: ChartScoreFacts?): SongInstrumentStatus {
        if (!song.supports(chart)) return SongInstrumentStatus.Unavailable
        if (facts == null) return SongInstrumentStatus.NoScore
        val fullCombo = facts.isFullCombo == true
        return if (facts.score > 0) {
            if (fullCombo) SongInstrumentStatus.FullCombo else SongInstrumentStatus.Scored
        } else {
            if (fullCombo) SongInstrumentStatus.InconsistentFullCombo else SongInstrumentStatus.NoScore
        }
    }
}

// endregion

// region Metadata

/** Percentile emphasis. */
enum class SongPercentileTier {
    /** Top 1%: gold fill. */
    TopOne,

    /** Top 5%: gold outline. */
    TopFive,

    /** Neutral. */
    Ordinary,
}

/**
 * One renderable metadata pill.
 *
 * @property kind Field.
 * @property text Visible text.
 * @property announcement Spoken text.
 * @property tint Accuracy tint `0xRRGGBB` (non-FC accuracy only).
 * @property fullCombo Accuracy pill is a full combo.
 * @property percentile Percentile tier.
 * @property starCount Stars shown (1–5).
 * @property goldStars Stars are gold (service 6).
 * @property currentSeason Season equals the catalogue season (inverted pill).
 * @property intensityRaw Raw chart intensity for the meter.
 * @property gameDifficulty Game difficulty 0–3, or −1.
 */
data class SongMetadataPill(
    val kind: MetadataField,
    val text: String,
    val announcement: String,
    val tint: Int? = null,
    val fullCombo: Boolean = false,
    val percentile: SongPercentileTier = SongPercentileTier.Ordinary,
    val starCount: Int = 0,
    val goldStars: Boolean = false,
    val currentSeason: Boolean = false,
    val intensityRaw: Double? = null,
    val gameDifficulty: Int = -1,
)

/** Builds the icons-off / single-chart selected-player metadata (web `SongRow` metadata). */
object SongMetadataPolicy {
    /** Game difficulty names 0–3. */
    val DIFFICULTY_NAMES = listOf("Easy", "Medium", "Hard", "Expert")

    /** Game difficulty glyphs 0–3. */
    val DIFFICULTY_LETTERS = listOf("E", "M", "H", "X")

    private val PERCENTILE_BUCKETS = listOf(1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100)

    /**
     * Pills for a positive score in display order ([MetadataField.LastPlayed] always last).
     *
     * @param detail Validated score for the chart.
     * @param chart First visible or filtered chart.
     * @param song Catalogue row (Intensity).
     * @param currentSeason Catalogue season.
     * @param order Every field in display order (Settings visual order, or the default).
     * @param visible Fields Settings shows; a hidden Percentage still yields an FC-only pill.
     * @param locale Formatting locale.
     * @param zone Time zone for Last Played.
     * @param primary The sort's field, shown first (web primary sort metadata key).
     * @return Pills; empty for a zero score.
     */
    fun pills(
        detail: SongScoreDetail,
        chart: Instrument,
        song: Song,
        currentSeason: Int?,
        order: List<MetadataField>,
        visible: Set<MetadataField> = order.toSet(),
        locale: Locale = Locale.getDefault(),
        zone: ZoneId = ZoneId.systemDefault(),
        primary: MetadataField? = null,
    ): List<SongMetadataPill> {
        if (detail.score <= 0) return emptyList()
        val shown = visible
        val byKind = mutableMapOf<MetadataField, SongMetadataPill>()
        if (MetadataField.Score in shown) {
            val text = NumberFormat.getIntegerInstance(locale).format(detail.score)
            byKind[MetadataField.Score] = SongMetadataPill(MetadataField.Score, text, "Score $text")
        }
        val fullCombo = detail.isFullCombo == true
        val showPercentage = MetadataField.Percentage in shown
        val accuracy = detail.accuracy?.takeIf { showPercentage && it.isFinite() }
        if (accuracy != null) {
            val text = "${ScoreFormatting.accuracy(accuracy, locale)}%"
            byKind[MetadataField.Percentage] = if (fullCombo) {
                SongMetadataPill(MetadataField.Percentage, "$text FC", "Full combo, accuracy $text", fullCombo = true)
            } else {
                SongMetadataPill(MetadataField.Percentage, text, "Accuracy $text", tint = ScoreFormatting.accuracyTint(accuracy))
            }
        } else if (fullCombo) {
            val spoken = if (showPercentage) "Full combo, accuracy unavailable" else "Full combo"
            byKind[MetadataField.Percentage] = SongMetadataPill(MetadataField.Percentage, "FC", spoken, fullCombo = true)
        }
        val bucket = percentileBucket(detail.rank, detail.totalEntries)
        if (MetadataField.Percentile in shown && bucket != null) {
            val pct = minOf(detail.rank!!.toDouble() / detail.totalEntries!! * 100, 100.0)
            val tier = when {
                pct <= 1 -> SongPercentileTier.TopOne
                pct <= 5 -> SongPercentileTier.TopFive
                else -> SongPercentileTier.Ordinary
            }
            byKind[MetadataField.Percentile] = SongMetadataPill(MetadataField.Percentile, bucket, bucket, percentile = tier)
        }
        val stars = detail.stars
        if (MetadataField.Stars in shown && stars != null && stars in 1..6) {
            val gold = stars >= 6
            val count = if (gold) 5 else stars
            val spoken = when {
                gold -> "$count gold stars"
                count == 1 -> "1 star"
                else -> "$count stars"
            }
            byKind[MetadataField.Stars] = SongMetadataPill(MetadataField.Stars, "★".repeat(count), spoken, starCount = count, goldStars = gold)
        }
        val season = detail.season
        if (MetadataField.Season in shown && season != null && season > 0) {
            val current = season == currentSeason
            byKind[MetadataField.Season] = SongMetadataPill(
                MetadataField.Season, "S$season", if (current) "Current season $season" else "Season $season", currentSeason = current,
            )
        }
        val raw = song.difficulty?.chartedValue(chart)
        if (MetadataField.Intensity in shown && raw != null) {
            byKind[MetadataField.Intensity] = SongMetadataPill(
                MetadataField.Intensity, "", "Song intensity ${DifficultyMeterSpec.filledBars(raw, true)} of 7", intensityRaw = raw,
            )
        }
        val difficulty = detail.difficulty
        if (MetadataField.Difficulty in shown && difficulty != null && difficulty.isFinite() && difficulty == floor(difficulty) && difficulty in 0.0..3.0) {
            val index = difficulty.toInt()
            byKind[MetadataField.Difficulty] = SongMetadataPill(
                MetadataField.Difficulty, DIFFICULTY_LETTERS[index], "${DIFFICULTY_NAMES[index]} difficulty", gameDifficulty = index,
            )
        }
        val lastPlayed = detail.lastPlayedAt
        if (MetadataField.LastPlayed in shown && lastPlayed != null) {
            val text = lastPlayedText(lastPlayed, locale, zone)
            byKind[MetadataField.LastPlayed] = SongMetadataPill(MetadataField.LastPlayed, text, text)
        }
        val display = order.filter { it != MetadataField.LastPlayed } + MetadataField.LastPlayed
        val ordered = if (primary != null) listOf(primary) + (display - primary) else display
        return ordered.mapNotNull { byKind[it] }
    }

    /**
     * Songs percentile bucket.
     *
     * @param rank One-based rank.
     * @param total Population.
     * @return "Top N%", or null without a positive rank and total.
     */
    fun percentileBucket(rank: Int?, total: Int?): String? {
        if (rank == null || total == null || rank <= 0 || total <= 0) return null
        val pct = (rank.toDouble() / total * 100).coerceIn(1.0, 100.0)
        return "Top ${PERCENTILE_BUCKETS.first { pct <= it }}%"
    }

    /**
     * "Last played 3 Sep 2026", or an explicit unavailable label.
     *
     * @param raw ISO-8601 timestamp.
     * @param locale Locale.
     * @param zone Display zone.
     * @return Text.
     */
    fun lastPlayedText(raw: String, locale: Locale = Locale.getDefault(), zone: ZoneId = ZoneId.systemDefault()): String = try {
        val date = OffsetDateTime.parse(raw).atZoneSameInstant(zone)
        "Last played " + DateTimeFormatter.ofPattern("d MMM yyyy", locale).format(date)
    } catch (error: DateTimeParseException) {
        "Last played date unavailable"
    }
}

// endregion

/// region Row model

/**
 * The dual "score / max" primary pill and its metric for Max Score % and Max Score
 * Diff sorts (web `renderMetadataElement` max modes).
 *
 * @property score Formatted score.
 * @property max Formatted CHOpt maximum, or null when unavailable ("—").
 * @property metric `95.3%` or `-4,210`, or `—` without a maximum.
 * @property percent Score as a percent of the maximum (tint), or null.
 */
data class SongMaxScorePill(val score: String, val max: String?, val metric: String, val percent: Double?) {
    /** Spoken text. */
    val announcement: String
        get() = if (max == null) "Score $score, max score unavailable" else "Score $score of max $max, $metric"
}

/**
 * The most recent play across charts (unfiltered Last Played sort).
 *
 * @property chart Most recently played chart.
 * @property text "Last played 3 Sep 2026".
 */
data class SongLastPlayed(val chart: Instrument, val text: String)

/**
 * One Songs row with everything the card shows, computed once per rebuild.
 *
 * @property song Catalogue row.
 * @property highlight Same-publication Shop badge (Leaving Tomorrow / New).
 * @property pulse Shop outline pulse (green in Shop, gold New, red Leaving Tomorrow).
 * @property chips Status chips (empty when chips don't apply).
 * @property chart Chart the metadata/meter describes.
 * @property chartRaw Raw difficulty for the meter (no metadata).
 * @property metadata Metadata pills.
 * @property scoreState Explicit non-scored text.
 * @property maxScore Max-score primary pill (Max Score % / Diff sorts).
 * @property lastPlayed Most recent play across charts (unfiltered Last Played sort).
 * @property warning Invalid-score warning (Filter Invalid Scores).
 */
data class SongRowModel(
    val song: Song,
    val highlight: ShopHighlight? = null,
    val pulse: ShopPulse? = null,
    val chips: List<SongInstrumentBadge> = emptyList(),
    val chart: Instrument? = null,
    val chartRaw: Double? = null,
    val metadata: List<SongMetadataPill> = emptyList(),
    val scoreState: String? = null,
    val maxScore: SongMaxScorePill? = null,
    val lastPlayed: SongLastPlayed? = null,
    val warning: InvalidScoreWarning? = null,
) {
    /** Whether metadata names a non-Lead chart. */
    val namesChart: Boolean get() = chart != null && chart != Instrument.Lead && (metadata.isNotEmpty() || maxScore != null)

    /** The single spoken summary for the whole row (one TalkBack stop). */
    val announcement: String
        get() = buildList {
            add(song.title)
            add(song.subtitle)
            when {
                highlight != null -> add("Item Shop: ${highlight.label}")
                pulse == ShopPulse.InShop -> add("In the Item Shop")
            }
            chips.forEach { add(it.announcement) }
            lastPlayed?.let { add("${it.text} on ${it.chart.label}") }
            if (metadata.isNotEmpty() || maxScore != null) {
                if (namesChart) add("${chart!!.label} chart")
                maxScore?.let { add(it.announcement) }
                metadata.forEach { add(it.announcement) }
            } else if (chart != null && chartRaw != null) {
                add("${chart.label}, ${DifficultyMeterSpec.accessibilityLabel(chartRaw, raw = true)}")
            }
            scoreState?.let { add(it) }
            warning?.let { add(if (it.warning) "Score over the CHOpt maximum" else "Filtered score") }
        }.filter { it.isNotEmpty() }.joinToString(", ")
}

/**
 * Projects catalogue rows for one rebuild (Windows `SongRowProjector`).
 *
 * @param settings Current settings.
 * @param filter Public filter (its chart drives the meter/metadata chart).
 * @param currentSeason Catalogue season.
 * @param offers Same-publication offers, or null.
 * @param scores Selected-player score source (effective scores).
 * @param sort Applied sort (primary pill, Last Played and max-score presentation).
 * @param metadataOrder Metadata sort priority (row order while independent visual order is off).
 * @param locale Formatting locale.
 */
class SongRowProjector(
    private val settings: AppSettings,
    private val filter: SongFilter,
    private val currentSeason: Int?,
    private val offers: Map<String, ShopSong>?,
    private val scores: SongScoreSource,
    private val sort: SongSortMode = SongSortMode.Title,
    metadataOrder: List<MetadataField> = MetadataField.entries,
    private val locale: Locale = Locale.getDefault(),
) {
    private val filterChart = filter.scopedTo(settings.visibleInstruments).instrument
    private val chips = SongInstrumentStatusPolicy.showsChips(
        scores.hasPlayer, scores.available, settings.showInstrumentIcons, filterChart, settings.visibleInstruments,
    )
    private val metadataChart = filterChart ?: settings.orderedVisibleInstruments.firstOrNull()
    private val order = SettingsOrder.normalize(if (settings.enableVisualOrder) settings.songRowVisualOrder else metadataOrder, MetadataField.entries)

    /** Last Played shows only while sorting by it (web `visibleMetadataOrder`). */
    private val visibleMetadata = if (sort == SongSortMode.LastPlayed) settings.visibleMetadata else settings.visibleMetadata - MetadataField.LastPlayed

    /** The sort's field leads the row for single-chart and Last Played sorts. */
    private val primary = sort.metadata.takeIf { sort.group != SongSortGroup.Catalog && it in visibleMetadata }

    /** Unfiltered Last Played: the most recent play across visible charts, beside chips or metadata. */
    private val latestAcrossCharts = sort == SongSortMode.LastPlayed && filterChart == null
    private val playedCharts = settings.orderedVisibleInstruments

    /**
     * Project one song.
     *
     * @param song Catalogue row.
     * @return Row model.
     */
    fun project(song: Song): SongRowModel {
        val offer = offers?.get(song.songId)
        val base = SongRowModel(
            song,
            highlight = ShopPresentationPolicy.highlight(offer, settings.hideShop, settings.disableShopHighlighting),
            pulse = ShopPresentationPolicy.pulse(offer, settings.hideShop, settings.disableShopHighlighting),
        )
        val filterRaw = filterChart?.let { song.difficulty?.chartedValue(it) }
        val meterChart = if (filterRaw == null) null else filterChart
        val detail = scores.detail
        if (!scores.hasPlayer) return base.copy(chart = meterChart, chartRaw = filterRaw)
        if (detail == null || metadataChart == null) return base.copy(chart = meterChart, chartRaw = filterRaw, scoreState = scores.rowState)
        val reasons = scores.invalid(song.songId).filterKeys { it in settings.visibleInstruments }
        val warned = base.copy(
            warning = InvalidScoreWarning.of(song.title, reasons, filterChart),
            lastPlayed = if (latestAcrossCharts) latestPlayed(song, detail) else null,
        )
        if (chips) {
            return warned.copy(chips = SongInstrumentStatusPolicy.badges(song, settings.visibleInstruments) { detail(song.songId, it)?.facts })
        }
        val chartDetail = detail(song.songId, metadataChart)
        val shown = if (latestAcrossCharts) visibleMetadata - MetadataField.LastPlayed else visibleMetadata
        var pills = chartDetail?.let { SongMetadataPolicy.pills(it, metadataChart, song, currentSeason, order, shown, locale, primary = primary) }.orEmpty()
        val maxPill = if (sort.isMaxScoreMode && chartDetail != null && chartDetail.score > 0) maxScorePill(chartDetail, song.maxScore(metadataChart)) else null
        if (maxPill != null) pills = pills.filter { it.kind != MetadataField.Score }
        val hasContent = pills.isNotEmpty() || maxPill != null
        return warned.copy(
            chart = metadataChart,
            chartRaw = if (!hasContent) song.difficulty?.chartedValue(metadataChart) else null,
            metadata = pills,
            maxScore = maxPill,
            scoreState = when {
                hasContent -> null
                reasons[metadataChart] == InvalidScoreReason.NoFallback -> "No valid score"
                song.supports(metadataChart) -> "No score"
                else -> "No ${metadataChart.label} chart"
            },
        )
    }

    private fun latestPlayed(song: Song, detail: (String, Instrument) -> SongScoreDetail?): SongLastPlayed? {
        val charts = playedCharts.ifEmpty { return null }
        val (chart, raw) = SongSortScores(charts.first(), charts, detail).latestPlayed(song.songId) ?: return null
        return SongLastPlayed(chart, SongMetadataPolicy.lastPlayedText(raw, locale))
    }

    private fun maxScorePill(detail: SongScoreDetail, max: Int?): SongMaxScorePill {
        val numbers = NumberFormat.getIntegerInstance(locale)
        val score = numbers.format(detail.score)
        if (max == null) return SongMaxScorePill(score, null, "—", null)
        val percent = detail.score.toDouble() / max * 100
        val metric = if (sort == SongSortMode.MaxDistance) {
            String.format(locale, "%.1f%%", percent)
        } else {
            val diff = detail.score - max
            (if (diff > 0) "+" else "") + numbers.format(diff)
        }
        return SongMaxScorePill(score, numbers.format(max), metric, percent)
    }
}

// endregion
