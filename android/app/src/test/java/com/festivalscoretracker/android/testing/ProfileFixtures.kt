package com.festivalscoretracker.android.testing

// region Profile fixtures

/** Synthetic player-profile payloads (made-up songs and IDs; never production data). */
object ProfileFixtures {
    /**
     * One compact score row.
     *
     * @param song Song ID.
     * @param code Instrument hex code.
     * @param score Score.
     * @param acc Wire accuracy (percent × 10).
     * @param fc Full combo.
     * @param stars Stars.
     * @param rank Rank.
     * @param total Chart population.
     * @return JSON object.
     */
    fun score(song: String, code: String = "01", score: Int = 90_000, acc: Int = 950, fc: Boolean = false, stars: Int = 5, rank: Int = 5, total: Int = 100) =
        """{"si":"$song","ins":"$code","sc":$score,"acc":$acc,"fc":$fc,"st":$stars,"sn":9,"pct":-1,"rk":$rank,"te":$total}"""

    /**
     * A 200 profile body.
     *
     * @param account Account ID.
     * @param name Display name.
     * @param rows Score rows.
     * @return JSON.
     */
    fun profile(account: String = Fixtures.ACCOUNT_A, name: String? = "Synthetic Player", rows: List<String> = defaultRows) =
        """{"accountId":"$account",${name?.let { "\"displayName\":\"$it\"," } ?: ""}"totalScores":${rows.size},"scores":[${rows.joinToString(",")}]}"""

    /** Lead (3 rows, one FC, one gold) and Bass (1 row) scores. */
    val defaultRows = listOf(
        score("s-alpha", "01", score = 95_000, acc = 1000, fc = true, stars = 6, rank = 1, total = 200),
        score("s-beta", "01", score = 80_000, acc = 900, stars = 5, rank = 30, total = 200),
        score("s-gamma", "01", score = 70_000, acc = 800, stars = 4, rank = 150, total = 200),
        score("s-alpha", "02", score = 60_000, acc = 700, stars = 3, rank = 9, total = 10),
    )

    /**
     * A 202 syncing body.
     *
     * @param account Account ID.
     * @return JSON.
     */
    fun syncing(account: String = Fixtures.ACCOUNT_A) =
        """{"accountId":"$account","displayName":"Synthetic Player","status":"syncing","notYetPublished":true,"totalScores":0,"scores":[]}"""

    /**
     * A single-account ranking row.
     *
     * @param account Account ID.
     * @param rank Total Score rank.
     * @param total Ranked field.
     * @return JSON.
     */
    fun ranking(account: String = Fixtures.ACCOUNT_A, rank: Int = 8, total: Int = 500) =
        """{"accountId":"$account","displayName":"Synthetic Player","instrument":"","totalScore":1234567,"totalScoreRank":$rank,"totalRankedAccounts":$total,"songsPlayed":3,"totalChartedSongs":3}"""

    /**
     * A rank-history body with three days.
     *
     * @param account Account ID.
     * @param instrument Wire ID.
     * @return JSON.
     */
    fun rankHistory(account: String = Fixtures.ACCOUNT_A, instrument: String = "Solo_Guitar") =
        """{"instrument":"$instrument","accountId":"$account","history":[
          {"snapshotDate":"2026-09-03","totalScoreRank":12,"totalScore":1000000,"rankedAccountCount":500},
          {"snapshotDate":"2026-09-01","totalScoreRank":20,"totalScore":900000,"rankedAccountCount":480},
          {"snapshotDate":"2026-09-02","totalScoreRank":0,"totalScore":null},
          {"snapshotDate":"2026-09-04","totalScoreRank":8,"totalScore":1234567,"rankedAccountCount":500}]}"""

    /**
     * A score-history body.
     *
     * @param account Account ID.
     * @return JSON with two Lead rows for `s-alpha` and one Bass row.
     */
    fun history(account: String = Fixtures.ACCOUNT_A) =
        """{"accountId":"$account","count":3,"history":[
          {"songId":"s-alpha","instrument":"Solo_Guitar","oldScore":700000,"newScore":850000,"oldRank":9,"newRank":4,"accuracy":991200,"isFullCombo":true,"stars":5,"season":40,"scoreAchievedAt":"2024-01-05T00:00:00Z","changedAt":"2024-01-05T00:00:00Z"},
          {"songId":"s-alpha","instrument":"Solo_Guitar","newScore":700000,"newRank":9,"accuracy":954500,"isFullCombo":false,"stars":4,"season":39,"changedAt":"2024-01-01T00:00:00Z"},
          {"songId":"s-alpha","instrument":"Solo_Bass","newScore":1,"newRank":1,"changedAt":"2024-01-02T00:00:00Z"}]}"""

    /**
     * Register every profile route for [account] on a transport.
     *
     * @param transport Fake transport.
     * @param account Account ID.
     * @param headers Profile response headers.
     */
    fun register(transport: FakeTransport, account: String = Fixtures.ACCOUNT_A, headers: Map<String, String> = mapOf("X-FST-Publication-Id" to "7")) {
        transport.on("/api/player/$account", headers = headers) { profile(account) }
        listOf("Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "Solo_PeripheralGuitar", "Solo_PeripheralBass", "Solo_PeripheralVocals", "Solo_PeripheralCymbals", "Solo_PeripheralDrums").forEach { wire ->
            transport.on("/api/rankings/$wire/$account") { ranking(account) }
            transport.on("/api/rankings/$wire/$account/history") { rankHistory(account, wire) }
        }
        transport.on("/api/player/$account/history") { history(account) }
    }
}

// endregion
