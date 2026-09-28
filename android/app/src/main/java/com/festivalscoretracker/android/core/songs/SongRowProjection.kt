package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.format.DifficultyMeterSpec
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.core.shop.ShopPresentationPolicy
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
    val facts: ChartScoreFacts get() = ChartScoreFacts(score, isFullCombo)
}

/**
 * The selected player's score index as Songs sees it: available only when scores,
 * catalogue and session share one observed publication. Anything else is an
 * explicit state, never an empty success.
 *
 * @property hasPlayer A player is selected.
 * @property detail Lookup for a matching, available index; null otherwise.
 * @property rowState Per-row text while unavailable ("Scores syncing"…).
 * @property notice List-level notice while unavailable.
 */
data class SongScoreSource(
    val hasPlayer: Boolean,
    val detail: ((String, Instrument) -> SongScoreDetail?)? = null,
    val rowState: String? = null,
    val notice: String? = null,
) {
    /** Whether a matching, available index backs [detail]. */
    val available: Boolean get() = detail != null

    /** Facts lookup for filters, only when available. */
    val facts: ((String, Instrument) -> ChartScoreFacts?)?
        get() = detail?.let { lookup -> { songId, chart -> lookup(songId, chart)?.facts } }

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
     * Chips need an available index, icons on, no single-chart filter and invalid-score filtering off.
     *
     * @param hasPlayer A player is selected.
     * @param scoresAvailable Matching 200 scores are loaded.
     * @param iconsEnabled Show Instrument Icons.
     * @param instrumentFilter Single-chart filter.
     * @param filterInvalidScores Filter Invalid Scores.
     * @param visible Settings-visible charts.
     * @return True when chips replace metadata.
     */
    fun showsChips(
        hasPlayer: Boolean,
        scoresAvailable: Boolean,
        iconsEnabled: Boolean,
        instrumentFilter: Instrument?,
        filterInvalidScores: Boolean,
        visible: Set<Instrument>,
    ): Boolean = hasPlayer && scoresAvailable && iconsEnabled && instrumentFilter == null && !filterInvalidScores && visible.isNotEmpty()

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
        return (order.filter { it != MetadataField.LastPlayed } + MetadataField.LastPlayed).mapNotNull { byKind[it] }
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

// region Row model

/**
 * One Songs row with everything the card shows, computed once per rebuild.
 *
 * @property song Catalogue row.
 * @property highlight Same-publication Shop accent.
 * @property chips Status chips (empty when chips don't apply).
 * @property chart Chart the metadata/meter describes.
 * @property chartRaw Raw difficulty for the meter (no metadata).
 * @property metadata Metadata pills.
 * @property scoreState Explicit non-scored text.
 */
data class SongRowModel(
    val song: Song,
    val highlight: ShopHighlight? = null,
    val chips: List<SongInstrumentBadge> = emptyList(),
    val chart: Instrument? = null,
    val chartRaw: Double? = null,
    val metadata: List<SongMetadataPill> = emptyList(),
    val scoreState: String? = null,
) {
    /** Whether metadata names a non-Lead chart. */
    val namesChart: Boolean get() = chart != null && chart != Instrument.Lead && metadata.isNotEmpty()

    /** The single spoken summary for the whole row (one TalkBack stop). */
    val announcement: String
        get() = buildList {
            add(song.title)
            add(song.subtitle)
            highlight?.let { add("Item Shop: ${it.label}") }
            chips.forEach { add(it.announcement) }
            if (metadata.isNotEmpty()) {
                if (namesChart) add("${chart!!.label} chart")
                metadata.forEach { add(it.announcement) }
            } else if (chart != null && chartRaw != null) {
                add("${chart.label}, ${DifficultyMeterSpec.accessibilityLabel(chartRaw, raw = true)}")
            }
            scoreState?.let { add(it) }
        }.filter { it.isNotEmpty() }.joinToString(", ")
}

/**
 * Projects catalogue rows for one rebuild (Windows `SongRowProjector`).
 *
 * @param settings Current settings.
 * @param filter Public filter (its chart drives the meter/metadata chart).
 * @param currentSeason Catalogue season.
 * @param offers Same-publication offers, or null.
 * @param scores Selected-player score source.
 */
class SongRowProjector(
    private val settings: AppSettings,
    private val filter: SongFilter,
    private val currentSeason: Int?,
    private val offers: Map<String, ShopSong>?,
    private val scores: SongScoreSource,
) {
    private val filterChart = filter.scopedTo(settings.visibleInstruments).instrument
    private val chips = SongInstrumentStatusPolicy.showsChips(
        scores.hasPlayer, scores.available, settings.showInstrumentIcons, filterChart, settings.filterInvalidScores, settings.visibleInstruments,
    )
    private val metadataChart = filterChart ?: settings.orderedVisibleInstruments.firstOrNull()
    private val order = if (settings.enableVisualOrder) settings.songRowVisualOrder else MetadataField.entries

    /**
     * Project one song.
     *
     * @param song Catalogue row.
     * @return Row model.
     */
    fun project(song: Song): SongRowModel {
        val highlight = ShopPresentationPolicy.highlight(offers?.get(song.songId), settings.hideShop, settings.disableShopHighlighting)
        val filterRaw = filterChart?.let { song.difficulty?.chartedValue(it) }
        val meterChart = if (filterRaw == null) null else filterChart
        val detail = scores.detail
        return when {
            !scores.hasPlayer -> SongRowModel(song, highlight, chart = meterChart, chartRaw = filterRaw)
            chips && detail != null -> SongRowModel(
                song, highlight,
                chips = SongInstrumentStatusPolicy.badges(song, settings.visibleInstruments) { detail(song.songId, it)?.facts },
            )
            detail == null || settings.filterInvalidScores || metadataChart == null -> SongRowModel(
                song, highlight, chart = meterChart, chartRaw = filterRaw,
                scoreState = if (settings.filterInvalidScores && detail != null) "Scores paused while Filter Invalid Scores is on" else scores.rowState,
            )
            else -> {
                val pills = detail(song.songId, metadataChart)?.let { SongMetadataPolicy.pills(it, metadataChart, song, currentSeason, order, settings.visibleMetadata) }.orEmpty()
                SongRowModel(
                    song, highlight,
                    chart = metadataChart,
                    chartRaw = if (pills.isEmpty()) song.difficulty?.chartedValue(metadataChart) else null,
                    metadata = pills,
                    scoreState = when {
                        pills.isNotEmpty() -> null
                        song.supports(metadataChart) -> "No score"
                        else -> "No ${metadataChart.label} chart"
                    },
                )
            }
        }
    }
}

// endregion
