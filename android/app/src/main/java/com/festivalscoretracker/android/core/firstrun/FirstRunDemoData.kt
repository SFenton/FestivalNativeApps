package com.festivalscoretracker.android.core.firstrun

import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.songs.SongMetadataPill
import com.festivalscoretracker.android.core.songs.SongPercentileTier
import java.text.NumberFormat
import java.util.Locale

// region Slides

/** The first-run slides whose web demos swap data on a timer (issue #58); every other demo stays still. */
object FirstRunRotatingDemos {
    /** Slide IDs of the twelve rotating web demos. */
    val IDS: Set<String> = setOf(
        "songs-song-list", "songs-icons", "songs-metadata", "statistics-top-songs",
        "songinfo-bar-select", "suggestions-category-card", "leaderboards-experimental-metrics",
        "compete-hub", "compete-rivals", "rivals-overview", "rivals-instruments", "rivals-detail",
    )
}

// endregion

// region Songs

/**
 * One song a rotating demo row shows: a real catalogue song, or a placeholder drawn as
 * redacted bars while the catalogue loads or is unavailable (demos never invent titles).
 *
 * @property id Catalogue song ID (`placeholder-<n>` for a placeholder).
 * @property title Title (empty for a placeholder).
 * @property artist Artist (empty for a placeholder).
 * @property year Release year.
 * @property artUrl Resolved album-art URL, if any.
 * @property isPlaceholder Whether this stands in for a song.
 */
data class FirstRunDemoSong(
    val id: String,
    val title: String,
    val artist: String,
    val year: Int? = null,
    val artUrl: String? = null,
    val isPlaceholder: Boolean = false,
) {
    companion object {
        /**
         * Distinct placeholder rows.
         *
         * @param count Rows.
         * @return [count] placeholders.
         */
        fun placeholders(count: Int): List<FirstRunDemoSong> =
            List(count.coerceAtLeast(0)) { FirstRunDemoSong("placeholder-$it", "", "", isPlaceholder = true) }
    }
}

// endregion

// region Rankings and rivals

/**
 * One leaderboard row (web `DemoRankingEntry`).
 *
 * @property rank Rank.
 * @property name Display name.
 * @property rating Formatted total.
 * @property isPlayer Whether it is the player's own row.
 */
data class FirstRunDemoRanking(val rank: Int, val name: String, val rating: String, val isPlayer: Boolean = false)

/**
 * One rival summary (web `RivalSummary`).
 *
 * @property name Display name.
 * @property rivalScore Rival score.
 * @property shared Shared songs.
 * @property ahead Songs the rival leads.
 * @property behind Songs the rival trails.
 * @property avgDelta Average rank delta.
 */
data class FirstRunDemoRival(val name: String, val rivalScore: Int, val shared: Int, val ahead: Int, val behind: Int, val avgDelta: Int)

/**
 * One head-to-head rank pair (web `RivalsDetailDemo` `CATEGORY_RANK_DATA`).
 *
 * @property userRank Player rank.
 * @property rivalRank Rival rank.
 * @property userScore Player score.
 * @property rivalScore Rival score.
 */
data class FirstRunDemoComparison(val userRank: Int, val rivalRank: Int, val userScore: Int, val rivalScore: Int) {
    /** Whether the player leads. */
    val playerWins: Boolean get() = userRank < rivalRank
}

/**
 * A Rivals detail category with its four rank rows.
 *
 * @property title Category title.
 * @property ranks Rank rows.
 */
data class FirstRunDemoRivalCategory(val title: String, val ranks: List<FirstRunDemoComparison>)

/** Web `firstRun/demoData.ts` and per-demo pools. */
object FirstRunDemoPools {
    /** Web `DEMO_RANKINGS`. */
    val RANKINGS: List<FirstRunDemoRanking> = listOf(
        FirstRunDemoRanking(1, "GoldStreak", "2,480,000"), FirstRunDemoRanking(2, "NoteHunter", "2,310,500"),
        FirstRunDemoRanking(3, "BeatLegend", "2,275,100"), FirstRunDemoRanking(4, "VocalStorm", "2,198,000"),
        FirstRunDemoRanking(5, "BassRuler", "2,112,800"), FirstRunDemoRanking(6, "TopClutch", "2,045,300"),
        FirstRunDemoRanking(7, "StageKnight", "1,998,700"), FirstRunDemoRanking(8, "RhythmEdge", "1,922,400"),
        FirstRunDemoRanking(9, "FretBlaze", "1,874,600"), FirstRunDemoRanking(10, "ComboKing", "1,801,200"),
    )

