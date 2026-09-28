package com.festivalscoretracker.android.bands

import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures

// region Synthetic band fixtures

/** Synthetic band payloads (made-up names, 32-hex fake IDs; never production data). */
object BandFixtures {
    /** Player whose bands are listed. */
    const val PLAYER = Fixtures.ACCOUNT_A

    /** Duo team key. */
    const val DUO_KEY = "${Fixtures.ACCOUNT_A}:${Fixtures.ACCOUNT_B}"

    /** Duo band hash. */
    const val DUO_ID = "band-duo-hash"

    /**
     * One member.
     *
     * @param id Account ID (may be empty for an anonymous member).
     * @param name Display name, or null.
     * @param instruments Wire instrument IDs.
     * @param score Per-song score.
     * @return JSON.
     */
    fun member(id: String, name: String?, instruments: List<String> = listOf("Solo_Guitar"), score: Long? = null): String {
        val nameJson = name?.let { "\"$it\"" } ?: "null"
        val scoreJson = score?.let { ",\"score\":$it,\"accuracy\":985000,\"isFullCombo\":false,\"stars\":5" } ?: ""
        return """{"accountId":"$id","displayName":$nameJson,"instruments":[${instruments.joinToString(",") { "\"$it\"" }}]$scoreJson}"""
    }

    /** The duo's two members. */
    val duoMembers = listOf(
        member(Fixtures.ACCOUNT_A, "Synthetic Lead", listOf("Solo_Guitar", "Solo_Guitar", "Unknown_Chart")),
        member(Fixtures.ACCOUNT_B, "Synthetic Bass", listOf("Solo_Bass")),
    )

    /**
     * A `/api/player/{id}/bands` page.
     *
     * @param total Total bands.
     * @param page One-based page.
     * @param pageSize Page size.
     * @param group Group echoed.
     * @param accountId Account echoed.
     * @return JSON.
     */
    fun playerBands(total: Int, page: Int, pageSize: Int, group: String = "all", accountId: String = PLAYER): String {
        val start = (page - 1) * pageSize
        val rows = (start until minOf(total, start + pageSize)).joinToString(",") { index ->
            val (type, members) = when {
                index == 0 -> "Band_Duets" to duoMembers
                index % 3 == 1 -> "Band_Trios" to duoMembers + member("", null, emptyList())
                else -> "Band_Quad" to duoMembers + member("0000000000000000000000000000000$index".takeLast(32), "Synthetic Drums $index", listOf("Solo_Drums")) + member("", null)
            }
            val key = if (index == 0) DUO_KEY else "${Fixtures.ACCOUNT_A}:team$index"
            val id = if (index == 0) DUO_ID else "band-$index"
            """{"bandId":"$id","teamKey":"$key","bandType":"$type","appearanceCount":${10 + index},"members":[${members.joinToString(",")}]}"""
        }
        return """{"accountId":"$accountId","group":"$group","totalCount":$total,"entries":[$rows]}"""
    }

    /**
     * A rankings-by-teamKey envelope.
     *
     * @param bandType Echoed type.
     * @param teamKey Selected key, or null for an unranked team.
     * @return JSON.
     */
    fun bandProfile(bandType: String = "Band_Duets", teamKey: String? = DUO_KEY): String {
        val selected = teamKey?.let {
            """{"bandId":"$DUO_ID","teamKey":"$it","members":[${duoMembers.joinToString(",")}],"songsPlayed":29,"totalChartedSongs":50,
               "adjustedSkillRank":3,"weightedRank":4,"fcRate":0.3,"fcRateRank":5,"totalScore":49500000,"totalScoreRank":2,
               "avgAccuracy":987654,"fullComboCount":15,"avgStars":5.4,"bestRank":1,"avgRank":12.5,"configurations":[]}"""
        } ?: "null"
        return """{"bandType":"$bandType","rankBy":"adjusted","page":1,"pageSize":1,"totalTeams":2,"entries":[],"selectedBandEntry":$selected}"""
    }

