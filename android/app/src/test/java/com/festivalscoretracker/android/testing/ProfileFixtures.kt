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
     * Seven ranked Lead scores, so Lead shows both Top Five and Bottom Five Songs (issue #595),
     * plus [defaultRows]' Bass row (a single list). The four extra song IDs are not in the
     * catalogue, so their rows show the ID prefix as the web does.
     */
    val topAndBottomRows = defaultRows.take(3) + listOf(
        score("s-delta", "01", rank = 40, total = 200),
        score("s-epsilon", "01", rank = 60, total = 200),
        score("s-zeta", "01", rank = 90, total = 200),
        score("s-eta", "01", rank = 120, total = 200),
    ) + defaultRows.drop(3)

    /** R4 variants, a dropped modern score, a legacy fallback and a valid raw score. */
    fun invalidScoresProfile(account: String = Fixtures.ACCOUNT_A) = profile(account, rows = listOf(
        """{"si":"s-alpha","ins":"01","sc":120000,"acc":1000,"fc":true,"st":6,"rk":1,"te":1000,"ml":5,
          "vs":[{"sc":100500,"acc":900,"fc":false,"st":4,"ml":0.5,"rt":[{"l":0,"r":50},{"l":1,"r":40},{"l":2,"r":30}]}]}""",
        """{"si":"s-beta","ins":"01","sc":120000,"acc":1000,"fc":true,"st":6,"rk":2,"te":1000,"ml":4,
          "validScore":90000,"validRank":1,"validTotalEntries":1000}""",
        """{"si":"s-gamma","ins":"01","sc":120000,"acc":1000,"fc":true,"st":6,"rk":3,"te":1000,
          "validScore":95000,"validAccuracy":800,"validIsFullCombo":false,"validStars":3,"validRank":6,"validTotalEntries":300}""",
        score("s-delta", score = 90000, acc = 1000, fc = true, stars = 5, rank = 10, total = 1000),
    ))

    /** Synthetic catalogue maxima and population changepoints for the R4 profile fixture. */
    val invalidScoresSongs = """{"count":4,"songs":[${
        listOf("s-alpha", "s-beta", "s-gamma", "s-delta").joinToString(",") { id ->
            """{"songId":"$id","title":"$id","artist":"Synthetic Artist","difficulty":{"guitar":3},
              "maxScores":{"Solo_Guitar":100000},"populationTiers":{"Solo_Guitar":{"bc":500,"t":[{"l":1,"t":600},{"l":2,"t":800}]}}}"""
        }
    }]}"""

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
     * A score-history body with more than five Lead scores for `s-alpha`, so Song Detail's Score
     * History card ends with View All Scores.
     *
     * @param account Account ID.
     * @param lead Lead rows (dated January 1st onward).
     * @return JSON with [lead] Lead rows and one Bass row.
     */
    fun longHistory(account: String = Fixtures.ACCOUNT_A, lead: Int = 7): String {
        val rows = (1..lead).map { day ->
            """{"songId":"s-alpha","instrument":"Solo_Guitar","newScore":${700000 + day * 1000},"newRank":9,"accuracy":${950000 + day * 1000},"isFullCombo":false,"stars":5,"season":40,"changedAt":"2024-01-%02dT00:00:00Z"}""".format(day)
        } + """{"songId":"s-alpha","instrument":"Solo_Bass","newScore":1,"newRank":1,"changedAt":"2024-01-02T00:00:00Z"}"""
        return """{"accountId":"$account","count":${rows.size},"history":[${rows.joinToString(",")}]}"""
    }

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
