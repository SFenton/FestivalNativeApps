package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.format.DifficultyMeterSpec
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import com.festivalscoretracker.android.core.shop.ShopSong
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException
import kotlin.math.floor
import kotlin.math.roundToLong

// region Headers

/**
 * A labeled bucket header inserted before [firstIndex] in the row list; also a
 * Songs Quick Links target (web `songQuickLinks.ts`).
 *
 * @property id Web quick-link ID, `webId:token` (e.g. `duration:lt2`, `shop:in-shop`).
 * @property label White Title Case header and Quick Links label.
 * @property firstIndex Row index the header precedes.
 * @property spoken TalkBack label (web `landmarkLabel`).
 */
data class SongListHeader(val id: String, val label: String, val firstIndex: Int, val spoken: String = label) {
    /** Bucket token after the mode ID. */
    val token: String get() = id.substringAfter(':')

    /** Test tag: Shop buckets keep `fst.songs.shop-section.<token>`; others `fst.songs.section.<mode>.<token>`. */
    val testTag: String
        get() = if (id.startsWith("${SongSortMode.Shop.webId}:")) "fst.songs.shop-section.$token" else "fst.songs.section.${id.replace(':', '.')}"

    /** The Quick Links item for this bucket. */
    val quickLink: QuickLinkSection get() = QuickLinkSection(id, label, spokenTitle = spoken.takeIf { it != label })
}

// endregion

// region Buckets

/**
 * One bucket (web `SectionBucket`).
 *
 * @property token ID token.
 * @property label Visible label.
 * @property spoken TalkBack label.
 */
data class SongBucket(val token: String, val label: String, val spoken: String = label)

/**
 * What bucketing needs for one rebuild.
 *
 * @property mode Applied sort.
 * @property chart Chart score buckets describe (filter chart, else first visible).
 * @property offers Validated Shop offers.
 * @property scores Effective scores, when available.
 * @property nowEpochMillis Clock for Last Played.
 */
data class SongBucketContext(
    val mode: SongSortMode,
    val chart: Instrument?,
    val offers: Map<String, ShopSong> = emptyMap(),
    val scores: SongSortScores? = null,
    val nowEpochMillis: Long = System.currentTimeMillis(),
)

/** Songs Quick Links buckets (web `buildSongQuickLinkSections`). */
object SongQuickLinkBuckets {
    private val PERCENTILE_THRESHOLDS = listOf(1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100)
    private val NO_SCORE = SongBucket("no-score", "No Score")
    private const val DAY_MS = 86_400_000.0

    /**
     * Group sorted rows by first-seen bucket (rows of one bucket stay in sort order).
     * With fewer than two buckets there are no headers and the order is unchanged.
     *
     * @param sorted Sorted rows.
     * @param context Bucketing context.
     * @return Rows grouped by bucket and their headers.
     */
    fun group(sorted: List<Song>, context: SongBucketContext): Pair<List<Song>, List<SongListHeader>> {
        if (sorted.isEmpty()) return sorted to emptyList()
        val order = LinkedHashMap<String, Pair<SongBucket, MutableList<Song>>>()
        for (song in sorted) {
            val bucket = bucket(song, context)
            order.getOrPut(bucket.token) { bucket to mutableListOf() }.second += song
        }
        if (order.size < 2) return sorted to emptyList()
        val rows = ArrayList<Song>(sorted.size)
        val headers = order.values.map { (bucket, songs) ->
            SongListHeader("${context.mode.webId}:${bucket.token}", bucket.label, rows.size, bucket.spoken).also { rows += songs }
        }
        return rows to headers
    }

    /**
     * Quick Links title (web `songs.quickLinksTitle`).
     *
     * @param mode Applied sort.
     * @return "{Sort} Quick Links".
     */
    fun title(mode: SongSortMode): String = "${mode.label} Quick Links"

