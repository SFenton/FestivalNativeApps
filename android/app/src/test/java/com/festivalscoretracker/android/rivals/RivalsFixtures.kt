package com.festivalscoretracker.android.rivals

import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures

// region Synthetic rivals fixtures

/** Synthetic Rivals payloads (made-up names and 32-hex IDs; never production data). */
object RivalsFixtures {
    /** Selected player. */
    const val PLAYER = Fixtures.ACCOUNT_A

    /** Synthetic rival IDs. */
    val RIVALS = listOf(
        "11111111111111111111111111111111",
        "22222222222222222222222222222222",
        "33333333333333333333333333333333",
        "44444444444444444444444444444444",
        "55555555555555555555555555555555",
    )

    /**
     * One rival row.
     *
     * @param id Account ID ("" for anonymous).
     * @param name Display name or null.
     * @param score Rival score.
     * @param shared Shared songs.
     * @return JSON object.
     */
    fun rival(id: String, name: String?, score: Double = 100.0, shared: Int = 20): String =
        """{"accountId":"$id","displayName":${name?.let { "\"$it\"" } ?: "null"},"rivalScore":$score,"sharedSongCount":$shared,"aheadCount":${shared / 2},"behindCount":${shared - shared / 2},"avgSignedDelta":-1.5}"""

    /**
     * A rivals list.
     *
     * @param scope Scope token.
     * @param above Above rows JSON.
     * @param below Below rows JSON.
     * @return JSON.
     */
    fun list(scope: String, above: List<String>, below: List<String>): String =
        """{"combo":"$scope","above":[${above.joinToString(",")}],"below":[${below.joinToString(",")}]}"""

    /**
     * A leaderboard rivals list.
     *
     * @param instrument Chart.
     * @param userRank Player rank.
     * @return JSON.
     */
    fun leaderboardList(instrument: String, userRank: Int = 42): String =
        """{"instrument":"$instrument","rankBy":"totalscore","userRank":$userRank,"above":[{"accountId":"${RIVALS[0]}","displayName":"Synthetic Neighbour","sharedSongCount":9,"aheadCount":5,"behindCount":4,"avgSignedDelta":1.0,"leaderboardRank":41,"userLeaderboardRank":$userRank}],"below":[]}"""

    /**
     * A detail response with songs spanning every category.
     *
     * @param rivalId Rival.
     * @param instrument Chart.
     * @param deltas Rank deltas, one song each.
     * @param name Rival name.
     * @return JSON.
     */
    fun detail(rivalId: String, instrument: String = "Solo_Guitar", deltas: List<Int> = listOf(1, -2, 3, -40, 60, 120, -9, 7), name: String? = "Synthetic Rival"): String {
        val songs = deltas.mapIndexed { index, delta ->
            val songId = listOf("s-alpha", "s-beta", "s-gamma").getOrElse(index) { "s-extra-$index" }
            """{"songId":"$songId","title":"Synthetic Song $index","artist":"Synthetic Artist","instrument":"$instrument","userInstrument":null,"rivalInstrument":null,"userRank":${100 + index},"rivalRank":${100 + index + delta},"rankDelta":$delta,"userScore":${200000 + delta * 10},"rivalScore":200000}"""
        }
        return """{"rival":{"accountId":"$rivalId","displayName":${name?.let { "\"$it\"" } ?: "null"}},"combo":"$instrument","source":"precomputed","totalSongs":${deltas.size},"offset":0,"limit":0,"sort":"closest","songs":[${songs.joinToString(",")}]}"""
    }

    /**
     * Standard transport plus rivals routes for Lead/Bass (and their 03 combo).
     *
     * @return Transport.
     */
    fun transport(): FakeTransport = FakeTransport.standard().apply {
        val lead = list("Solo_Guitar", listOf(rival(RIVALS[0], "Synthetic Alpha", 90.0), rival(RIVALS[1], "Synthetic Beta", 80.0)), listOf(rival(RIVALS[2], "Synthetic Gamma", 70.0), rival("", null, 10.0)))
        val bass = list("Solo_Bass", listOf(rival(RIVALS[1], "Synthetic Beta", 85.0, shared = 40)), listOf(rival(RIVALS[0], "Synthetic Alpha", 60.0), rival(RIVALS[3], "Synthetic Delta", 50.0)))
        on("/api/player/$PLAYER/rivals/Solo_Guitar") { lead }
        on("/api/player/$PLAYER/rivals/Solo_Bass") { bass }
        on("/api/player/$PLAYER/rivals/03") { list("03", listOf(rival(RIVALS[4], "Synthetic Combo", 75.0)), emptyList()) }
        on("/api/player/$PLAYER/leaderboard-rivals/Solo_Guitar") { leaderboardList("Solo_Guitar") }
        on("/api/player/$PLAYER/leaderboard-rivals/Solo_Bass") { leaderboardList("Solo_Bass", 7) }
        RIVALS.forEach { id ->
            on("/api/player/$PLAYER/rivals/Solo_Guitar/$id") { detail(id) }
            on("/api/player/$PLAYER/rivals/Solo_Bass/$id") { detail(id, "Solo_Bass", listOf(2, -3)) }
            on("/api/player/$PLAYER/rivals/03/$id") { detail(id, "Solo_Guitar", listOf(4, -4)) }
            on("/api/player/$PLAYER/leaderboard-rivals/Solo_Guitar/$id") { detail(id, "Solo_Guitar", listOf(5)) }
        }
    }
}

// endregion
