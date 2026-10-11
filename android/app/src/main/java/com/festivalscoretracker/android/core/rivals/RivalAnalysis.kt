package com.festivalscoretracker.android.core.rivals

import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

// region Common rivals

/** Rivals present in every loaded per-chart list (web `RivalsPage` `commonRivals`). */
object RivalCommonRivals {
    /**
     * Intersect two or more lists: a rival must appear (above or below) in every list;
     * direction is a majority vote (ties favour above); the highest `sharedSongCount`
     * entry represents the rival; each side sorts by `rivalScore` descending.
     * Anonymous rows (no valid account ID) cannot be matched and are skipped. Charts
     * without rivals are ignored, as on the web where their 404 leaves no data.
     *
     * @param loaded Each loaded chart's list.
     * @return Above and below rivals (both empty for fewer than two non-empty lists).
     */
    fun intersect(loaded: List<RivalsListResponse>): Pair<List<RivalSummary>, List<RivalSummary>> {
        val lists = loaded.filterNot { it.isEmpty }
        if (lists.size < 2) return emptyList<RivalSummary>() to emptyList()
        val counts = LinkedHashMap<String, Int>()
        val aboveEntries = HashMap<String, MutableList<RivalSummary>>()
        val belowEntries = HashMap<String, MutableList<RivalSummary>>()
        for (list in lists) {
            val seen = HashSet<String>()
            val aboveIds = list.above.mapTo(HashSet()) { it.accountId }
            for (rival in list.above + list.below) {
                if (!rival.isNavigable || !seen.add(rival.accountId)) continue
                counts[rival.accountId] = (counts[rival.accountId] ?: 0) + 1
                val bucket = if (rival.accountId in aboveIds) aboveEntries else belowEntries
                bucket.getOrPut(rival.accountId) { mutableListOf() } += rival
            }
        }
        val above = mutableListOf<RivalSummary>()
        val below = mutableListOf<RivalSummary>()
        for ((id, count) in counts) {
            if (count < lists.size) continue
            val up = aboveEntries[id].orEmpty()
            val down = belowEntries[id].orEmpty()
            val best = (up + down).reduce { a, b -> if (a.sharedSongCount >= b.sharedSongCount) a else b }
            if (up.size >= down.size) above += best else below += best
        }
        return above.sortedByDescending { it.rivalScore } to below.sortedByDescending { it.rivalScore }
    }
}

// endregion

// region Categories

/** Tone of a rivalry category (web `RivalCategorySentiment`). */
enum class RivalSentiment { Neutral, Positive, Negative }

/**
 * One themed group of shared songs (web `rivalCategories.ts`).
 *
 * @property key Stable key used as the Rivalry `mode`.
 * @property title Title Case heading.
 * @property description Web `rivals.detail.*Desc` text.
 * @property sentiment Tone.
 * @property songs Songs in category order.
 */
data class RivalCategory(
    val key: String,
    val title: String,
    val description: String,
    val sentiment: RivalSentiment,
    val songs: List<RivalSongComparison>,
)

/** Native port of `categorizeRivalSongs`. */
object RivalCategorization {
    /** Songs in Closest Battles. */
    const val CLOSEST_BATTLES_COUNT = 5

    /** Songs per category on Rival Detail before "View All". */
    const val PREVIEW_COUNT = 5

    private data class Meta(val title: String, val description: String, val sentiment: RivalSentiment)

    private val META = linkedMapOf(
        "closest_battles" to Meta("Closest Battles", "Songs where you and your rival are neck and neck.", RivalSentiment.Neutral),
        "almost_passed" to Meta("Almost Passed", "You're just behind — one good run could flip these.", RivalSentiment.Negative),
        "slipping_away" to Meta("Slipping Away", "They're pulling further ahead on these songs.", RivalSentiment.Negative),
        "barely_winning" to Meta("Barely Winning", "You're just ahead — don't let them catch up.", RivalSentiment.Positive),
        "pulling_forward" to Meta("Pulling Forward", "You have a solid lead on these songs.", RivalSentiment.Positive),
        "dominating_them" to Meta("Dominating Them", "You're far ahead — these are your strongest matchups.", RivalSentiment.Positive),
    )

    /** Every category key in web order. */
    val keys: List<String> get() = META.keys.toList()

