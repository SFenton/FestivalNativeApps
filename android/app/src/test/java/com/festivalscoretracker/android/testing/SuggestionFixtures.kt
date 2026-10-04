package com.festivalscoretracker.android.testing

/** Synthetic Suggestions fixtures: made-up titles and account IDs only. */
object SuggestionFixtures {
    /** Songs in the synthetic catalogue. */
    const val SONG_COUNT = 40

    /** Songs the synthetic player has scored (the rest are unplayed). */
    const val SCORED = 30

    private val hex = listOf("01", "02", "04", "08", "10", "20", "40", "80", "100")

    /**
     * A catalogue of [SONG_COUNT] synthetic songs, every chart charted, with max scores.
     *
     * @param currentSeason Catalogue season.
     * @return `/api/songs` JSON.
     */
    fun songsJson(currentSeason: Int = 12): String {
        val songs = (0 until SONG_COUNT).joinToString(",") { i ->
            val title = if (i % 10 == 1) "Synthetic Track ${i - 1}" else "Synthetic Track $i"
            """{"songId":"sg-$i","title":"$title","artist":"Synthetic Artist ${i % 6}","year":${1975 + i},"durationSeconds":200,
              "difficulty":{"guitar":3,"bass":2,"drums":4,"vocals":1,"proGuitar":5,"proBass":2,"proDrums":3,"proCymbals":3,"proVocals":2},
              "maxScores":{"Solo_Guitar":200000,"Solo_Bass":200000,"Solo_Drums":200000}}"""
        }
        return """{"count":$SONG_COUNT,"currentSeason":$currentSeason,"songs":[$songs]}"""
    }

    /**
     * The synthetic player's compact profile.
     *
     * @param accountId Account.
     * @return `/api/player/{id}` JSON (wire accuracy in thousandths of a percent).
     */
    fun playerJson(accountId: String = Fixtures.ACCOUNT_A): String {
        val rows = mutableListOf<String>()
        for (i in 0 until SCORED) {
            for (c in 0 until 3) {
                val stars = listOf(6, 5, 4, 3)[(i + c) % 4]
                val fc = (i + c) % 5 == 0
                val acc = listOf(990, 960, 930, 900)[(i + c) % 4]
                val score = 200_000 - listOf(2_000, 7_000, 12_000, 40_000)[(i + c) % 4]
                val rank = listOf(2, 4, 9, 30, 60)[(i + c) % 5]
                rows += """{"si":"sg-$i","ins":"${hex[c]}","sc":$score,"acc":$acc,"fc":$fc,"st":$stars,"sn":${1 + (i % 12)},"rk":$rank,"te":1000,"pct":${rank / 10.0}}"""
            }
        }
        return """{"accountId":"$accountId","displayName":"Synthetic Player","totalScores":${rows.size},"scores":[${rows.joinToString(",")}]}"""
    }

    /**
     * Rivals across two combos for the synthetic player.
     *
     * @param accountId Account.
     * @return `/api/player/{id}/rivals/all` JSON.
     */
    fun rivalsJson(accountId: String = Fixtures.ACCOUNT_A): String {
        val songs = (0 until 12).joinToString(",") { "\"sg-$it\"" }
        fun rival(id: String, deltas: List<Int>) = """{"accountId":"$id","displayName":"Rival $id","direction":"above","sharedSongCount":${deltas.size},
            "aheadCount":2,"behindCount":2,"rivalScore":4.5,"samples":[${deltas.mapIndexed { i, d -> """{"s":$i,"i":"Solo_Guitar","ur":${100 + d},"rr":100,"us":1000,"rs":900}""" }.joinToString(",")}]}"""
        return """{"accountId":"$accountId","songs":[$songs],"combos":[{"combo":"01","above":[${rival("rv-a", listOf(-3, -25, 4, 40, -8, 2))}],"below":[${rival("rv-b", listOf(5, -2, 35, -30))}]}]}"""
    }

    /**
     * A standard transport plus the Suggestions reads.
     *
     * @param accountId Player the profile/rivals belong to.
     * @return Transport.
     */
    fun transport(accountId: String = Fixtures.ACCOUNT_A): FakeTransport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { songsJson() }
        on("/api/player/$accountId", headers = mapOf("X-FST-Publication-Id" to "7")) { playerJson(accountId) }
        on("/api/player/$accountId/rivals/all") { rivalsJson(accountId) }
    }
}
