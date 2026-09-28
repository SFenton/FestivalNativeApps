package com.festivalscoretracker.android.rankings

import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.testing.FakeTransport

// region Synthetic rankings

/**
 * Synthetic, captured-shape rankings fixtures (made-up names and 32-hex IDs; never
 * production payloads). Row `n` has every metric's rank equal to `n`, except the
 * optional anonymous row which has an empty `accountId` and no name, like the live
 * Lead total-score rank-15 row seen 2026-09-28.
 */
object RankingsFixtures {
    /** The synthetic "selected" player, ranked [SELECTED_RANK] on every board. */
    const val SELECTED = "5e1ec7ed5e1ec7ed5e1ec7ed5e1ec7ed"

    /** Rank of [SELECTED] on every fixture board. */
    const val SELECTED_RANK = 40

    /** Accounts ranked on every board. */
    const val TOTAL_ACCOUNTS = 60

    /** Bands ranked on every board. */
    const val TOTAL_TEAMS = 30

    /** Rank of the anonymous row, when present. */
    const val ANONYMOUS_RANK = 3

    /**
     * Account ID for a rank.
     *
     * @param rank One-based rank.
     * @return 32-hex synthetic ID ([SELECTED] at [SELECTED_RANK]).
     */
    fun accountId(rank: Int): String = if (rank == SELECTED_RANK) SELECTED else "a".repeat(24) + rank.toString().padStart(8, '0')

    /**
     * One account row.
     *
     * @param rank One-based rank on every metric.
     * @param anonymous Empty account ID and no name.
     * @return Row JSON.
     */
    fun accountRow(rank: Int, anonymous: Boolean = false): String {
        val id = if (anonymous) "" else accountId(rank)
        val name = if (anonymous) "" else ",\"displayName\":\"Synthetic Player $rank\""
        return """{"accountId":"$id"$name,"songsPlayed":${200 - rank},"totalChartedSongs":250,"coverage":0.8,"rawSkillRating":${rank / 1000.0},""" +
            """"adjustedSkillRating":${1.5 - rank / 100.0},"adjustedSkillRank":$rank,"weightedRating":${1.2 - rank / 100.0},"weightedRank":$rank,""" +
            """"fcRate":0.5,"fcRateRank":$rank,"totalScore":${50_000_000L - rank * 1000L},"totalScoreRank":$rank,"maxScorePercent":${0.99 - rank / 1000.0},""" +
            """"maxScorePercentRank":$rank,"avgAccuracy":97.5,"fullComboCount":${125 - rank},"avgStars":5.8,"bestRank":1,"avgRank":12.5,"rawWeightedRating":${rank / 900.0},"unknownFutureField":1}"""
    }

    /**
     * An account rankings page.
     *
     * @param instrument Wire instrument.
     * @param rankBy Metric.
     * @param page One-based page.
     * @param pageSize Rows per page.
     * @param total Ranked accounts.
     * @param anonymousAt Rank of an anonymous row, or null.
     * @return Page JSON.
     */
    fun rankings(instrument: String, rankBy: String, page: Int, pageSize: Int, total: Int = TOTAL_ACCOUNTS, anonymousAt: Int? = ANONYMOUS_RANK): String {
        val first = (page - 1) * pageSize + 1
        val last = minOf(total, page * pageSize)
        val rows = if (first > last) "" else (first..last).joinToString(",") { accountRow(it, it == anonymousAt) }
        return """{"instrument":"$instrument","rankBy":"$rankBy","page":$page,"pageSize":$pageSize,"totalAccounts":$total,"entries":[$rows]}"""
    }

    /**
     * The selected player's own row envelope.
     *
     * @param instrument Echoed instrument (production sends blank).
     * @param accountId Account.
     * @param rank Rank on every metric.
     * @return JSON.
     */
    fun playerRanking(instrument: String = "", accountId: String = SELECTED, rank: Int = SELECTED_RANK): String =
        accountRow(rank).replace(accountId(rank), accountId).dropLast(1) + ""","instrument":"$instrument","totalRankedAccounts":$TOTAL_ACCOUNTS}"""

