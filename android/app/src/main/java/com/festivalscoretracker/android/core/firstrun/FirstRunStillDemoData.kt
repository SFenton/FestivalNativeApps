package com.festivalscoretracker.android.core.firstrun

// region Still demo data

/**
 * One demo leaderboard player (web `demoData.ts` neighbourhood and rankings).
 *
 * @property rank Rank.
 * @property name Display name.
 * @property score Total score.
 * @property isPlayer The demo player ("You").
 */
data class FirstRunDemoPlayer(val rank: Int, val name: String, val score: Long, val isPlayer: Boolean = false)

/**
 * One demo song leaderboard entry (web `TopScoresDemo`).
 *
 * @property rank Rank.
 * @property name Display name.
 * @property score Score.
 * @property accuracy Accuracy percent.
 * @property fullCombo Full combo.
 * @property stars Stars (6 = gold).
 */
data class FirstRunDemoTopScore(val rank: Int, val name: String, val score: Int, val accuracy: Double, val fullCombo: Boolean, val stars: Int)

/**
 * One demo score-history entry (web `ScoreListDemo`/`ViewAllDemo`).
 *
 * @property daysAgo Days before today.
 * @property score Score.
 * @property accuracy Accuracy percent.
 * @property fullCombo Full combo.
 */
data class FirstRunDemoHistoryScore(val daysAgo: Long, val score: Long, val accuracy: Double, val fullCombo: Boolean = false)

/**
 * One demo statistics tile (web `OverviewDemo`/`DrillDownDemo` boxes).
 *
 * @property label Label.
 * @property value Value.
 * @property gold Gold value.
 * @property clickable Drills down (pulses in the drill-down demo).
 */
data class FirstRunDemoStat(val label: String, val value: String, val gold: Boolean = false, val clickable: Boolean = false)

/** Numbers for the still (non-rotating) first-run demos, from the web demos (issue #380). */
object FirstRunStillDemoData {
    /** Web `DEMO_RANKINGS` as scores. */
    val RANKINGS: List<FirstRunDemoPlayer> = FirstRunDemoPools.RANKINGS.map {
        FirstRunDemoPlayer(it.rank, it.name, it.rating.filter(Char::isDigit).toLong())
    }

    /** Web `YourRankDemo` neighbourhood: ranks 39–45 around the player at 42. */
    val NEIGHBOURHOOD: List<FirstRunDemoPlayer> = listOf(
        FirstRunDemoPlayer(39, "SonicRush", 1_278_400),
        FirstRunDemoPlayer(40, "DeepGroove", 1_265_100),
        FirstRunDemoPlayer(41, "KeyDrifter", 1_258_000),
        FirstRunDemoPlayer(42, "You", 1_250_000, isPlayer = true),
        FirstRunDemoPlayer(43, "DrumSurge", 1_241_300),
        FirstRunDemoPlayer(44, "ShredLord", 1_230_800),
        FirstRunDemoPlayer(45, "NoteCrush", 1_219_500),
    )

    /** Index of the player in [NEIGHBOURHOOD]. */
    val PLAYER_INDEX: Int = NEIGHBOURHOOD.indexOfFirst { it.isPlayer }

    /** Web `TopScoresDemo` Lead entries. */
    val TOP_SCORES: List<FirstRunDemoTopScore> = listOf(
        FirstRunDemoTopScore(1, "AceSolo", 486_500, 100.0, fullCombo = true, stars = 6),
        FirstRunDemoTopScore(2, "RiffMaster", 412_300, 98.0, fullCombo = false, stars = 5),
        FirstRunDemoTopScore(3, "ChordKing", 347_100, 97.0, fullCombo = false, stars = 5),
        FirstRunDemoTopScore(4, "PickSlayer", 289_600, 96.0, fullCombo = false, stars = 5),
    )

    /** Web `ScoreListDemo` scores, best (and newest) first. */
    val HISTORY: List<FirstRunDemoHistoryScore> = listOf(
        FirstRunDemoHistoryScore(0, 486_500, 100.0, fullCombo = true),
        FirstRunDemoHistoryScore(7, 412_300, 99.0),
        FirstRunDemoHistoryScore(21, 347_100, 97.0),
        FirstRunDemoHistoryScore(35, 289_600, 95.0),
        FirstRunDemoHistoryScore(56, 218_400, 88.0),
    )

    /** Web `OverviewDemo` summary boxes. */
    val OVERVIEW: List<FirstRunDemoStat> = listOf(
        FirstRunDemoStat("Songs Played", "142"),
        FirstRunDemoStat("Full Combos", "38 (26.8%)"),
        FirstRunDemoStat("Gold Stars", "12", gold = true),
        FirstRunDemoStat("Avg Accuracy", "96.2%"),
        FirstRunDemoStat("Best Rank", "#4"),
    )

    /** Web `DrillDownDemo` boxes; the clickable ones pulse. */
    val DRILL_DOWN: List<FirstRunDemoStat> = listOf(
        FirstRunDemoStat("Songs Played", "142", clickable = true),
        FirstRunDemoStat("Gold Stars", "12", gold = true),
        FirstRunDemoStat("Avg Accuracy", "96.2%"),
        FirstRunDemoStat("Full Combos", "38 (26.8%)", clickable = true),
    )

    /** Web `InstrumentBreakdownDemo` Lead cards (98 scores, 24 FCs, 8 gold, of 206 songs). */
    val BREAKDOWN: List<FirstRunDemoStat> = listOf(
        FirstRunDemoStat("Songs Played", "98 / 206"),
        FirstRunDemoStat("Full Combos", "24 (24.5%)"),
        FirstRunDemoStat("Gold Stars", "8", gold = true),
        FirstRunDemoStat("Avg Accuracy", "94.9%"),
    )

    /** Web `PercentileDemo` buckets: top percent to song count. */
    val PERCENTILES: List<Pair<Int, Int>> = listOf(1 to 3, 5 to 12, 10 to 28, 25 to 55, 50 to 89, 100 to 142)
}

// endregion