    /**
     * Bucket for one song.
     *
     * @param song Song.
     * @param context Context.
     * @return Bucket.
     */
    fun bucket(song: Song, context: SongBucketContext): SongBucket {
        val chart = context.chart
        val detail = if (chart != null) context.scores?.detail?.invoke(song.songId, chart) else null
        return when (context.mode) {
            SongSortMode.Title -> alpha(song.title)
            SongSortMode.Artist -> alpha(song.artist)
            SongSortMode.Year -> year(song.year)
            SongSortMode.Duration -> duration(song.durationSeconds)
            SongSortMode.Shop -> SongShopSections.bucket(song, context.offers).let { SongBucket(it.id, it.label) }
            SongSortMode.HasFC -> when {
                detail == null || detail.score <= 0 -> NO_SCORE
                detail.isFullCombo == true -> SongBucket("fc", "FC", "Full combo")
                else -> SongBucket("no-fc", "No FC", "No full combo")
            }
            SongSortMode.LastPlayed -> lastPlayed(context.scores?.latestPlayed(song.songId)?.second, context.nowEpochMillis)
            SongSortMode.Score -> score(detail)
            SongSortMode.Percentage -> percentage(detail)
            SongSortMode.Percentile -> percentile(detail)
            SongSortMode.Stars -> detail?.stars?.takeIf { it > 0 }?.let { SongBucket("$it", "$it★", if (it == 1) "1 star" else "$it stars") } ?: NO_SCORE
            SongSortMode.Season -> detail?.season?.takeIf { it > 0 }?.let { SongBucket("s$it", "S$it", "Season $it") }
                ?: SongBucket("no-season", "No Season")
            SongSortMode.Intensity -> intensity(chart?.let { song.difficulty?.chartedValue(it) })
            SongSortMode.Difficulty -> difficulty(detail)
            SongSortMode.MaxDistance -> maxDistance(detail, chart?.let(song::maxScore))
            SongSortMode.MaxScoreDiff -> maxScoreDiff(detail, chart?.let(song::maxScore))
        }
    }

    private fun alpha(text: String): SongBucket {
        val token = SongSectionIndex.firstLetter(text)
        return if (token == "#") SongBucket("#", "#", "Numbers and symbols") else SongBucket(token.lowercase(), token)
    }

    private fun year(year: Int?): SongBucket {
        if (year == null || year <= 0) return SongBucket("unknown", "Unknown Year")
        val decade = year / 10 * 10
        return SongBucket("$decade", "${decade}s")
    }

    private fun duration(seconds: Int?): SongBucket = when {
        seconds == null || seconds <= 0 -> SongBucket("unknown", "Unknown Duration")
        seconds < 120 -> SongBucket("lt2", "<2m", "Under 2 minutes")
        seconds < 180 -> SongBucket("2to3", "2-3m", "2 to 3 minutes")
        seconds < 240 -> SongBucket("3to4", "3-4m", "3 to 4 minutes")
        seconds < 300 -> SongBucket("4to5", "4-5m", "4 to 5 minutes")
        else -> SongBucket("gte5", "5m+", "5 minutes or more")
    }

    private fun lastPlayed(raw: String?, now: Long): SongBucket {
        if (raw == null) return SongBucket("never", "Never Played")
        val older = SongBucket("older", "Older")
        val millis = try {
            OffsetDateTime.parse(raw).toInstant().toEpochMilli()
        } catch (error: DateTimeParseException) {
            return older
        }
        val days = (now - millis) / DAY_MS
        return when {
            days < 1 -> SongBucket("today", "Today")
            days < 7 -> SongBucket("week", "This Week")
            days < 31 -> SongBucket("month", "This Month")
            days < 366 -> SongBucket("year", "This Year")
            else -> older
        }
    }

    private fun score(detail: SongScoreDetail?): SongBucket {
        val score = detail?.score?.takeIf { it > 0 } ?: return NO_SCORE
        val step = if (score >= 1_000_000) 100_000L else 50_000L
        val floor = score / step * step
        val label = "${compact(floor)}+"
        return SongBucket("$floor", label, "$floor or more")
    }