    /**
     * Rank history.
     *
     * @param status `historyStatus`.
     * @param empty Whether no snapshots exist.
     * @return JSON.
     */
    fun history(status: String? = null, empty: Boolean = false): String {
        val rows = if (empty) "" else listOf("2024-01-03" to 1, "2024-01-01" to 3, "2024-01-02" to 2, "2024-01-04" to 0).joinToString(",") { (date, rank) ->
            """{"snapshotDate":"$date","adjustedSkillRank":$rank,"weightedRank":$rank,"fcRateRank":$rank,"totalScoreRank":$rank,
               "adjustedSkillRating":0.0${rank + 1},"weightedRating":0.05,"fcRate":0.3,"totalScore":${49000000 + rank}}"""
        }
        val statusJson = status?.let { "\"$it\"" } ?: "null"
        return """{"bandType":"Band_Duets","teamKey":"$DUO_KEY","days":30,"history":[$rows],"historyStatus":$statusJson,"historyMessage":null}"""
    }

    /** Best/worst songs referencing one known and one unknown catalogue song. */
    val songs = """{"bandType":"Band_Duets","teamKey":"$DUO_KEY","limit":5,
        "best":[{"songId":"s-alpha","rank":1,"totalEntries":26,"percentile":0.004,"score":123456}],
        "worst":[{"songId":"s-missing","rank":20,"totalEntries":26,"percentile":0.77,"score":1000}]}"""

    /**
     * A song band leaderboard page.
     *
     * @param songId Song.
     * @param bandType Type.
     * @param total Population.
     * @param offset Offset.
     * @param top Page size.
     * @return JSON.
     */
    fun songBoard(songId: String, bandType: String, total: Int, offset: Int, top: Int): String {
        val rows = (offset until minOf(total, offset + top)).map { index ->
            val rank = index + 1
            val members = listOf(
                member(Fixtures.ACCOUNT_A, "Synthetic Lead", listOf("Solo_Guitar"), 60000L - rank),
                member("", null, listOf("Solo_Bass"), 40000L),
            )
            """{"bandId":"band-$rank","bandType":"$bandType","teamKey":"${Fixtures.ACCOUNT_A}:t$rank","members":[${members.joinToString(",")}],
               "score":${100000 - rank},"rank":$rank,"accuracy":${if (rank == 1) 1000000 else 975000},"isFullCombo":${rank == 1},"stars":6,"season":15,"difficulty":3,"percentile":0.1}"""
        }
        return """{"songId":"$songId","bandType":"$bandType","count":${rows.size},"totalEntries":$total,"localEntries":$total,"entries":[${rows.joinToString(",")}]}"""
    }

    /**
     * Register every band route on a transport.
     *
     * @param transport Transport.
     * @param bandCount Player band count.
     * @param boardTotal Song band leaderboard population.
     * @return The transport.
     */
    fun install(transport: FakeTransport, bandCount: Int = 30, boardTotal: Int = 30): FakeTransport = transport.apply {
        val pin = mapOf("X-FST-Publication-Id" to "7")
        on("/api/player/$PLAYER/bands", headers = pin) { request ->
            val page = Regex("[?&]page=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            val size = Regex("pageSize=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            val group = Regex("group=(\\w+)").find(request.url)!!.groupValues[1]
            val total = if (group == "all") bandCount else if (group == "duos") 0 else 2
            playerBands(total, page, size, group)
        }
        on("/api/rankings/bands/Band_Duets", headers = pin) { request ->
            val key = Regex("teamKey=([^&]+)").find(request.url)?.groupValues?.get(1)?.replace("%3A", ":")
            if (key != null) bandProfile(teamKey = key.takeIf { it == DUO_KEY }) else "{}"
        }
        on("/api/rankings/bands/Band_Duets/$DUO_KEY/history", headers = pin) { history() }
        on("/api/rankings/bands/Band_Duets/$DUO_KEY/songs", headers = pin) { songs }
        listOf("Band_Duets", "Band_Trios", "Band_Quad").forEach { type ->
            on("/api/leaderboard/s-alpha/bands/$type", headers = pin) { request ->
                val top = Regex("top=(\\d+)").find(request.url)!!.groupValues[1].toInt()
                val offset = Regex("offset=(\\d+)").find(request.url)!!.groupValues[1].toInt()
                songBoard("s-alpha", type, if (type == "Band_Quad") 0 else boardTotal, offset, top)
            }
        }
    }
}

// endregion