    /** The player's own row (web `DEMO_PLAYER`). */
    val PLAYER: FirstRunDemoRanking = FirstRunDemoRanking(42, "You", "1,250,000", isPlayer = true)

    /** Web `DEMO_RIVALS_ABOVE`. */
    val RIVALS_ABOVE: List<FirstRunDemoRival> = listOf(
        FirstRunDemoRival("KeyDrifter", 920, 148, 82, 66, 12), FirstRunDemoRival("DeepGroove", 870, 135, 75, 60, 8),
        FirstRunDemoRival("SonicRush", 840, 120, 68, 52, 5), FirstRunDemoRival("FretPhenom", 900, 155, 88, 67, 10),
        FirstRunDemoRival("NeonPick", 855, 122, 70, 52, 7), FirstRunDemoRival("BeatForge", 830, 118, 65, 53, 4),
    )

    /** Web `DEMO_RIVALS_BELOW`. */
    val RIVALS_BELOW: List<FirstRunDemoRival> = listOf(
        FirstRunDemoRival("DrumSurge", 790, 142, 58, 84, -10), FirstRunDemoRival("ShredLord", 750, 130, 50, 80, -14),
        FirstRunDemoRival("NoteCrush", 710, 118, 44, 74, -18), FirstRunDemoRival("AxelStrike", 770, 138, 54, 84, -12),
        FirstRunDemoRival("LowTide", 730, 126, 46, 80, -16), FirstRunDemoRival("OffBeat", 695, 112, 40, 72, -20),
    )

    /** Instruments of the Rivals instruments demo, in order. */
    val INSTRUMENT_RIVAL_ORDER: List<Instrument> = listOf(Instrument.Lead, Instrument.Drums, Instrument.Vocals)

    /** Web `DEMO_INSTRUMENT_RIVALS`: per instrument, rivals above then below (index 0 shown first). */
    val INSTRUMENT_RIVALS: Map<Instrument, Pair<List<FirstRunDemoRival>, List<FirstRunDemoRival>>> = mapOf(
        Instrument.Lead to (
            listOf(FirstRunDemoRival("StageKnight", 860, 140, 78, 62, 6), FirstRunDemoRival("FretPhenom", 890, 145, 82, 63, 9), FirstRunDemoRival("NeonPick", 845, 130, 72, 58, 5)) to
                listOf(FirstRunDemoRival("FretBlaze", 720, 125, 48, 77, -12), FirstRunDemoRival("AxelStrike", 700, 118, 42, 76, -15), FirstRunDemoRival("LowTide", 680, 110, 38, 72, -18))
            ),
        Instrument.Drums to (
            listOf(FirstRunDemoRival("BeatLegend", 910, 132, 80, 52, 14), FirstRunDemoRival("BeatForge", 875, 128, 74, 54, 10), FirstRunDemoRival("DoubleSnare", 850, 120, 70, 50, 8)) to
                listOf(FirstRunDemoRival("RhythmEdge", 680, 115, 40, 75, -20), FirstRunDemoRival("OffBeat", 660, 108, 36, 72, -22), FirstRunDemoRival("DrumSurge", 640, 100, 32, 68, -24))
            ),
        Instrument.Vocals to (
            listOf(FirstRunDemoRival("VocalStorm", 880, 128, 74, 54, 10), FirstRunDemoRival("SonicRush", 860, 122, 70, 52, 8), FirstRunDemoRival("NoteHunter", 840, 116, 66, 50, 6)) to
                listOf(FirstRunDemoRival("TopClutch", 700, 110, 42, 68, -16), FirstRunDemoRival("NoteCrush", 680, 104, 38, 66, -18), FirstRunDemoRival("KeyDrifter", 660, 98, 34, 64, -20))
            ),
    )

    /** The rival named by the Rivals detail demo. */
    const val DETAIL_RIVAL: String = "KeyDrifter"

