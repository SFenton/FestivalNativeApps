package com.festivalscoretracker.android.core.suggestions

import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Produces score-driven Suggestions categories from the catalogue and the selected
 * player's score index: a line-for-line port of Apple `SuggestionGenerator.swift`
 * (itself ported from the web `suggestionGenerator.ts`), kept order-identical so a
 * fixed seed yields exactly the Apple/Windows output (`SuggestionParityTest`).
 *
 * Order-sensitive rules for anyone editing this file: pipelines are listed in the
 * Apple order; [Instrument.entries] is Apple `Instrument.allCases`; every sort with
 * possible ties is stable (`sortedBy`); keyed groups sort by ordinal string order;
 * every RNG draw happens in the same place as on Apple.
 *
 * Band pipelines are not ported (no selected-band context). Rival pipelines run once
 * [setRivalData] supplies an index. Not thread-safe; confine to one coroutine context.
 *
 * @param rng Random source; defaults to Mulberry32 seeded from [Options.seed].
 * @param options Tuning knobs.
 */
class SuggestionGenerator(
    private val options: Options = Options(),
    private val rng: SuggestionRng = SeededSuggestionRng(options.seed),
) {
    /**
     * Tuning knobs (web `SuggestionGeneratorOptions`).
     *
     * @property seed 32-bit seed (`0..4294967295`).
     * @property disableSkipping Skip the emit-probability roll (tests).
     * @property fixedDisplayCount Force every category to this many songs instead of 2–5.
     * @property currentSeason Current season; stale families are disabled at 0.
     */
    data class Options(
        val seed: Long = 1,
        val disableSkipping: Boolean = false,
        val fixedDisplayCount: Int? = null,
        val currentSeason: Int = 0,
    )

    /** One (song, chart) pairing considered before final selection. */
    private data class Candidate(val song: Song, val score: SuggestionScore?, val instrument: Instrument?)

    private val currentSeason = options.currentSeason
    private var songs: List<Song> = emptyList()
    private var songsById: Map<String, Song> = emptyMap()
    private var scoresIndex: SuggestionScoreIndex = emptyMap()
    private var rivalData: RivalDataIndex? = null

    private val emitted = HashSet<String>()
    private var pipelines = ArrayDeque<() -> List<SuggestionCategory>>()
    private var initialized = false

    private val sessionShownSongs = HashSet<String>()
    private val recentSongIds = ArrayDeque<String>()
    private val recentArtists = ArrayDeque<String>()
    private val categorySongHistory = HashMap<String, MutableSet<String>>()
    private val categorySkipStreak = HashMap<String, Int>()
    private val firstPlaysMixedLastInstrument = HashMap<String, Instrument>()

    // region Public API

    /**
     * Supply the catalogue and the selected player's score index.
     *
     * @param songs Current catalogue rows.
     * @param scoresIndex songId → chart → score.
     */
    fun setSource(songs: List<Song>, scoresIndex: SuggestionScoreIndex) {
        this.songs = songs
        this.scoresIndex = scoresIndex
        val byId = LinkedHashMap<String, Song>()
        for (song in songs) byId.putIfAbsent(song.songId, song)
        songsById = byId
    }

    /**
     * Inject rival data for the `song_rival_*` families (null disables them).
     *
     * Before the first [getNext] the rival pipelines join the startup shuffle; after
     * it they are shuffled on their own and spliced at the front of the queue.
     *
     * @param data Index from [RivalDataIndex.build], or null.
     */
    fun setRivalData(data: RivalDataIndex?) {
        rivalData = data
        if (data == null || !initialized) return
        val additions = rivalPipelines(data)
        shuffleInPlace(additions)
        val merged = ArrayDeque<() -> List<SuggestionCategory>>(additions.size + pipelines.size)
        merged.addAll(additions)
        merged.addAll(pipelines)
        pipelines = merged
    }

    /**
     * Produce up to [count] more categories, continuing from the last call.
     *
     * @param count Page size.
     * @return New categories; fewer than [count] (or none) once pipelines are exhausted.
     */
    fun getNext(count: Int): List<SuggestionCategory> {
        ensurePipelines()
        val produced = ArrayList<SuggestionCategory>()
        var safety = 0
        while (produced.size < count && pipelines.isNotEmpty() && safety < 500) {
            safety++
            val pipe = pipelines.removeFirst()
            for (category in pipe()) {
                if (category.songs.isEmpty() || category.key in emitted) continue
                emitted += category.key
                produced += category
                if (produced.size >= count) break
            }
        }
        return produced
    }

    /** Start a fresh mix: clears emitted keys and shown songs, keeps the source (web "Start New Mix"). */
    fun resetForEndless() {
        initialized = false
        pipelines = ArrayDeque()
        emitted.clear()
        sessionShownSongs.clear()
        ensurePipelines()
    }

    // endregion

    // region Pipeline construction

    private fun ensurePipelines() {
        if (initialized) return
        initialized = true
        val list = mutableListOf<() -> List<SuggestionCategory>>(
            ::fcTheseNext, ::fcTheseNextDecade, ::nearFcRelaxed, ::nearFcRelaxedDecade,
            ::almostSixStars, ::almostSixStarsDecade, ::starGains, ::starGainsDecade,
            ::firstPlaysMixed, ::firstPlaysMixedDecade, ::unplayedAll, ::unplayedAllDecade,
            ::varietyPack, ::artistSamplerRotating, ::getMoreStars, ::getMoreStarsDecade,
            ::almostElite, ::almostEliteDecade, ::percentilePush, ::percentilePushDecade,
            ::artistFocusUnplayed, ::sameNameSets, ::sameNameNearFc, ::samePercentileBucket,
        )
        for (instrument in Instrument.entries) {
            list += { unFcInstrument(instrument) }
            list += { unFcInstrumentDecade(instrument) }
            list += { unplayedInstrument(instrument) }
            list += { unplayedInstrumentDecade(instrument) }
            list += { almostEliteInstrument(instrument) }
            list += { almostEliteInstrumentDecade(instrument) }
            list += { percentilePushInstrument(instrument) }
            list += { percentilePushInstrumentDecade(instrument) }
            list += { improveInstrumentRankings(instrument) }
            for (seasons in 1..5) list += { staleInstrument(instrument, seasons) }
            for (bucket in PERCENTILE_BUCKETS) list += { percentileImproveInstrument(instrument, bucket) }
        }
        for (seasons in 1..5) list += { staleGlobal(seasons) }
        for (bucket in PERCENTILE_BUCKETS) {
            list += { samePercentileBucketSpecific(bucket) }
            list += { percentileImproveBucket(bucket) }
        }
        for (tier in NEAR_MAX_TIERS) {
            list += { nearMaxScore(tier) }
            list += { nearMaxScoreDecade(tier) }
        }
        rivalData?.let { list += rivalPipelines(it) }
        shuffleInPlace(list)
        pipelines = ArrayDeque(list)
    }

    /** Generic rival families, then five per kept rival, in the web order. */
    private fun rivalPipelines(data: RivalDataIndex): MutableList<() -> List<SuggestionCategory>> {
        val list = mutableListOf<() -> List<SuggestionCategory>>(
            ::songRivalBattleground, ::songRivalNearFc, ::songRivalStale, ::songRivalStarGains, ::songRivalPctPush,
        )
        for (rival in data.songRivals) {
            val id = rival.accountId
            list += { songRivalGap(id) }
            list += { songRivalProtect(id) }
            list += { songRivalSpotlight(id) }
            list += { songRivalSlipping(id) }
            list += { songRivalDominate(id) }
        }
        return list
    }

    // endregion

    // region Shared helpers

    private fun <T> shuffleInPlace(list: MutableList<T>) {
        if (list.size <= 1) return
        var i = list.size - 1
        while (i > 0) {
            val j = rng.nextInt(i + 1)
            val tmp = list[i]
            list[i] = list[j]
            list[j] = tmp
            i--
        }
    }

    private fun displayCount(): Int {
        options.fixedDisplayCount?.let { return max(1, it) }
        return 2 + rng.nextInt(4)
    }

    private fun canon(value: String?): String = (value ?: "").trim().lowercase()

    private fun rawPercentile(score: SuggestionScore): Double? {
        val rank = score.rank ?: return null
        val total = score.totalEntries ?: return null
        if (rank <= 0 || total <= 0) return null
        return rank.toDouble() / total.toDouble()
    }

    private fun latestSeason(songId: String): Int {
        val scores = scoresIndex[songId] ?: return 0
        return Instrument.entries.mapNotNull { scores[it]?.season }.maxOrNull() ?: 0
    }

    private fun instrumentSeason(songId: String, instrument: Instrument): Int = scoresIndex[songId]?.get(instrument)?.season ?: 0

    /** Fresh-candidate count for the emit table; always keyed on plain song id (web `getFreshCount`). */
    private fun freshCount(pool: List<Candidate>): Int = pool.count { it.song.songId !in sessionShownSongs }

    private fun shouldEmit(key: String, candidateCount: Int): Boolean {
        if (options.disableSkipping) return candidateCount > 0
        val prob = EMIT_TABLE.firstOrNull { candidateCount >= it.first }?.second ?: 0.38
        val skipped = categorySkipStreak[key] ?: 0
        if (skipped >= 2) {
            categorySkipStreak[key] = 0
            return true
        }
        val emit = rng.nextDouble() < prob
        categorySkipStreak[key] = if (emit) 0 else skipped + 1
        return emit
    }

    /** History identity: song+instrument for the mixed first-plays family, song id otherwise. */
    private fun historyId(candidate: Candidate, categoryKey: String): String {
        if (categoryKey != "first_plays_mixed" && !categoryKey.startsWith("first_plays_mixed_")) return candidate.song.songId
        return "${candidate.song.songId}:${candidate.instrument?.wireId ?: "any"}"
    }

    /** New-first selection with fallback to category- and session-repeated songs (web `selectNewFirst`). */
    private fun selectNewFirst(categoryKey: String, pool: List<Candidate>, take: Int): List<Candidate> {
        if (pool.isEmpty() || take <= 0) return emptyList()
        val used = HashSet(categorySongHistory[categoryKey] ?: emptySet())
        if (pool.all { historyId(it, categoryKey) in used }) used.clear()

        val freshNew = pool.filterTo(ArrayList()) {
            val id = historyId(it, categoryKey)
            id !in sessionShownSongs && id !in used
        }
        shuffleInPlace(freshNew)
        val freshNewIds = freshNew.mapTo(HashSet()) { it.song.songId }

        val categoryNew = pool.filterTo(ArrayList()) { historyId(it, categoryKey) !in used && it.song.songId !in freshNewIds }
        shuffleInPlace(categoryNew)

        val oldOnes = pool.filterTo(ArrayList()) { historyId(it, categoryKey) in used }
        shuffleInPlace(oldOnes)

        val result = ArrayList<Candidate>()
        val chosenSongs = HashSet<String>()
        outer@ for (tier in listOf(freshNew, categoryNew, oldOnes)) {
            for (candidate in tier) {
                if (!chosenSongs.add(candidate.song.songId)) continue
                result += candidate
                if (result.size == take) break@outer
            }
        }
        for (chosen in result) {
            val id = historyId(chosen, categoryKey)
            used += id
            sessionShownSongs += id
        }
        categorySongHistory[categoryKey] = used
        return result
    }

    private fun mapItem(candidate: Candidate, includeInstrument: Boolean): SuggestionSongItem {
        val score = candidate.score
        val percentileDisplay = score?.let { s ->
            val rank = s.rank
            val total = s.totalEntries
            if (rank != null && total != null) ScoreFormatting.percentileBucket(rank, total) else null
        }
        return SuggestionSongItem(
            song = candidate.song,
            instrument = if (includeInstrument) candidate.instrument else null,
            stars = score?.stars,
            percent = score?.accuracy?.let { it / 10_000 },
            fullCombo = score?.isFullCombo,
            percentileDisplay = percentileDisplay,
        )
    }

    private fun recordRecent(song: Song) {
        recentSongIds.addLast(song.songId)
        while (recentSongIds.size > 40) recentSongIds.removeFirst()
        val artist = canon(song.artist)
        if (artist.isEmpty()) return
        recentArtists.addLast(artist)
        while (recentArtists.size > 12) recentArtists.removeFirst()
    }

    private fun finalizeOne(candidate: Candidate, includeInstrument: Boolean): SuggestionSongItem {
        recordRecent(candidate.song)
        return mapItem(candidate, includeInstrument)
    }

    private fun finalize(candidates: List<Candidate>, includeInstrument: Boolean): List<SuggestionSongItem> =
        candidates.map { finalizeOne(it, includeInstrument) }

    private fun candidatesForSong(song: Song, predicate: (SuggestionScore, Instrument) -> Boolean): List<Candidate> {
        val scores = scoresIndex[song.songId] ?: return emptyList()
        val out = ArrayList<Candidate>()
        for (instrument in Instrument.entries) {
            val score = scores[instrument] ?: continue
            if (predicate(score, instrument)) out += Candidate(song, score, instrument)
        }
        return out
    }

    private fun candidates(predicate: (SuggestionScore, Instrument) -> Boolean): List<Candidate> {
        val out = ArrayList<Candidate>()
        for (song in songs) out += candidatesForSong(song, predicate)
        return out
    }

    private fun candidates(instrument: Instrument, predicate: (SuggestionScore) -> Boolean): List<Candidate> {
        val out = ArrayList<Candidate>()
        for (song in songs) {
            val score = scoresIndex[song.songId]?.get(instrument) ?: continue
            if (predicate(score)) out += Candidate(song, score, instrument)
        }
        return out
    }

    /** Shared shuffle → probability → select → map pipeline for a plain (non-decade) category. */
    private fun emit(
        key: String,
        title: String,
        description: String,
        type: SuggestionCategoryType,
        instrument: Instrument?,
        pool: List<Candidate>,
        includeInstrumentInItems: Boolean,
    ): List<SuggestionCategory> {
        val shuffled = ArrayList(pool)
        shuffleInPlace(shuffled)
        if (!shouldEmit(key, freshCount(shuffled))) return emptyList()
        val selected = selectNewFirst(key, shuffled, displayCount())
        if (selected.isEmpty()) return emptyList()
        return listOf(SuggestionCategory(key, title, description, type, instrument, finalize(selected, includeInstrumentInItems)))
    }

    /** Web `buildDecadeVariant`: one decade with 2+ eligible songs, re-titled for it. */
    private fun buildDecadeVariant(
        baseKey: String,
        baseTitle: String,
        baseDescription: String,
        type: SuggestionCategoryType,
        instrument: Instrument?,
        includeInstrumentInItems: Boolean,
        pool: List<Candidate>,
    ): List<SuggestionCategory> {
        val valid = pool.filter { (it.song.year ?: 0) > 0 }
        if (valid.size < 2) return emptyList()
        val byDecade = HashMap<Int, MutableList<Candidate>>()
        for (candidate in valid) {
            val start = decadeStart(candidate.song.year) ?: continue
            byDecade.getOrPut(start) { mutableListOf() } += candidate
        }
        val groups = byDecade.entries.filter { it.value.size >= 2 }.sortedBy { it.key }.map { it.key to it.value }.toMutableList()
        if (groups.isEmpty()) return emptyList()
        shuffleInPlace(groups)
        val (decade, chosen) = groups[0]
        val label = decadeLabel(decade)
        val variantKey = "${baseKey}_decade_${two(decade % 100)}"
        val selection = selectNewFirst(variantKey, chosen, displayCount())
        if (selection.size < 2) return emptyList()

        if (baseKey == "first_plays_mixed") {
            for (candidate in selection) candidate.instrument?.let { firstPlaysMixedLastInstrument[candidate.song.songId] = it }
        }
        val name = instrument?.label ?: ""
        var title = "$baseTitle ($label)"
        var description = "$baseDescription Limited to $label songs."
        when {
            baseKey == "more_stars" || baseKey == "almost_six_star" -> title = "Push $label to Gold"
            baseKey.startsWith("unfc_") -> title = "Close $name FCs ($label)"
            baseKey == "unplayed_any" -> title = "First Plays ($label)"
            baseKey.startsWith("unplayed_") -> title = "First $name Plays ($label)"
            baseKey == "first_plays_mixed" -> title = "First Plays (Mixed $label)"
            baseKey == "near_fc_relaxed" -> title = "Close to FC (92%+) - $label"
            baseKey == "near_fc_any" -> title = "FC These Next! ($label)"
            baseKey == "star_gains" -> title = "Easy Star Gains ($label)"
            baseKey == "almost_elite" -> {
                title = "Almost Elite ($label)"
                description = "You're in the top 5% on these $label songs — one good run could crack the top 1%."
            }
            baseKey.startsWith("almost_elite_") -> {
                title = "Almost Elite on $name ($label)"
                description = "Your $name scores on these $label songs are in the top 5% — push them into the top 1%."
            }
            baseKey == "pct_push" -> {
                title = "Percentile Push ($label)"
                description = "These $label scores are close to the next percentile bracket — replay them to climb."
            }
            baseKey.startsWith("pct_push_") -> {
                title = "Percentile Push: $name ($label)"
                description = "Replay these $label $name songs to jump to the next percentile bracket."
            }
        }
        if (baseKey == "unplayed_any") {
            description = "Unplayed songs from the $label."
        } else if (baseKey.startsWith("unplayed_")) {
            description = "Unplayed $name songs from the $label."
        }
        return listOf(SuggestionCategory(variantKey, title, description, type, instrument, finalize(selection, includeInstrumentInItems)))
    }

    /** Shared decade wrapper: one emit roll on the undecaded pool, then [buildDecadeVariant]. */
    private fun decade(
        baseKey: String,
        baseTitle: String,
        baseDescription: String,
        type: SuggestionCategoryType,
        instrument: Instrument?,
        includeInstrumentInItems: Boolean,
        pool: List<Candidate>,
    ): List<SuggestionCategory> {
        if (!shouldEmit("${baseKey}_decade_wrap", freshCount(pool))) return emptyList()
        return buildDecadeVariant(baseKey, baseTitle, baseDescription, type, instrument, includeInstrumentInItems, pool)
    }

    // endregion

    // region Near FC

    private fun nearFcAnyPool() = candidates { s, _ -> (s.stars ?: 0) == 6 && s.isFullCombo != true && (s.accuracy ?: 0.0) >= 950_000 }

    private fun nearFcRelaxedPool() = candidates { s, _ -> (s.stars ?: 0) >= 5 && (s.accuracy ?: 0.0) >= 920_000 && s.isFullCombo != true }

    private fun fcTheseNext() = emit(
        "near_fc_any", "FC These Next!", "If you can get gold stars, you can FC it!",
        SuggestionCategoryType.NearFC, null, nearFcAnyPool(), true,
    )

    private fun fcTheseNextDecade() = decade(
        "near_fc_any", "FC These Next!", "If you can get gold stars, you can FC it!",
        SuggestionCategoryType.NearFC, null, true, nearFcAnyPool(),
    )

    private fun nearFcRelaxed() = emit(
        "near_fc_relaxed", "Close to FC (92%+)", "Great runs to try and FC next!",
        SuggestionCategoryType.NearFC, null, nearFcRelaxedPool(), true,
    )

    private fun nearFcRelaxedDecade() = decade(
        "near_fc_relaxed", "Close to FC (92%+)", "Great runs to try and FC next!",
        SuggestionCategoryType.NearFC, null, true, nearFcRelaxedPool(),
    )

    private fun unFcPool(instrument: Instrument) = candidates(instrument) { (it.stars ?: 0) == 6 && it.isFullCombo != true }

    private fun unFcInstrument(instrument: Instrument) = emit(
        "unfc_${instrument.wireId}", "Finish the ${instrument.label} FCs",
        "Play these songs again on ${instrument.label} and grab an FC!",
        SuggestionCategoryType.NearFC, instrument, unFcPool(instrument), false,
    )

    private fun unFcInstrumentDecade(instrument: Instrument) = decade(
        "unfc_${instrument.wireId}", "Finish the ${instrument.label} FCs",
        "Play these songs again on ${instrument.label} and grab an FC!",
        SuggestionCategoryType.NearFC, instrument, false, unFcPool(instrument),
    )

    private fun sameNameNearFc(): List<SuggestionCategory> {
        val buckets = HashMap<String, MutableList<Song>>()
        for (song in songs) {
            if (scoresIndex[song.songId] != null) buckets.getOrPut(canon(song.title)) { mutableListOf() } += song
        }
        val groups = buckets.entries.filter { it.value.size >= 2 }.sortedBy { it.key }.map { it.value }.toMutableList()
        if (groups.isEmpty()) return emptyList()
        shuffleInPlace(groups)
        val pickedGroup = groups[0]
        val displayTitle = trimSpaces(pickedGroup.first().title)
        val poolAll = ArrayList<Candidate>()
        for (song in pickedGroup) {
            poolAll += candidatesForSong(song) { s, _ -> (s.stars ?: 0) == 6 && s.isFullCombo != true && (s.accuracy ?: 0.0) >= 900_000 }
        }
        shuffleInPlace(poolAll)
        val final = selectNewFirst("samename_nearfc", poolAll.take(30), displayCount())
        if (final.isEmpty()) return emptyList()
        return listOf(
            SuggestionCategory(
                "samename_nearfc_$displayTitle", "Close to FC: '$displayTitle' Variants",
                "FC these same-name songs for a unique achievement!", SuggestionCategoryType.NearFC, null,
                finalize(final, true),
            ),
        )
    }

    // endregion

    // region Star progress

    private fun almostSixPool() = candidates { s, _ -> (s.stars ?: 0) == 5 && (s.accuracy ?: 0.0) >= 900_000 }

    private fun starGainsPool() = candidates { s, _ -> (s.stars ?: 0) in 3..5 }

    private fun moreStarsPool() = candidates { s, _ -> (s.stars ?: 0) in 1..5 }

    private fun almostSixStars() = emit(
        "almost_six_star", "Push to Gold Stars", "Push these five-star runs to gold stars!",
        SuggestionCategoryType.StarProgress, null, almostSixPool(), true,
    )

    private fun almostSixStarsDecade() = decade(
        "almost_six_star", "Push to Gold Stars", "Push these five-star runs to gold stars!",
        SuggestionCategoryType.StarProgress, null, true, almostSixPool(),
    )

    private fun starGains() = emit(
        "star_gains", "Easy Star Gains", "Hit a new high score to get even more stars on these songs!",
        SuggestionCategoryType.StarProgress, null, starGainsPool(), true,
    )

    private fun starGainsDecade() = decade(
        "star_gains", "Easy Star Gains", "Hit a new high score to get even more stars on these songs!",
        SuggestionCategoryType.StarProgress, null, true, starGainsPool(),
    )

    private fun getMoreStars() = emit(
        "more_stars", "Push These to Gold Stars", "Try gold-starring this selection of tracks!",
        SuggestionCategoryType.StarProgress, null, moreStarsPool(), true,
    )

    private fun getMoreStarsDecade() = decade(
        "more_stars", "Push These to Gold Stars", "Try gold-starring this selection of tracks!",
        SuggestionCategoryType.StarProgress, null, true, moreStarsPool(),
    )

    // endregion

    // region Unplayed

    private fun unplayedInstruments(song: Song): List<Instrument> {
        val scores = scoresIndex[song.songId]
        return Instrument.entries.filter { instrument ->
            if (!song.supports(instrument)) return@filter false
            val score = scores?.get(instrument) ?: return@filter true
            (score.stars ?: 0) == 0
        }
    }

    private fun firstPlaysMixedPool(): MutableList<Candidate> {
        val pool = ArrayList<Candidate>()
        for (song in songs) {
            val unplayed = unplayedInstruments(song)
            if (unplayed.isEmpty()) continue
            val last = firstPlaysMixedLastInstrument[song.songId]
            val eligible = if (last != null && unplayed.size > 1) unplayed.filter { it != last } else unplayed
            for (instrument in eligible) pool += Candidate(song, null, instrument)
        }
        return pool
    }

    private fun firstPlaysMixed(): List<SuggestionCategory> {
        val pool = firstPlaysMixedPool()
        if (pool.isEmpty()) return emptyList()
        shuffleInPlace(pool)
        val final = selectNewFirst("first_plays_mixed", pool, displayCount())
        for (candidate in final) candidate.instrument?.let { firstPlaysMixedLastInstrument[candidate.song.songId] = it }
        if (final.isEmpty()) return emptyList()
        return listOf(
            SuggestionCategory(
                "first_plays_mixed", "First Plays (Mixed)", "Unplayed picks across instruments.",
                SuggestionCategoryType.Unplayed, null, finalize(final, true),
            ),
        )
    }

    private fun firstPlaysMixedDecade() = decade(
        "first_plays_mixed", "First Plays (Mixed)", "Unplayed picks across instruments.",
        SuggestionCategoryType.Unplayed, null, true, firstPlaysMixedPool(),
    )

    private fun unplayedAll(): List<SuggestionCategory> {
        val list = songs.filterTo(ArrayList()) { scoresIndex[it.songId] == null }
        shuffleInPlace(list)
        val pool = list.map { Candidate(it, null, null) }
        if (!shouldEmit("unplayed_any", freshCount(pool))) return emptyList()
        val final = selectNewFirst("unplayed_any", pool, displayCount())
        if (final.isEmpty()) return emptyList()
        return listOf(
            SuggestionCategory(
                "unplayed_any", "Try Something New", "Songs you haven't played on any instrument yet.",
                SuggestionCategoryType.Unplayed, null, finalize(final, false),
            ),
        )
    }

    private fun unplayedAllDecade() = decade(
        "unplayed_any", "Try Something New", "Songs you haven't played on any instrument yet.",
        SuggestionCategoryType.Unplayed, null, false,
        songs.filter { scoresIndex[it.songId] == null }.map { Candidate(it, null, null) },
    )

    private fun unplayedOn(instrument: Instrument): MutableList<Song> = songs.filterTo(ArrayList()) { song ->
        if (!song.supports(instrument)) return@filterTo false
        val score = scoresIndex[song.songId]?.get(instrument) ?: return@filterTo true
        (score.stars ?: 0) == 0
    }

    private fun unplayedInstrument(instrument: Instrument): List<SuggestionCategory> {
        val list = unplayedOn(instrument)
        shuffleInPlace(list)
        val pool = list.map { Candidate(it, null, null) }
        val key = "unplayed_${instrument.wireId}"
        if (!shouldEmit(key, freshCount(pool))) return emptyList()
        val final = selectNewFirst(key, pool, displayCount())
        if (final.isEmpty()) return emptyList()
        return listOf(
            SuggestionCategory(
                key, "New on ${instrument.label}", "Songs you haven't played on ${instrument.label} yet.",
                SuggestionCategoryType.Unplayed, instrument, finalize(final, false),
            ),
        )
    }

    private fun unplayedInstrumentDecade(instrument: Instrument) = decade(
        "unplayed_${instrument.wireId}", "New on ${instrument.label}", "Songs you haven't played on ${instrument.label} yet.",
        SuggestionCategoryType.Unplayed, instrument, false, unplayedOn(instrument).map { Candidate(it, null, null) },
    )

    // endregion

    // region Variety, artists, same name

    /** Lead score, else Drums (web `mapUniqueSong` for variety/artist rows). */
    private fun leadOrDrums(song: Song): SuggestionScore? {
        val scores = scoresIndex[song.songId]
        return scores?.get(Instrument.Lead) ?: scores?.get(Instrument.Drums)
    }

    private fun varietyPack(): List<SuggestionCategory> {
        val sorted = songs.sortedWith(compareBy<Song> { canon(it.artist) }.thenBy { it.songId }).toMutableList()
        shuffleInPlace(sorted)
        val usedArtists = HashSet<String>()
        val picks = ArrayList<Song>()
        for (song in sorted) {
            val key = canon(song.artist)
            if (key in usedArtists || song.songId in recentSongIds || song.songId in sessionShownSongs) continue
            usedArtists += key
            picks += song
            if (picks.size == 5) break
        }
        val freshPicks = picks.count { it.songId !in sessionShownSongs }
        if (!shouldEmit("variety_pack", freshPicks)) return emptyList()
        shuffleInPlace(picks)
        val pool = picks.map { Candidate(it, leadOrDrums(it), null) }
        val display = finalize(selectNewFirst("variety_pack", pool, displayCount()), false)
        if (display.size < 2) return emptyList()
        val description = when (display.size) {
            2 -> "Two different artists for variety."
            3 -> "Three different artists for variety."
            4 -> "Four different artists for variety."
            else -> "Five different artists for variety."
        }
        return listOf(SuggestionCategory("variety_pack", "Variety Pack", description, SuggestionCategoryType.VarietyPack, null, display))
    }

    private fun artistSamplerRotating(): List<SuggestionCategory> {
        val groups = HashMap<String, MutableList<Song>>()
        for (song in songs) groups.getOrPut(canon(song.artist)) { mutableListOf() } += song
        val eligible = groups.entries.filter { it.value.size >= 3 }.sortedBy { it.key }.map { it.key to it.value }.toMutableList()
        if (eligible.isEmpty()) return emptyList()
        shuffleInPlace(eligible)
        val (chosenKey, chosenSongs) = eligible[0]
        val artist = canon(chosenKey)
        if (artist.isEmpty()) return emptyList()
        recentArtists.addLast(artist)
        while (recentArtists.size > 12) recentArtists.removeFirst()

        var picked = chosenSongs.sortedBy { it.songId }.take(10).toMutableList()
        shuffleInPlace(picked)
        if (picked.size > 5) picked = picked.take(displayCount()).toMutableList()

        var artistName = picked.firstOrNull()?.artist ?: chosenKey
        if (trimSpaces(artistName).length <= 1) artistName = "Featured Artist"
        if (picked.isEmpty() || artistName == "Featured Artist") return emptyList()
        val items = picked.map { finalizeOne(Candidate(it, leadOrDrums(it), null), false) }
        return listOf(
            SuggestionCategory(
                "artist_sampler_$artistName", "$artistName Essentials", "A selection of songs by $artistName.",
                SuggestionCategoryType.ArtistEssentials, null, items,
            ),
        )
    }

    private fun artistFocusUnplayed(): List<SuggestionCategory> {
        val unplayed = songs.filter { scoresIndex[it.songId] == null }
        if (unplayed.isEmpty()) return emptyList()
        val groups = HashMap<String, MutableList<Song>>()
        for (song in unplayed) groups.getOrPut(canon(song.artist)) { mutableListOf() } += song
        val entries = groups.entries.sortedBy { it.key }.map { it.key to it.value }.toMutableList()
        shuffleInPlace(entries)
        val (artistKey, groupSongs) = entries.first()
        val displayName = groupSongs.first().artist
        val key = "artist_unplayed_$artistKey"
        val picked = selectNewFirst(key, groupSongs.map { Candidate(it, null, null) }, displayCount())
        if (picked.isEmpty()) return emptyList()
        return listOf(
            SuggestionCategory(
                key, "Discover $displayName", "Unplayed songs from $displayName.",
                SuggestionCategoryType.ArtistDiscover, null, finalize(picked, false),
            ),
        )
    }

    private fun sameNameSets(): List<SuggestionCategory> {
        val groups = HashMap<String, MutableList<Song>>()
        for (song in songs) groups.getOrPut(canon(song.title)) { mutableListOf() } += song
        val duplicates = groups.entries.filter { it.value.size >= 2 }.sortedBy { it.key }.map { it.value }.toMutableList()
        if (duplicates.isEmpty()) return emptyList()
        shuffleInPlace(duplicates)
        val selected = selectNewFirst("samename", duplicates[0].map { Candidate(it, null, null) }, displayCount())
        if (selected.isEmpty()) return emptyList()
        val displayTitle = trimSpaces(selected[0].song.title)
        return listOf(
            SuggestionCategory(
                "samename_$displayTitle", "Songs Named '$displayTitle'", "Different tracks sharing the same title.",
                SuggestionCategoryType.SameName, null, finalize(selected, false),
            ),
        )
    }

    // endregion

    // region Almost elite / percentile push

    private fun isAlmostElite(score: SuggestionScore): Boolean {
        val bucket = rawPercentile(score)?.let(::percentileBucket) ?: return false
        return bucket in 2..5
    }

    private fun isNearNext(score: SuggestionScore): Boolean = rawPercentile(score)?.let(::isNearNextBracket) ?: false

    private fun almostElite() = emit(
        "almost_elite", "Almost Elite", "You're in the top 5% on these — one good run could crack the top 1%.",
        SuggestionCategoryType.AlmostElite, null, candidates { s, _ -> isAlmostElite(s) }, true,
    )

    private fun almostEliteDecade() = decade(
        "almost_elite", "Almost Elite", "You're in the top 5% on these — one good run could crack the top 1%.",
        SuggestionCategoryType.AlmostElite, null, true, candidates { s, _ -> isAlmostElite(s) },
    )

    private fun almostEliteInstrument(instrument: Instrument) = emit(
        "almost_elite_${instrument.wireId}", "Almost Elite on ${instrument.label}",
        "Your ${instrument.label} scores are in the top 5% — push them into the top 1%.",
        SuggestionCategoryType.AlmostElite, instrument, candidates(instrument, ::isAlmostElite), false,
    )

    private fun almostEliteInstrumentDecade(instrument: Instrument) = decade(
        "almost_elite_${instrument.wireId}", "Almost Elite on ${instrument.label}",
        "Your ${instrument.label} scores are in the top 5% — push them into the top 1%.",
        SuggestionCategoryType.AlmostElite, instrument, false, candidates(instrument, ::isAlmostElite),
    )

    private fun percentilePush() = emit(
        "pct_push", "Percentile Push", "These scores are close to the next percentile bracket — replay them to climb.",
        SuggestionCategoryType.PercentilePush, null, candidates { s, _ -> isNearNext(s) }, true,
    )

    private fun percentilePushDecade() = decade(
        "pct_push", "Percentile Push", "These scores are close to the next percentile bracket — replay them to climb.",
        SuggestionCategoryType.PercentilePush, null, true, candidates { s, _ -> isNearNext(s) },
    )

    private fun percentilePushInstrument(instrument: Instrument) = emit(
        "pct_push_${instrument.wireId}", "Percentile Push: ${instrument.label}",
        "Replay these ${instrument.label} songs to jump to the next percentile bracket.",
        SuggestionCategoryType.PercentilePush, instrument, candidates(instrument, ::isNearNext), false,
    )

    private fun percentilePushInstrumentDecade(instrument: Instrument) = decade(
        "pct_push_${instrument.wireId}", "Percentile Push: ${instrument.label}",
        "Replay these ${instrument.label} songs to jump to the next percentile bracket.",
        SuggestionCategoryType.PercentilePush, instrument, false, candidates(instrument, ::isNearNext),
    )

    // endregion

    // region Stale songs

    private fun staleMatches(ago: Int, minSeasonsAgo: Int) = if (minSeasonsAgo >= 5) ago >= 5 else ago >= minSeasonsAgo

    private fun staleGlobal(minSeasonsAgo: Int): List<SuggestionCategory> {
        if (currentSeason <= 0) return emptyList()
        val pool = ArrayList<Candidate>()
        for (song in songs) {
            val latest = latestSeason(song.songId)
            if (latest <= 0) continue
            if (staleMatches(currentSeason - latest, minSeasonsAgo)) pool += Candidate(song, null, null)
        }
        shuffleInPlace(pool)
        val key = "stale_global_${if (minSeasonsAgo >= 5) "5plus" else "$minSeasonsAgo"}"
        if (!shouldEmit(key, freshCount(pool))) return emptyList()
        val final = selectNewFirst(key, pool, displayCount())
        if (final.isEmpty()) return emptyList()
        val title = when {
            minSeasonsAgo == 1 -> "Play This Season"
            minSeasonsAgo >= 5 -> "Untouched for 5+ Seasons"
            else -> "Untouched for $minSeasonsAgo Seasons"
        }
        val description = when {
            minSeasonsAgo == 1 -> "Songs you haven't played on any instrument this season."
            minSeasonsAgo >= 5 -> "Songs you haven't played on any instrument in 5 or more seasons."
            else -> "Songs you haven't played on any instrument in at least $minSeasonsAgo seasons."
        }
        return listOf(SuggestionCategory(key, title, description, SuggestionCategoryType.Stale, null, finalize(final, false)))
    }

    private fun staleInstrument(instrument: Instrument, minSeasonsAgo: Int): List<SuggestionCategory> {
        if (currentSeason <= 0) return emptyList()
        val pool = ArrayList<Candidate>()
        for (song in songs) {
            val season = instrumentSeason(song.songId, instrument)
            if (season <= 0) continue
            if (staleMatches(currentSeason - season, minSeasonsAgo)) {
                pool += Candidate(song, scoresIndex[song.songId]?.get(instrument), instrument)
            }
        }
        shuffleInPlace(pool)
        val key = "stale_${instrument.wireId}_${if (minSeasonsAgo >= 5) "5plus" else "$minSeasonsAgo"}"
        if (!shouldEmit(key, freshCount(pool))) return emptyList()
        val final = selectNewFirst(key, pool, displayCount())
        if (final.isEmpty()) return emptyList()
        val name = instrument.label
        val title = when {
            minSeasonsAgo == 1 -> "Play $name This Season"
            minSeasonsAgo >= 5 -> "$name Untouched for 5+ Seasons"
            else -> "$name Untouched for $minSeasonsAgo Seasons"
        }
        val description = when {
            minSeasonsAgo == 1 -> "Songs you haven't played on $name this season."
            minSeasonsAgo >= 5 -> "Songs you haven't played on $name in 5 or more seasons."
            else -> "Songs you haven't played on $name in at least $minSeasonsAgo seasons."
        }
        return listOf(SuggestionCategory(key, title, description, SuggestionCategoryType.Stale, instrument, finalize(final, true)))
    }

    // endregion

    // region Percentile improvement

    /** Every chart's bucket on one song, for charts with a valid rank. */
    private fun songBuckets(scores: Map<Instrument, SuggestionScore>): List<Int> = Instrument.entries.mapNotNull { instrument ->
        val raw = scores[instrument]?.let(::rawPercentile) ?: return@mapNotNull null
        if (raw > 0) percentileBucket(raw) else null
    }

    private fun samePercentileBucket(): List<SuggestionCategory> {
        val pool = ArrayList<Candidate>()
        val songBucket = HashMap<String, Int>()
        for (song in songs) {
            val scores = scoresIndex[song.songId] ?: continue
            val buckets = songBuckets(scores)
            val first = buckets.firstOrNull()
            if (buckets.size >= 2 && first != null && buckets.all { it == first } && first > 1) {
                pool += Candidate(song, null, null)
                songBucket[song.songId] = first
            }
        }
        shuffleInPlace(pool)
        val key = "same_pct_improve"
        if (!shouldEmit(key, freshCount(pool))) return emptyList()
        val final = selectNewFirst(key, pool, displayCount())
        if (final.isEmpty()) return emptyList()
        val items = final.map { candidate ->
            val item = finalizeOne(candidate, false)
            songBucket[candidate.song.songId]?.let { item.copy(percentileDisplay = "Top $it%") } ?: item
        }
        return listOf(
            SuggestionCategory(
                key, "Competitive Improvements",
                "Songs where your percentile is the same across all instruments. An improvement on any instrument moves you up everywhere.",
                SuggestionCategoryType.PctImprove, null, items,
            ),
        )
    }

    private fun samePercentileBucketSpecific(bucket: Int): List<SuggestionCategory> {
        val pool = ArrayList<Candidate>()
        for (song in songs) {
            val scores = scoresIndex[song.songId] ?: continue
            val buckets = songBuckets(scores)
            if (buckets.size >= 2 && buckets.all { it == bucket }) pool += Candidate(song, null, null)
        }
        shuffleInPlace(pool)
        val key = "same_pct_$bucket"
        if (!shouldEmit(key, freshCount(pool))) return emptyList()
        val final = selectNewFirst(key, pool, displayCount())
        if (final.isEmpty()) return emptyList()
        val target = nextLowerThreshold(bucket)?.let { "Top $it%" } ?: "a higher bracket"
        val items = final.map { finalizeOne(it, false).copy(percentileDisplay = "Top $bucket%") }
        return listOf(
            SuggestionCategory(
                key, "Break Into $target",
                "Songs where all your instruments are ranked Top $bucket%. Improve any instrument to break the tie and climb to $target.",
                SuggestionCategoryType.PctImprove, null, items,
            ),
        )
    }

    private fun inBucket(score: SuggestionScore, bucket: Int): Boolean = rawPercentile(score)?.let(::percentileBucket) == bucket

    private fun percentileImproveBucket(bucket: Int): List<SuggestionCategory> {
        if (bucket <= 1) return emptyList()
        return emit(
            "pct_improve_$bucket", "Top $bucket% Push",
            "Songs with at least one instrument ranked Top $bucket%. A small score bump could push you higher.",
            SuggestionCategoryType.PctImprove, null, candidates { s, _ -> inBucket(s, bucket) }, true,
        )
    }

    private fun percentileImproveInstrument(instrument: Instrument, bucket: Int): List<SuggestionCategory> {
        if (bucket <= 1) return emptyList()
        return emit(
            "pct_improve_${instrument.wireId}_$bucket", "Top $bucket% Push",
            "Songs with ${instrument.label} scores ranked Top $bucket%. A small score bump could push you higher.",
            SuggestionCategoryType.PctImprove, instrument, candidates(instrument) { inBucket(it, bucket) }, false,
        )
    }

    private fun improveInstrumentRankings(instrument: Instrument): List<SuggestionCategory> {
        val byBucket = HashMap<Int, MutableList<Candidate>>()
        for (song in songs) {
            val score = scoresIndex[song.songId]?.get(instrument) ?: continue
            val raw = rawPercentile(score) ?: continue
            if (raw <= 0) continue
            val bucket = percentileBucket(raw) ?: continue
            if (bucket <= 1) continue
            byBucket.getOrPut(bucket) { mutableListOf() } += Candidate(song, score, instrument)
        }
        if (byBucket.size < 3) return emptyList()
        val picks = ArrayList<Candidate>()
        for (bucket in byBucket.keys.sorted()) {
            val group = byBucket.getValue(bucket)
            shuffleInPlace(group)
            group.firstOrNull()?.let { picks += it }
        }
        shuffleInPlace(picks)
        val key = "improve_rankings_${instrument.wireId}"
        if (!shouldEmit(key, freshCount(picks))) return emptyList()
        val take = min(displayCount(), picks.size)
        val final = selectNewFirst(key, picks, take)
        if (final.size < 3) return emptyList()
        return listOf(
            SuggestionCategory(
                key, "Improve ${instrument.label} Rankings",
                "A varied mix of ${instrument.label} songs across different percentile brackets — all with room to grow.",
                SuggestionCategoryType.PctImprove, instrument, finalize(final, false),
            ),
        )
    }

    // endregion

    // region Near max score

    /** One exclusive CHOpt-max gap tier `(minGap, maxGap]`. */
    private data class NearMaxTier(val minGap: Int, val maxGap: Int, val label: String, val title: String, val description: String)

    private fun nearMaxCandidates(tier: NearMaxTier): List<Candidate> {
        val out = ArrayList<Candidate>()
        for (song in songs) {
            if (song.maxScores == null) continue
            val scores = scoresIndex[song.songId] ?: continue
            for (instrument in Instrument.entries) {
                val score = scores[instrument] ?: continue
                if (score.score <= 0) continue
                val choptMax = song.maxScore(instrument) ?: continue
                val gap = choptMax - score.score
                if (gap > tier.minGap && gap <= tier.maxGap) out += Candidate(song, score, instrument)
            }
        }
        return out
    }

    private fun nearMaxScore(tier: NearMaxTier) = emit(
        "near_max_${tier.label}", tier.title, tier.description, SuggestionCategoryType.NearMax, null, nearMaxCandidates(tier), true,
    )

    private fun nearMaxScoreDecade(tier: NearMaxTier) = decade(
        "near_max_${tier.label}", tier.title, tier.description, SuggestionCategoryType.NearMax, null, true, nearMaxCandidates(tier),
    )

    // endregion

    // region Rival strategies

    private fun matchKey(candidate: Candidate): String? = candidate.instrument?.let { RivalDataIndex.closestKey(candidate.song.songId, it) }

    /** Last match per song/chart key (the web re-`find`s after selection reorders the pool). */
    private fun matchLookup(matches: List<RivalSongMatch>): Map<String, RivalSongMatch> {
        val out = HashMap<String, RivalSongMatch>()
        for (match in matches) out[RivalDataIndex.closestKey(match.songId, match.instrument)] = match
        return out
    }

    private fun Map<String, RivalSongMatch>.delta(candidate: Candidate): Int? = this[matchKey(candidate) ?: ""]?.rankDelta

    /** Web `mapRivalSong`: a rival-keyed category's own row, always instrument-included. */
    private fun mapRivalItem(candidate: Candidate, rival: RivalInfo, rankDelta: Int): SuggestionSongItem =
        finalizeOne(candidate, true).copy(rivalName = rival.displayName, rivalAccountId = rival.accountId, rivalRankDelta = rankDelta)

    private fun closestMatch(candidate: Candidate): RivalSongMatch? {
        val instrument = candidate.instrument ?: return null
        return rivalData?.closestRivalBySong?.get(RivalDataIndex.closestKey(candidate.song.songId, instrument))
    }

    /** Web `annotateWithRival`: attach the closest rival, if any. */
    private fun mapWithClosestRival(candidate: Candidate): SuggestionSongItem {
        val item = finalizeOne(candidate, true)
        val match = closestMatch(candidate) ?: return item
        return item.copy(rivalName = match.rival.displayName, rivalAccountId = match.rival.accountId, rivalRankDelta = match.rankDelta)
    }

    private fun closestRivalName(candidate: Candidate): String = closestMatch(candidate)?.rival?.displayName ?: "a rival"

    private fun rivalPool(matches: List<RivalSongMatch>, keep: (RivalSongMatch) -> Boolean): MutableList<Candidate> {
        val pool = ArrayList<Candidate>()
        for (match in matches) {
            if (!keep(match)) continue
            val song = songsById[match.songId] ?: continue
            pool += Candidate(song, scoresIndex[match.songId]?.get(match.instrument), match.instrument)
        }
        return pool
    }

    /** Shared tail of the per-rival families: emit roll, selection, rival-annotated rows. */
    private fun rivalCategory(
        key: String,
        title: String,
        description: String,
        pool: List<Candidate>,
        rival: RivalInfo,
        lookup: Map<String, RivalSongMatch>,
    ): List<SuggestionCategory> {
        if (!shouldEmit(key, freshCount(pool))) return emptyList()
        val final = selectNewFirst(key, pool, displayCount())
        if (final.isEmpty()) return emptyList()
        return listOf(
            SuggestionCategory(
                key, title, description, SuggestionCategoryType.SongRivals, null,
                final.map { mapRivalItem(it, rival, lookup.delta(it) ?: 0) },
            ),
        )
    }

    private fun songRivalGap(rivalId: String): List<SuggestionCategory> {
        val matches = rivalData?.byRival?.get(rivalId)?.takeIf { it.isNotEmpty() } ?: return emptyList()
        val rival = matches[0].rival
        val lookup = matchLookup(matches)
        val pool = rivalPool(matches) { it.rankDelta < 0 }
        if (pool.isEmpty()) return emptyList()
        val sorted = pool.sortedBy { abs(lookup.delta(it) ?: 999) }
        return rivalCategory(
            "song_rival_gap_$rivalId", "Close the Gap vs ${rival.displayName}",
            "Songs where ${rival.displayName} barely leads you. One good run could overtake them.", sorted, rival, lookup,
        )
    }

    private fun songRivalProtect(rivalId: String): List<SuggestionCategory> {
        val matches = rivalData?.byRival?.get(rivalId)?.takeIf { it.isNotEmpty() } ?: return emptyList()
        val rival = matches[0].rival
        val lookup = matchLookup(matches)
        val pool = rivalPool(matches) { it.rankDelta > 0 }
        if (pool.isEmpty()) return emptyList()
        val sorted = pool.sortedBy { lookup.delta(it) ?: 999 }
        return rivalCategory(
            "song_rival_protect_$rivalId", "Protect Your Lead vs ${rival.displayName}",
            "You're barely ahead of ${rival.displayName} on these. Don't let them pass you.", sorted, rival, lookup,
        )
    }

    /** 2+ rivals within 10 ranks of the player on one song/chart; keys iterated in sorted order. */
    private fun songRivalBattleground(): List<SuggestionCategory> {
        val data = rivalData ?: return emptyList()
        val counts = HashMap<String, Int>()
        for (matches in data.byRival.values) {
            for (match in matches) {
                if (abs(match.rankDelta) <= 10) {
                    val key = RivalDataIndex.closestKey(match.songId, match.instrument)
                    counts[key] = (counts[key] ?: 0) + 1
                }
            }
        }
        val pool = ArrayList<Candidate>()
        for (key in counts.keys.sorted()) {
            if ((counts[key] ?: 0) < 2) continue
            val separator = key.lastIndexOf(':')
            if (separator < 0) continue
            val songId = key.substring(0, separator)
            val instrument = Instrument.fromWireId(key.substring(separator + 1)) ?: continue
            val song = songsById[songId] ?: continue
            pool += Candidate(song, scoresIndex[songId]?.get(instrument), instrument)
        }
        if (pool.isEmpty()) return emptyList()
        shuffleInPlace(pool)
        val key = "song_rival_battleground"
        if (!shouldEmit(key, freshCount(pool))) return emptyList()
        val final = selectNewFirst(key, pool, displayCount())
        if (final.isEmpty()) return emptyList()
        return listOf(
            SuggestionCategory(
                key, "Battleground Songs",
                "Multiple rivals are clustered around your rank on these songs. Every position matters.",
                SuggestionCategoryType.SongRivals, null, final.map(::mapWithClosestRival),
            ),
        )
    }

    /** Curated per-rival mix; gated only on "already emitted" (no emit roll), like the web. */
    private fun songRivalSpotlight(rivalId: String): List<SuggestionCategory> {
        val matches = rivalData?.byRival?.get(rivalId)?.takeIf { it.size >= 3 } ?: return emptyList()
        val rival = matches[0].rival
        val behind = matches.filter { it.rankDelta < 0 }.sortedBy { abs(it.rankDelta) }
        val ahead = matches.filter { it.rankDelta > 0 }.sortedBy { it.rankDelta }
        val closest = matches.sortedBy { abs(it.rankDelta) }
        val picks = ArrayList<RivalSongMatch>()
        picks += behind.take(2)
        picks += ahead.take(2)
        closest.firstOrNull { candidate -> picks.none { it.songId == candidate.songId } }?.let { picks += it }

        val pool = rivalPool(picks) { true }
        if (pool.size < 3) return emptyList()
        val key = "song_rival_spotlight_$rivalId"
        if (key in emitted) return emptyList()
        val lookup = matchLookup(matches)
        return listOf(
            SuggestionCategory(
                key, "Rival Spotlight: ${rival.displayName}",
                "A curated mix of your rivalry with ${rival.displayName} — catches, defenses, and closest battles.",
                SuggestionCategoryType.SongRivals, null, pool.map { mapRivalItem(it, rival, lookup.delta(it) ?: 0) },
            ),
        )
    }

    private fun songRivalSlipping(rivalId: String): List<SuggestionCategory> {
        val matches = rivalData?.byRival?.get(rivalId)?.takeIf { it.isNotEmpty() } ?: return emptyList()
        val rival = matches[0].rival
        val lookup = matchLookup(matches)
        val pool = rivalPool(matches) { it.rankDelta < -20 }
        if (pool.isEmpty()) return emptyList()
        shuffleInPlace(pool)
        return rivalCategory(
            "song_rival_slipping_$rivalId", "${rival.displayName} is Pulling Ahead",
            "${rival.displayName} has a big lead on these songs. Time to close the gap.", pool, rival, lookup,
        )
    }

    private fun songRivalDominate(rivalId: String): List<SuggestionCategory> {
        val matches = rivalData?.byRival?.get(rivalId)?.takeIf { it.isNotEmpty() } ?: return emptyList()
        val rival = matches[0].rival
        val lookup = matchLookup(matches)
        val pool = rivalPool(matches) { it.rankDelta > 30 }
        if (pool.isEmpty()) return emptyList()
        shuffleInPlace(pool)
        return rivalCategory(
            "song_rival_dominate_$rivalId", "Dominate ${rival.displayName}",
            "You're crushing ${rival.displayName} on these. Keep up the dominance.", pool, rival, lookup,
        )
    }

    /** Shared tail of the four cross-pollination families (closest-rival annotation). */
    private fun crossPollinated(
        key: String,
        pool: MutableList<Candidate>,
        title: (String) -> String,
        description: String,
    ): List<SuggestionCategory> {
        if (pool.isEmpty()) return emptyList()
        shuffleInPlace(pool)
        if (!shouldEmit(key, freshCount(pool))) return emptyList()
        val final = selectNewFirst(key, pool, displayCount())
        if (final.isEmpty()) return emptyList()
        return listOf(
            SuggestionCategory(
                key, title(closestRivalName(final[0])), description, SuggestionCategoryType.SongRivals, null,
                final.map(::mapWithClosestRival),
            ),
        )
    }

    private fun songRivalNearFc(): List<SuggestionCategory> {
        if (rivalData == null) return emptyList()
        val pool = nearFcRelaxedPool().filterTo(ArrayList()) { closestMatch(it) != null }
        return crossPollinated(
            "song_rival_near_fc", pool, { "FC These to Beat $it!" },
            "Almost FC songs where your rival also competes. Nail the combo to pull ahead.",
        )
    }

    private fun songRivalStale(): List<SuggestionCategory> {
        if (rivalData == null || currentSeason == 0) return emptyList()
        val stale = candidates { s, _ ->
            val season = s.season
            season != null && season != 0 && currentSeason - season >= 2
        }
        val pool = stale.filterTo(ArrayList()) { (closestMatch(it)?.rankDelta ?: 0) < 0 }
        return crossPollinated(
            "song_rival_stale", pool, { "Stale Songs Your Rivals Are Beating You On" },
            "Songs you haven't touched in a while where rivals have pulled ahead.",
        )
    }

    private fun songRivalStarGains(): List<SuggestionCategory> {
        if (rivalData == null) return emptyList()
        val pool = starGainsPool().filterTo(ArrayList()) { (closestMatch(it)?.rankDelta ?: 0) < 0 }
        return crossPollinated(
            "song_rival_star_gains", pool, { "Gain Stars & Beat $it" },
            "Improving your star count on these would also overtake a rival.",
        )
    }

    private fun songRivalPctPush(): List<SuggestionCategory> {
        if (rivalData == null) return emptyList()
        val eligible = candidates { s, _ -> (rawPercentile(s)?.let(::percentileBucket) ?: 0) > 1 }
        val pool = eligible.filterTo(ArrayList()) { (closestMatch(it)?.rankDelta ?: 0) < 0 }
        return crossPollinated(
            "song_rival_pct_push", pool, { "Climb Past $it" },
            "A percentile push on these would also move you past a rival.",
        )
    }

    // endregion

    internal companion object {
        private val PERCENTILE_THRESHOLDS = listOf(1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100)
        private val PERCENTILE_BUCKETS = listOf(2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50)

        /** Candidate-count → emit probability (first row whose minimum is met). */
        private val EMIT_TABLE = listOf(
            80 to 1.0, 50 to 0.98, 35 to 0.95, 25 to 0.9, 18 to 0.85, 12 to 0.75, 8 to 0.62, 5 to 0.5, 0 to 0.38,
        )

        private val NEAR_MAX_TIERS = listOf(
            NearMaxTier(0, 5_000, "5k", "Almost Perfect (Within 5k)", "Scores within 5,000 of the theoretical max. You're almost there!"),
            NearMaxTier(
                5_000, 10_000, "10k", "Close to Max (Within 10k)",
                "Scores within 10,000 of the theoretical max. A great run could close the gap.",
            ),
            NearMaxTier(10_000, 15_000, "15k", "Approaching Max (Within 15k)", "Scores within 15,000 of the theoretical max. Keep pushing!"),
        )

        /**
         * Web percentile bucket for a raw rank fraction (0–1).
         *
         * @param rawPct `rank / totalEntries`.
         * @return Bucket 1–100, or null for a non-positive fraction.
         */
        fun percentileBucket(rawPct: Double): Int? {
            if (rawPct <= 0) return null
            val topPct = (rawPct * 100).coerceIn(1.0, 100.0)
            return PERCENTILE_THRESHOLDS.firstOrNull { topPct <= it } ?: 100
        }

        /**
         * The next better threshold below [bucket].
         *
         * @param bucket Current bucket.
         * @return Lower threshold, or null for Top 1% or an unknown bucket.
         */
        fun nextLowerThreshold(bucket: Int): Int? {
            val index = PERCENTILE_THRESHOLDS.indexOf(bucket)
            return if (index > 0) PERCENTILE_THRESHOLDS[index - 1] else null
        }

        /**
         * Whether a score sits in the better half of its bracket.
         *
         * @param rawPct `rank / totalEntries`.
         * @return True when at or past the midpoint toward the next threshold.
         */
        fun isNearNextBracket(rawPct: Double): Boolean {
            val bucket = percentileBucket(rawPct) ?: return false
            if (bucket <= 1) return false
            val next = nextLowerThreshold(bucket) ?: return false
            val midpoint = next + (bucket - next) / 2.0
            return rawPct * 100 <= midpoint
        }

        /**
         * Decade start for 1970–2099, else null.
         *
         * @param year Release year.
         * @return E.g. 1980.
         */
        fun decadeStart(year: Int?): Int? = if (year != null && year in 1970..2099) (year / 10) * 10 else null

        /**
         * `80's`, `00's` style label.
         *
         * @param start Decade start.
         * @return Label.
         */
        fun decadeLabel(start: Int): String = "${two(start % 100)}'s"

        private fun two(value: Int): String = value.toString().padStart(2, '0')

        /**
         * Trim Swift `.whitespaces` (space separators and tab, not newlines).
         *
         * @param value Text.
         * @return Trimmed text.
         */
        fun trimSpaces(value: String): String = value.trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }
    }
}