    /**
     * Heading for a key, or the key itself when unknown (as on the web).
     *
     * @param key Category key.
     * @return Title.
     */
    fun title(key: String): String = META[key]?.title ?: key

    /**
     * Description for a key.
     *
     * @param key Category key.
     * @return Description, or null when unknown.
     */
    fun description(key: String): String? = META[key]?.description

    /**
     * Heading tone for a key.
     *
     * @param key Category key.
     * @return Sentiment, neutral when unknown.
     */
    fun sentiment(key: String): RivalSentiment = META[key]?.sentiment ?: RivalSentiment.Neutral

    /**
     * Split compared songs into non-empty categories in web order. A song may appear in
     * Closest Battles and its directional category; ties beyond Closest Battles are dropped.
     *
     * @param songs Compared songs.
     * @return Categories.
     */
    fun categorize(songs: List<RivalSongComparison>): List<RivalCategory> {
        if (songs.isEmpty()) return emptyList()
        val userLeads = songs.filter { it.rankDelta > 0 }.sortedBy { it.rankDelta }
        val rivalLeads = songs.filter { it.rankDelta < 0 }.sortedByDescending { it.rankDelta }
        val result = mutableListOf<RivalCategory>()
        fun add(key: String, list: List<RivalSongComparison>) {
            if (list.isEmpty()) return
            val meta = META.getValue(key)
            result += RivalCategory(key, meta.title, meta.description, meta.sentiment, list)
        }
        add("closest_battles", songs.sortedBy { abs(it.rankDelta.toLong()) }.take(CLOSEST_BATTLES_COUNT))
        if (rivalLeads.isNotEmpty()) {
            val half = (rivalLeads.size + 1) / 2
            add("almost_passed", rivalLeads.take(half))
            add("slipping_away", rivalLeads.drop(half))
        }
        if (userLeads.isNotEmpty()) {
            val third = (userLeads.size + 2) / 3
            add("barely_winning", userLeads.take(third))
            add("pulling_forward", userLeads.drop(third).take(third))
            add("dominating_them", userLeads.drop(third * 2))
        }
        return result
    }
}

// endregion

// region Head to head

/** Rivalry song orderings (native control; the web keeps category order). */
enum class RivalrySort(val label: String) {
    Category("Default"),
    Closest("Closest Gap"),
    YouLead("Your Biggest Leads"),
    TheyLead("Their Biggest Leads"),
    Title("Title"),
}

/**
 * Who leads one shared song (iOS `RivalSongStanding`): it colours the song row's "#rank Name"
 * pills and delta badge (`rival-rows` R3).
 */
enum class RivalSongStanding {
    /** The player has the better rank. */
    PlayerAhead,

    /** The rival has the better rank. */
    RivalAhead,

    /** Same rank. */
    Tied;

    /** The player's pill: true for green, false for red, null for neutral. */
    val playerWins: Boolean? get() = when (this) {
        PlayerAhead -> true
        RivalAhead -> false
        Tied -> null
    }

    /** The rival's pill, the mirror of [playerWins]. */
    val rivalWins: Boolean? get() = playerWins?.not()
}