    /**
     * Web `formatCompactNumber`.
     *
     * @param value Non-negative value.
     * @return `1.5M`, `50k` or the value.
     */
    internal fun compact(value: Long): String = when {
        value >= 1_000_000 -> {
            val millions = value / 1_000_000.0
            if (millions == floor(millions)) "${millions.toLong()}M" else String.format(java.util.Locale.ROOT, "%.1fM", millions)
        }
        value >= 1_000 -> "${(value / 1_000.0).roundToLong()}k"
        else -> "$value"
    }

    /**
     * Accuracy buckets on the percent scale (the web compares expanded accuracy to
     * percent thresholds, which puts every score in "100%"; not ported).
     */
    private fun percentage(detail: SongScoreDetail?): SongBucket {
        val accuracy = detail?.accuracy?.takeIf { it.isFinite() && it > 0 } ?: return NO_SCORE
        val percent = accuracy / 10_000
        return when {
            percent >= 100 -> SongBucket("100", "100%")
            percent >= 99 -> SongBucket("99", "99%")
            percent >= 98 -> SongBucket("98", "98%")
            percent >= 95 -> SongBucket("95", "95-97%", "95 to 97%")
            percent >= 90 -> SongBucket("90", "90-94%", "90 to 94%")
            else -> SongBucket("lt90", "<90%", "Under 90%")
        }
    }

    private fun percentile(detail: SongScoreDetail?): SongBucket {
        val rank = detail?.rank ?: 0
        val total = detail?.totalEntries ?: 0
        if (rank <= 0 || total <= 0) return SongBucket("no-rank", "No Rank")
        val pct = minOf(rank.toDouble() / total * 100, 100.0)
        val bucket = PERCENTILE_THRESHOLDS.first { pct <= it }
        return SongBucket("$bucket", "$bucket%", "Top $bucket%")
    }

    private fun intensity(raw: Double?): SongBucket {
        val bars = raw?.let { DifficultyMeterSpec.filledBars(it, raw = true) } ?: return SongBucket("unknown", "Unknown Intensity")
        return SongBucket("${bars - 1}", "$bars", "Difficulty $bars of 7")
    }

    private fun difficulty(detail: SongScoreDetail?): SongBucket {
        if (detail == null || detail.score <= 0) return NO_SCORE
        val value = detail.difficulty?.takeIf { it >= 0 && it.isFinite() } ?: return SongBucket("unknown", "Unknown Difficulty")
        val index = value.toInt()
        val label = if (value == floor(value) && index in 0..3) SongMetadataPolicy.DIFFICULTY_NAMES[index] else "$value"
        return SongBucket("$index", label)
    }

    private fun maxDistance(detail: SongScoreDetail?, max: Int?): SongBucket {
        val score = detail?.score?.takeIf { it > 0 } ?: return NO_SCORE
        if (max == null) return SongBucket("max-unavailable", "Max Score Unavailable")
        val ratio = score.toDouble() / max
        return when {
            ratio >= 1 -> SongBucket("100", "100%")
            ratio >= 0.99 -> SongBucket("99", "99%+", "99% or more")
            ratio >= 0.98 -> SongBucket("98", "98%+", "98% or more")
            ratio >= 0.95 -> SongBucket("95", "95%+", "95% or more")
            ratio >= 0.9 -> SongBucket("90", "90%+", "90% or more")
            else -> SongBucket("lt90", "<90%", "Under 90%")
        }
    }

    private fun maxScoreDiff(detail: SongScoreDetail?, max: Int?): SongBucket {
        val score = detail?.score?.takeIf { it > 0 } ?: return NO_SCORE
        if (max == null) return SongBucket("max-unavailable", "Max Score Unavailable")
        val diff = score - max
        return when {
            diff >= 0 -> SongBucket("max", "At Max")
            diff >= -1_000 -> SongBucket("lt1k", "<1k", "Within 1,000")
            diff >= -5_000 -> SongBucket("lt5k", "<5k", "Within 5,000")
            diff >= -10_000 -> SongBucket("lt10k", "<10k", "Within 10,000")
            diff >= -25_000 -> SongBucket("lt25k", "<25k", "Within 25,000")
            diff >= -50_000 -> SongBucket("lt50k", "<50k", "Within 50,000")
            else -> SongBucket("gte50k", "50k+", "50,000 or more below max")
        }
    }
}

// endregion