    /** Web `RivalsDetailDemo` `CATEGORIES` with `CATEGORY_RANK_DATA`, in display order. */
    val RIVAL_DETAIL_CATEGORIES: List<FirstRunDemoRivalCategory> = listOf(
        FirstRunDemoRivalCategory("Closest Battles", ranks(14, 15, 988_000, 987_500, 23, 22, 965_000, 965_800, 8, 9, 995_200, 994_900, 31, 30, 942_000, 942_600)),
        FirstRunDemoRivalCategory("Almost Passed", ranks(18, 15, 971_000, 978_000, 12, 9, 986_000, 992_000, 26, 22, 950_000, 958_000, 35, 31, 930_000, 938_000)),
        FirstRunDemoRivalCategory("Slipping Away", ranks(28, 12, 945_000, 985_000, 40, 18, 910_000, 970_000, 35, 15, 930_000, 978_000, 48, 22, 890_000, 960_000)),
        FirstRunDemoRivalCategory("Barely Winning", ranks(15, 18, 978_000, 971_000, 9, 12, 992_000, 986_000, 22, 26, 958_000, 950_000, 31, 35, 938_000, 930_000)),
        FirstRunDemoRivalCategory("Pulling Forward", ranks(8, 22, 994_000, 960_000, 5, 18, 998_000, 970_000, 12, 30, 986_000, 940_000, 10, 26, 990_000, 952_000)),
        FirstRunDemoRivalCategory("Dominating Them", ranks(3, 45, 999_000, 895_000, 2, 38, 999_500, 915_000, 5, 52, 998_000, 880_000, 4, 60, 998_500, 860_000)),
    )

    /** Web `TopSongsDemo` `DEMO_PERCENTILES`, assigned by row index. */
    val TOP_SONG_PERCENTILES: List<Double> = listOf(1.2, 3.5, 7.8, 14.2, 22.6, 35.1, 48.9)

    /**
     * Experimental "Rank By" metrics with their descriptions (web `ExperimentalMetricsDemo`).
     */
    val EXPERIMENTAL_METRICS: List<Pair<String, String>> = listOf(
        "Adjusted Percentile" to "Estimated skill from your rank position.",
        "Popularity-Weighted Percentile" to "Adjusts for how many players know this song.",
        "FC Rate" to "Share of your tracked scores that were full combos.",
        "Max Score %" to "How close your best score is to the song's ceiling.",
    )

    private fun ranks(vararg values: Int): List<FirstRunDemoComparison> =
        values.toList().chunked(4).map { (user, rival, userScore, rivalScore) -> FirstRunDemoComparison(user, rival, userScore, rivalScore) }

    /**
     * "Top 1.2%" for a Top Songs row.
     *
     * @param index Row index.
     * @return Percentile label.
     */
    fun topSongPercentile(index: Int): String {
        val value = TOP_SONG_PERCENTILES[index.coerceAtLeast(0) % TOP_SONG_PERCENTILES.size]
        return "Top ${if (value == Math.floor(value)) value.toInt().toString() else value.toString()}%"
    }

    /**
     * Songs-row percentile styling for a "Top N%" label: gold fill to 1%, gold outline to 5%.
     *
     * @param label Percentile label.
     * @return Tier.
     */
    fun percentileTier(label: String): SongPercentileTier {
        val value = label.filter { it.isDigit() || it == '.' }.toDoubleOrNull() ?: return SongPercentileTier.Ordinary
        return when {
            value <= 1 -> SongPercentileTier.TopOne
            value <= 5 -> SongPercentileTier.TopFive
            else -> SongPercentileTier.Ordinary
        }
    }
}

// endregion

// region Song Info bar select

/**
 * One bar of the Song Info bar-select demo (web `BarSelectDemo`).
 *
 * @property accuracy Accuracy percent (bar height).
 * @property score Score.
 * @property date Relative date label.
 * @property fullCombo Whether it was a full combo (gold bar).
 */
data class FirstRunDemoBar(val accuracy: Int, val score: Int, val date: String, val fullCombo: Boolean = false)

/** Bar-select demo data. */
object FirstRunDemoBars {
    /** The three tracked scores, oldest first. */
    val BARS: List<FirstRunDemoBar> = listOf(
        FirstRunDemoBar(62, 218_400, "2 days ago"),
        FirstRunDemoBar(78, 347_100, "Yesterday"),
        FirstRunDemoBar(100, 486_500, "Today", fullCombo = true),
    )
}

// endregion

// region Songs metadata

/**
 * Per-song demo metadata (web `MetadataDemo` `META_DATA`).
 *
 * @property score Score.
 * @property accuracy Expanded accuracy (1,000,000 = 100%).
 * @property fullCombo Full combo.
 * @property stars Stars (6 = gold).
 * @property percentile Percentile label.
 * @property season Season.
 * @property intensity Raw song intensity.
 */
data class FirstRunDemoMeta(
    val score: Int,
    val accuracy: Int,
    val fullCombo: Boolean,
    val stars: Int,
    val percentile: String,
    val season: Int,
    val intensity: Int,
)

/** The two metadata pills a metadata-demo row shows (web `MetadataLayout`). */
enum class FirstRunDemoMetaLayout(val fields: List<MetadataField>) {
    /** Score and accuracy. */
    ScoreAccuracy(listOf(MetadataField.Score, MetadataField.Percentage)),