/** Summaries, orderings and number formatting for rival comparisons. */
object RivalHeadToHead {
    /**
     * Order songs; ties keep the incoming order.
     *
     * @param songs Category songs.
     * @param sort Ordering.
     * @return Ordered copy.
     */
    fun sort(songs: List<RivalSongComparison>, sort: RivalrySort): List<RivalSongComparison> = when (sort) {
        RivalrySort.Category -> songs
        RivalrySort.Closest -> songs.sortedBy { abs(it.rankDelta.toLong()) }
        RivalrySort.YouLead -> songs.sortedByDescending { it.rankDelta }
        RivalrySort.TheyLead -> songs.sortedBy { it.rankDelta }
        RivalrySort.Title -> songs.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title ?: it.songId })
    }

    /**
     * Web `rivals.detail.summary`.
     *
     * @param songs Compared songs.
     * @param locale Number locale.
     * @return "{total} shared songs · {ahead} ahead / {behind} behind".
     */
    fun summary(songs: List<RivalSongComparison>, locale: Locale = Locale.getDefault()): String {
        val format = NumberFormat.getIntegerInstance(locale)
        return "${format.format(songs.size)} shared songs · ${format.format(songs.count { it.rankDelta > 0 })} ahead / " +
            "${format.format(songs.count { it.rankDelta < 0 })} behind"
    }

    /**
     * Who leads one shared song (iOS `RivalSongStanding`).
     *
     * @param delta Signed rank delta (positive: the player leads).
     * @return Standing.
     */
    fun standing(delta: Long): RivalSongStanding = when {
        delta > 0 -> RivalSongStanding.PlayerAhead
        delta < 0 -> RivalSongStanding.RivalAhead
        else -> RivalSongStanding.Tied
    }

    /**
     * A song row's "#rank Name" standing pill text (iOS `RivalSongRowContent`, `rival-rows` R3).
     *
     * @param rank Leaderboard rank.
     * @param name Player or rival name.
     * @param locale Number locale.
     * @return Text such as `#1,234 SFentonX`.
     */
    fun standingPill(rank: Int, name: String, locale: Locale = Locale.getDefault()): String =
        "#${NumberFormat.getIntegerInstance(locale).format(rank)} $name"

    /**
     * The trailing delta badge's unsigned rank gap (the arrow carries the direction), abbreviated
     * like [formatRankDelta] so it fits the badge.
     *
     * @param delta Signed rank delta.
     * @param locale Number locale.
     * @return Text such as `12`, `15K` or `0`.
     */
    fun deltaMagnitude(delta: Long, locale: Locale = Locale.getDefault()): String = formatRankDelta(abs(delta), locale).removePrefix("+")

    /**
     * A song row's single TalkBack label: song, chart, both ranks and who leads.
     *
     * @param song Comparison.
     * @param title Song title.
     * @param chart Chart label, or null.
     * @param playerName Player's name.
     * @param rivalName Rival's name.
     * @param locale Number locale.
     * @return Text such as `Song, Lead, You rank 3, Rival rank 15, you lead by 12 ranks`.
     */
    fun songRowLabel(song: RivalSongComparison, title: String, chart: String?, playerName: String, rivalName: String, locale: Locale = Locale.getDefault()): String {
        val format = NumberFormat.getIntegerInstance(locale)
        return listOfNotNull(
            title,
            chart?.takeIf { it.isNotEmpty() },
            "$playerName rank ${format.format(song.userRank)}",
            "$rivalName rank ${format.format(song.rivalRank)}",
            leaderPhrase(song.rankDelta.toLong(), rivalName, locale),
        ).joinToString(", ")
    }

    /**
     * Web `formatRankDelta`: sign, exact below 10K, `K` below 1M, then `M`.
     *
     * @param delta Signed rank delta (positive: the player leads).
     * @param locale Number locale.
     * @return Text such as `+12`, `−15K` or `+1.5M`.
     */
    fun formatRankDelta(delta: Long, locale: Locale = Locale.getDefault()): String {
        val magnitude = abs(delta)
        val sign = if (delta > 0) "+" else if (delta < 0) "−" else ""
        if (magnitude < 10_000) return sign + NumberFormat.getIntegerInstance(locale).format(magnitude)
        if (magnitude >= 1_000_000) {
            val millions = magnitude / 1_000_000.0
            val text = if (millions >= 10) {
                millions.roundToLong().toString()
            } else {
                String.format(Locale.ROOT, "%.1f", millions).removeSuffix(".0")
            }
            return "${sign}${text}M"
        }
        return "${sign}${(magnitude / 1_000.0).roundToLong()}K"
    }

    /**
     * Spoken rank lead for a song row's accessibility label: the exact unsigned gap with a
     * singular/plural unit (the visible badge shows an arrow over the abbreviated gap).
     *
     * @param delta Signed rank delta (positive: the player leads).
     * @param rivalName Rival's display name.
     * @param locale Number locale.
     * @return Text such as `you lead by 1 rank`, `Rival leads by 12,345 ranks` or `tied`.
     */
    fun leaderPhrase(delta: Long, rivalName: String, locale: Locale = Locale.getDefault()): String {
        if (delta == 0L) return "tied"
        val magnitude = abs(delta)
        val gap = NumberFormat.getIntegerInstance(locale).format(magnitude) + if (magnitude == 1L) " rank" else " ranks"
        return if (delta > 0) "you lead by $gap" else "$rivalName leads by $gap"
    }
}

// endregion
