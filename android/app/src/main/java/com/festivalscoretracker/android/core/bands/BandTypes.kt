package com.festivalscoretracker.android.core.bands

// region Band type

/**
 * The three ranked band sizes (web `utils/bandTypes.ts`, Apple/Windows `BandType`).
 *
 * @property wireId Exact service identifier used in URLs and payloads.
 * @property label Web band-size name.
 * @property memberCount Players in a band of this size.
 */
enum class BandType(val wireId: String, val label: String, val memberCount: Int) {
    Duets("Band_Duets", "Duos", 2),
    Trios("Band_Trios", "Trios", 3),
    Quad("Band_Quad", "Quads", 4);

    companion object {
        /**
         * Parse an exact service identifier.
         *
         * @param wireId Value such as `Band_Trios`.
         * @return The band size, or null for anything else.
         */
        fun fromWireId(wireId: String?): BandType? = entries.firstOrNull { it.wireId == wireId }
    }
}

// endregion

// region Rank-by metric

/**
 * Band rank-by metrics (`rankBy` query values); bands have no max-score metric.
 *
 * @property wireId `rankBy` value.
 * @property label Picker label.
 */
enum class BandRankingMetric(val wireId: String, val label: String) {
    Adjusted("adjusted", "Adjusted Skill"),
    Weighted("weighted", "Weighted"),
    FcRate("fcrate", "FC Rate"),
    TotalScore("totalscore", "Total Score");

    companion object {
        /** The web Band page's default (Total Score, experimental ranks off). */
        val DEFAULT = TotalScore

        /**
         * Parse a `rankBy` value.
         *
         * @param wireId Value such as `fcrate`.
         * @return The metric, or null.
         */
        fun fromWireId(wireId: String?): BandRankingMetric? = entries.firstOrNull { it.wireId == wireId }
    }
}

// endregion

// region Player band group

/**
 * The player-bands `?group=` filter (web `PlayerBandListGroup`), distinct from [BandType].
 *
 * @property wireId Query value.
 * @property label Web filter label (`bandList.groups.*`).
 * @property bandType Band size the group narrows to, or null for every size.
 */
enum class PlayerBandGroup(val wireId: String, val label: String, val bandType: BandType?) {
    All("all", "All Bands", null),
    Duos("duos", "Duos", BandType.Duets),
    Trios("trios", "Trios", BandType.Trios),
    Quads("quads", "Quads", BandType.Quad),
    ;

    companion object {
        /**
         * The group for a route's `?group=` value; unknown or missing values mean [All] (web `parsePlayerBandListGroup`).
         *
         * @param wireId Query value.
         * @return Group.
         */
        fun fromWireId(wireId: String?): PlayerBandGroup = entries.firstOrNull { it.wireId == wireId } ?: All
    }
}

// endregion

// region Identity validation

/** Validation for band identities carried in routes and URLs. */
object BandText {
    private val memberPattern = Regex("^[A-Za-z0-9_-]{1,128}$")

    /** Longest team key accepted (four 128-character IDs plus separators). */
    const val MAX_TEAM_KEY = 600

    /**
     * Whether an account ID is safe for a URL segment: 1–128 of `[A-Za-z0-9_-]`
     * (Epic IDs are 32 hex digits; fixture services use synthetic `fixture-…` IDs).
     *
     * @param accountId Candidate ID.
     * @return True when safe.
     */
    fun isValidMemberId(accountId: String?): Boolean = accountId != null && memberPattern.matches(accountId)

    /**
     * Whether a team key is 1–4 `:`-joined safe account IDs (the service joins
     * sorted member IDs; fixtures use one synthetic segment).
     *
     * @param teamKey Candidate key.
     * @return True when safe to put in a URL.
     */
    fun isValidTeamKey(teamKey: String?): Boolean {
        if (teamKey.isNullOrEmpty() || teamKey.length > MAX_TEAM_KEY) return false
        val parts = teamKey.split(':')
        return parts.size in 1..4 && parts.all(::isValidMemberId)
    }
}

// endregion