    /** Stars and intensity. */
    StarsDifficulty(listOf(MetadataField.Stars, MetadataField.Intensity)),

    /** Percentile and season. */
    PercentileSeason(listOf(MetadataField.Percentile, MetadataField.Season)),

    /** Score and stars. */
    ScoreStars(listOf(MetadataField.Score, MetadataField.Stars)),

    /** Accuracy and intensity. */
    AccuracyDifficulty(listOf(MetadataField.Percentage, MetadataField.Intensity)),

    /** Percentile and score. */
    PercentileScore(listOf(MetadataField.Percentile, MetadataField.Score)),
}

/**
 * One metadata-demo row.
 *
 * @property song Song.
 * @property meta Metadata values.
 * @property layout Pills shown.
 */
data class FirstRunDemoMetaRow(val song: FirstRunDemoSong, val meta: FirstRunDemoMeta, val layout: FirstRunDemoMetaLayout)

/**
 * The metadata demo's rows: each swap changes a row's song, metadata and layout,
 * picking a layout no other row shows (web `MetadataDemo` `pickNewLayout`).
 *
 * @property songs Song rotation (drives which rows swap).
 * @property metas Metadata per row.
 * @property layouts Layout per row.
 */
data class FirstRunMetadataRotation(
    val songs: FirstRunRowRotation<FirstRunDemoSong>,
    val metas: List<FirstRunDemoMeta>,
    val layouts: List<FirstRunDemoMetaLayout>,
    private val tick: Int = 0,
) {
    /** The rows currently shown. */
    val rows: List<FirstRunDemoMetaRow> get() = songs.rows.mapIndexed { i, song -> FirstRunDemoMetaRow(song, metas[i], layouts[i]) }

    /**
     * The rows the next swap fades out.
     *
     * @return Row indices.
     */
    fun nextIndices(): List<Int> = songs.nextIndices()

    /**
     * Swap [indices] to new songs with new metadata and an unused layout.
     *
     * @param indices Rows to replace.
     * @return Rotated state.
     */
    fun swapped(indices: List<Int>): FirstRunMetadataRotation {
        val random = SplitMix64(tick.toLong() * 0x9E3779B9L + 7)
        val nextLayouts = layouts.toMutableList()
        val nextMetas = metas.toMutableList()
        for (index in indices) {
            if (index !in nextLayouts.indices) continue
            val unused = FirstRunDemoMetaLayout.entries.filter { it !in nextLayouts }.ifEmpty { FirstRunDemoMetaLayout.entries }
            nextLayouts[index] = unused[random.nextInt(unused.size)]
            val metaChoices = META.filter { it != nextMetas[index] }
            nextMetas[index] = metaChoices[random.nextInt(metaChoices.size)]
        }
        return copy(songs = songs.swapped(indices), metas = nextMetas, layouts = nextLayouts, tick = tick + 1)
    }

    /** Data and pill projection. */
    companion object {
        /** Web `META_DATA`. */
        val META: List<FirstRunDemoMeta> = listOf(
            FirstRunDemoMeta(198_942, 1_000_000, true, 6, "Top 1%", 12, 4),
            FirstRunDemoMeta(157_320, 980_000, false, 5, "Top 5%", 10, 3),
            FirstRunDemoMeta(142_800, 960_000, false, 5, "Top 8%", 11, 5),
            FirstRunDemoMeta(185_600, 1_000_000, true, 6, "Top 2%", 9, 2),
            FirstRunDemoMeta(123_400, 940_000, false, 4, "Top 15%", 8, 4),
            FirstRunDemoMeta(176_100, 1_000_000, true, 6, "Top 3%", 12, 3),
            FirstRunDemoMeta(110_250, 910_000, false, 4, "Top 20%", 7, 5),
            FirstRunDemoMeta(168_900, 970_000, false, 5, "Top 6%", 11, 2),
            FirstRunDemoMeta(191_200, 1_000_000, true, 6, "Top 1%", 10, 4),
            FirstRunDemoMeta(135_700, 950_000, false, 5, "Top 10%", 9, 3),
        )

        /**
         * Start with the first [visible] songs, metadata in order and layouts in order.
         *
         * @param pool Songs.
         * @param visible Rows.
         * @return Initial state.
         */
        fun start(pool: List<FirstRunDemoSong>, visible: Int): FirstRunMetadataRotation {
            val songs = FirstRunRowRotation.start(pool, visible) { it.id }
            val count = songs.rows.size
            return FirstRunMetadataRotation(
                songs,
                List(count) { META[it % META.size] },
                List(count) { FirstRunDemoMetaLayout.entries[it % FirstRunDemoMetaLayout.entries.size] },
            )
        }

        /**
         * The metadata pills of one row, styled like Songs rows.
         *
         * @param meta Values.
         * @param layout Pills to show.
         * @param locale Number locale.
         * @return Pills in layout order.
         */
        fun pills(meta: FirstRunDemoMeta, layout: FirstRunDemoMetaLayout, locale: Locale = Locale.getDefault()): List<SongMetadataPill> =
            layout.fields.map { field ->
                when (field) {
                    MetadataField.Score -> NumberFormat.getIntegerInstance(locale).format(meta.score).let { SongMetadataPill(field, it, "Score $it") }
                    MetadataField.Percentage -> {
                        val text = "${ScoreFormatting.accuracy(meta.accuracy.toDouble(), locale)}%"
                        if (meta.fullCombo) {
                            SongMetadataPill(field, "$text FC", "Full combo, accuracy $text", fullCombo = true)
                        } else {
                            SongMetadataPill(field, text, "Accuracy $text", tint = ScoreFormatting.accuracyTint(meta.accuracy.toDouble()))
                        }
                    }
                    MetadataField.Stars -> {
                        val gold = meta.stars >= 6
                        val count = if (gold) 5 else meta.stars
                        SongMetadataPill(field, "★".repeat(count), if (gold) "$count gold stars" else "$count stars", starCount = count, goldStars = gold)
                    }
                    MetadataField.Percentile -> SongMetadataPill(field, meta.percentile, meta.percentile, percentile = FirstRunDemoPools.percentileTier(meta.percentile))
                    MetadataField.Season -> SongMetadataPill(field, "S${meta.season}", "Season ${meta.season}")
                    else -> SongMetadataPill(MetadataField.Intensity, "", "Song intensity", intensityRaw = meta.intensity.toDouble())
                }
            }
    }
}

