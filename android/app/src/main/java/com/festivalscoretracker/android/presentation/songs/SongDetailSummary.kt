package com.festivalscoretracker.android.presentation.songs

import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.songs.InvalidScoreReason
import com.festivalscoretracker.android.core.songs.SongMetadataPolicy
import com.festivalscoretracker.android.core.songs.SongScoreSource
import java.text.NumberFormat
import java.util.Locale

// region Your score

/**
 * The selected player's line on one Song Detail chart card.
 *
 * @property text Visible and spoken text.
 * @property scored Whether it describes a positive score (gold emphasis).
 * @property rank The player's rank on this chart, when known.
 */
data class ChartScoreSummary(val text: String, val scored: Boolean, val rank: Int? = null)

/** Builds Song Detail's per-chart "Your score" line (web `InstrumentCard` player row). */
object SongDetailSummary {
    /**
     * Summary for one chart, or null without a selected player.
     *
     * @param source Publication-matched score source (effective scores under Filter Invalid Scores).
     * @param playerName Selected player's name.
     * @param song Song.
     * @param chart Chart.
     * @param locale Formatting locale.
     * @return Summary or null.
     */
    fun summary(
        source: SongScoreSource,
        playerName: String,
        song: Song,
        chart: Instrument,
        locale: Locale = Locale.getDefault(),
    ): ChartScoreSummary? {
        if (!source.hasPlayer) return null
        val lookup = source.detail ?: return ChartScoreSummary(source.rowState ?: "Loading scores", scored = false)
        if (!song.supports(chart)) return ChartScoreSummary("${chart.label} is not charted for this song", scored = false)
        val reason = source.invalid(song.songId)[chart]
        val detail = lookup(song.songId, chart)
        if (reason == InvalidScoreReason.NoFallback) {
            return ChartScoreSummary("No valid ${chart.label} score for $playerName at this leeway (Filter Invalid Scores)", scored = false)
        }
        if (detail == null || detail.score <= 0) return ChartScoreSummary("No ${chart.label} score for $playerName", scored = false)
        val numbers = NumberFormat.getIntegerInstance(locale)
        val parts = mutableListOf("Your score: ${numbers.format(detail.score)}")
        detail.accuracy?.takeIf { it.isFinite() }?.let { parts += "${ScoreFormatting.accuracy(it, locale)}%" }
        if (detail.isFullCombo == true) parts += "FC"
        SongMetadataPolicy.percentileBucket(detail.rank, detail.totalEntries)?.let { parts += it }
        val rank = detail.rank?.takeIf { it > 0 }
        rank?.let { parts += "#${numbers.format(it)}" }
        if (reason == InvalidScoreReason.Fallback) parts += "next valid score"
        return ChartScoreSummary(parts.joinToString(" · "), scored = true, rank = rank)
    }
}

// endregion