    /**
     * One band row.
     *
     * @param bandType Wire band type.
     * @param rank One-based rank.
     * @param withSelected Whether [SELECTED] is a member.
     * @return Row JSON.
     */
    fun bandRow(bandType: String, rank: Int, withSelected: Boolean = false): String {
        val first = if (withSelected) SELECTED else accountId(1000 + rank)
        val second = accountId(2000 + rank)
        return """{"bandId":"band${rank.toString().padStart(4, '0')}","teamKey":"$first:$second","teamMembers":[""" +
            """{"accountId":"$first","displayName":"Member ${rank}A"},{"accountId":"$second","displayName":""}],""" +
            """"songsPlayed":${90 - rank},"totalChartedSongs":250,"coverage":0.4,"rawSkillRating":${rank / 500.0},"adjustedSkillRating":${1.1 - rank / 100.0},""" +
            """"adjustedSkillRank":$rank,"weightedRating":0.9,"weightedRank":$rank,"fcRate":0.2,"fcRateRank":$rank,"totalScore":${9_000_000_000L - rank},""" +
            """"totalScoreRank":$rank,"avgAccuracy":95.0,"fullComboCount":10,"avgStars":5.1,"bestRank":2,"avgRank":30.0,"bandType":"$bandType"}"""
    }

    /**
     * A band rankings page; rank 2 includes [SELECTED].
     *
     * @param bandType Wire band type.
     * @param rankBy Band metric.
     * @param page One-based page.
     * @param pageSize Rows per page.
     * @return JSON.
     */
    fun bandRankings(bandType: String, rankBy: String, page: Int, pageSize: Int): String {
        val first = (page - 1) * pageSize + 1
        val last = minOf(TOTAL_TEAMS, page * pageSize)
        val rows = if (first > last) "" else (first..last).joinToString(",") { bandRow(bandType, it, withSelected = it == 2) }
        return """{"bandType":"$bandType","rankBy":"$rankBy","page":$page,"pageSize":$pageSize,"totalTeams":$TOTAL_TEAMS,"entries":[$rows]}"""
    }

    private fun query(url: String, name: String): String? = Regex("[?&]$name=([^&]+)").find(url)?.groupValues?.get(1)

    /**
     * Serve every rankings route on a fake transport.
     *
     * @param transport Transport to extend.
     * @param unranked Instruments whose own-row read answers 404.
     * @return The same transport.
     */
    fun install(transport: FakeTransport, unranked: Set<String> = emptySet()): FakeTransport = transport.apply {
        val instruments = listOf("Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "Solo_PeripheralGuitar", "Solo_PeripheralBass", "Solo_PeripheralVocals", "Solo_PeripheralCymbals", "Solo_PeripheralDrums")
        instruments.forEach { instrument ->
            onRaw("/api/rankings/$instrument") { request ->
                val page = query(request.url, "page")?.toInt() ?: 1
                val size = query(request.url, "pageSize")?.toInt() ?: 25
                HttpResult(200, rankings(instrument, query(request.url, "rankBy") ?: "totalscore", page, size).toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
            }
            onRaw("/api/rankings/$instrument/$SELECTED") {
                if (instrument in unranked) HttpResult(404, "{}".toByteArray()) else HttpResult(200, playerRanking().toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
            }
        }
        listOf("Band_Duets", "Band_Trios", "Band_Quad").forEach { bandType ->
            onRaw("/api/rankings/bands/$bandType") { request ->
                val page = query(request.url, "page")?.toInt() ?: 1
                val size = query(request.url, "pageSize")?.toInt() ?: 25
                HttpResult(200, bandRankings(bandType, query(request.url, "rankBy") ?: "totalscore", page, size).toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
            }
        }
    }
}

// endregion