// endregion

// region Suggestions

/**
 * One song of the suggestions demo card.
 *
 * @property song Song.
 * @property instrument Instrument icon shown.
 * @property detail Percent or percentile label, if any.
 */
data class FirstRunDemoSuggestionItem(val song: FirstRunDemoSong, val instrument: Instrument?, val detail: String?)

/**
 * A suggestions-demo category template (web `CategoryCardDemo` `TEMPLATES`).
 *
 * @property key Category key.
 * @property title Title.
 * @property description Description.
 * @property instrument Card instrument, if any.
 */
data class FirstRunDemoSuggestionTemplate(val key: String, val title: String, val description: String, val instrument: Instrument?) {
    /**
     * The card's songs: `pool[(templateIndex * 5 + i) % n]` for up to [count] songs.
     *
     * @param templateIndex This template's index.
     * @param pool Songs.
     * @param count Songs to show (web 5).
     * @return Items.
     */
    fun items(templateIndex: Int, pool: List<FirstRunDemoSong>, count: Int = 5): List<FirstRunDemoSuggestionItem> {
        if (pool.isEmpty()) return emptyList()
        return List(minOf(count, pool.size)) { i ->
            val song = pool[(templateIndex * 5 + i) % pool.size]
            when (key) {
                "unfc_guitar" -> FirstRunDemoSuggestionItem(song, Instrument.Lead, "${100 - i * 2}%")
                "pct_push_bass" -> FirstRunDemoSuggestionItem(song, Instrument.Bass, "Top ${3 + i}%")
                "near_fc_any" -> FirstRunDemoSuggestionItem(song, NEAR_FC_INSTRUMENTS[i % NEAR_FC_INSTRUMENTS.size], null)
                else -> FirstRunDemoSuggestionItem(song, instrument, null)
            }
        }
    }

    /** Templates in rotation order. */
    companion object {
        private val NEAR_FC_INSTRUMENTS = listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals)

        /** Web `TEMPLATES`, in order. */
        val TEMPLATES: List<FirstRunDemoSuggestionTemplate> = listOf(
            FirstRunDemoSuggestionTemplate("unfc_guitar", "Finish the Lead FCs", "Play these songs again on Lead and grab an FC!", Instrument.Lead),
            FirstRunDemoSuggestionTemplate("pct_push_bass", "Percentile Push: Bass", "Replay these Bass songs to jump to the next percentile bracket.", Instrument.Bass),
            FirstRunDemoSuggestionTemplate("near_fc_any", "FC These Next!", "If you can get gold stars, you can FC it!", null),
            FirstRunDemoSuggestionTemplate("unplayed_drums", "New on Drums", "Songs you haven't played on Drums yet.", Instrument.Drums),
        )
    }
}

// endregion
