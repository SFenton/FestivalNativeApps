package com.festivalscoretracker.android.testing

// region Compete fixtures

/**
 * Synthetic Compete routes: rankings (shared fixtures), combo boards and rivals for the
 * selected player. Shared by the Robolectric Compete tests and the Compete device journeys.
 */
object CompeteFixtures {
    /** Selected player (ranked 40th, outside the top 10). */
    const val PLAYER = RankingsFixtures.SELECTED

    /**
     * Combo board JSON.
     *
     * @param comboId Combo.
     * @param rows Rows.
     * @return JSON.
     */
    fun comboBoard(comboId: String, rows: Int = 3): String {
        val entries = (1..rows).joinToString(",") { rank ->
            """{"rank":$rank,"accountId":"${RankingsFixtures.accountId(rank)}","displayName":"Synthetic Combo $rank","adjustedRating":0.1,"weightedRating":0.2,"fcRate":0.5,"totalScore":${1_000_000 - rank},"maxScorePercent":0.9,"songsPlayed":10,"totalChartedSongs":20,"fullComboCount":5,"computedAt":"2026-09-28T00:00:00Z"}"""
        }
        return """{"comboId":"$comboId","rankBy":"totalscore","page":1,"pageSize":10,"totalAccounts":30,"entries":[$entries]}"""
    }

    private fun combo(url: String): String = Regex("combo=([0-9a-fA-F]+)").find(url)?.groupValues?.get(1).orEmpty()

    /**
     * Standard transport with rankings, a Lead+Bass combo board and rivals.
     *
     * @return Transport.
     */
    fun transport(): FakeTransport = RankingsFixtures.install(FakeTransport.standard(), unranked = setOf("Solo_PeripheralVocals")).apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/rankings/combo", headers = mapOf("X-FST-Publication-Id" to "7")) { comboBoard(combo(it.url)) }
        on("/api/rankings/combo/$PLAYER", headers = mapOf("X-FST-Publication-Id" to "7")) {
            """{"comboId":"${combo(it.url)}","rankBy":"totalscore","rank":2,"accountId":"$PLAYER","displayName":"Synthetic Player","totalScore":999998,"songsPlayed":10,"totalChartedSongs":20,"totalAccounts":30}"""
        }
        val ids = RivalsFixtures.RIVALS
        on("/api/player/$PLAYER/rivals/Solo_Guitar") { RivalsFixtures.list("Solo_Guitar", listOf(RivalsFixtures.rival(ids[0], "Synthetic Alpha")), listOf(RivalsFixtures.rival(ids[1], "Synthetic Beta"))) }
        on("/api/player/$PLAYER/rivals/03") { RivalsFixtures.list("03", listOf(RivalsFixtures.rival(ids[4], "Synthetic Combo")), emptyList()) }
        on("/api/player/$PLAYER/rivals/03/${ids[4]}") { RivalsFixtures.detail(ids[4]) }
    }
}

// endregion
