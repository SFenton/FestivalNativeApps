package com.festivalscoretracker.android.core.notifications

import com.festivalscoretracker.android.core.model.Instrument

// region Engine types

/**
 * Full Combo / star state attached to a score event or the row's payload.
 *
 * @property oldFullCombo Previous Full Combo state.
 * @property newFullCombo New Full Combo state.
 * @property oldStars Previous stars.
 * @property newStars New stars (6 = gold).
 */
internal data class NotificationScoreResult(
    val oldFullCombo: Boolean? = null,
    val newFullCombo: Boolean? = null,
    val oldStars: Double? = null,
    val newStars: Double? = null,
) {
    /** Whether the state says anything about the play's result. */
    val hasResult: Boolean get() = newFullCombo != null || newStars != null
}

/**
 * One normalized event (web `NotificationTextEvent`, player fields only).
 *
 * @property eventKind Event kind.
 * @property instrument Chart (the row's chart when the event names none).
 * @property metric Raw metric.
 * @property oldNumeric Previous value.
 * @property newNumeric New value.
 * @property oldRank Previous rank.
 * @property newRank New rank.
 * @property oldLabel Previous value's display label (difficulty).
 * @property newLabel New value's display label (difficulty).
 * @property state Full Combo / star result carried by the event.
 */
internal data class NotificationTextEvent(
    val eventKind: String,
    val instrument: Instrument?,
    val metric: String? = null,
    val oldNumeric: Double? = null,
    val newNumeric: Double? = null,
    val oldRank: Double? = null,
    val newRank: Double? = null,
    val oldLabel: String? = null,
    val newLabel: String? = null,
    val state: NotificationScoreResult = NotificationScoreResult(),
) {
    /** Chart label, if any. */
    val instrumentLabel: String? get() = instrument?.label
}

/**
 * The formatter input (web `NotificationTextInput`, player fields only).
 *
 * @property eventKind Row event kind.
 * @property instrument Row chart.
 * @property instrumentLabel Row chart label (rescoped by multi-chart clauses).
 * @property scopeLabel Web `scopeLabel`: the row's own chart label for a player feed.
 * @property metric Row metric.
 * @property oldNumeric Row previous value.
 * @property newNumeric Row new value.
 * @property oldRank Row previous rank.
 * @property newRank Row new rank.
 * @property songTitle Catalogue song title.
 * @property title Fallback title.
 * @property payloadState Top-level payload Full Combo / star state.
 * @property events Normalized events.
 */
internal data class NotificationTextInput(
    val eventKind: String,
    val instrument: Instrument? = null,
    val instrumentLabel: String? = null,
    val scopeLabel: String? = null,
    val metric: String? = null,
    val oldNumeric: Double? = null,
    val newNumeric: Double? = null,
    val oldRank: Double? = null,
    val newRank: Double? = null,
    val songTitle: String? = null,
    val title: String? = null,
    val payloadState: NotificationScoreResult = NotificationScoreResult(),
    val events: List<NotificationTextEvent> = emptyList(),
)

/**
 * Display output before row metadata is attached.
 *
 * @property title Title.
 * @property message Plain message; statement-style rows separate clauses with blank lines.
 * @property messageParts [message] split into plain and bold runs.
 * @property flags Unique flags in event priority order.
 * @property flagGroups Per-chart flags for multi-chart song rows.
 */
internal data class NotificationTextResult(
    val title: String,
    val message: String,
    val messageParts: List<NotificationMessagePart>,
    val flags: List<NotificationFlagKind>,
    val flagGroups: List<NotificationFlagGroup>,
)

/** A message clause and the terms to bold within it. */
private data class NotificationClause(val text: String, val emphasisTerms: List<String>)

/** Interpolation values for one event (web `buildValues`, player fields only). */
private data class NotificationTextValues(
    val song: String,
    val newScore: String,
    val oldScore: String,
    val oldRank: String,
    val newRank: String,
    val oldStars: String,
    val newStars: String,
    val oldDifficulty: String,
    val newDifficulty: String,
    val oldCount: String,
    val newCount: String,
    val instrument: String,
    val scope: String,
)

// endregion

// region Engine

/**
 * Port of the player-scoped web `formatNotificationPresentation` (`notificationText.ts`, English
 * copy from `en.json`), following the Apple port (`NotificationPresentation.swift`, issue #76):
 * coalesced events, derived Full Combo / gold-star results, redundant star events dropped,
 * priority order, statement-style rows (instrument aggregates, several rank updates, several
 * charts), emphasis runs, flags and per-chart flag groups. Band and combo copy is not ported.
 */
internal object NotificationTextEngine {
    /**
     * Format a non-shop row.
     *
     * @param input Normalized row.
     * @return Title, message, emphasis runs, flags and flag groups.
     */
    fun present(input: NotificationTextInput): NotificationTextResult {
        val events = displayEvents(input)
        val title = title(input, events)
        val statementStyle = isPlayerInstrumentAggregate(events) || isMultiAggregateRank(events) || isMultiInstrumentPlayerSong(events)
        val clauses = clauses(input, events).filter { it.text.isNotEmpty() }
        val texts = clauses.map { it.text }
        val message = when {
            texts.isEmpty() -> Copy.UNKNOWN
            statementStyle -> texts.joinToString("\n\n")
            else -> Copy.sentence(texts)
        }
        val parts = if (clauses.isEmpty()) listOf(NotificationMessagePart(message)) else emphasize(message, clauses.flatMap { it.emphasisTerms })
        return NotificationTextResult(title, message, parts, uniqueFlags(events.map { it.eventKind }), flagGroups(events))
    }

    // region Events

    /** Port of `getDisplayEvents`: derive score results, drop redundant stars, sort by priority (stable). */
    fun displayEvents(input: NotificationTextInput): List<NotificationTextEvent> =
        removeRedundantStarEvents(withDerivedScoreResultEvents(input, input.events)).sortedBy { priority(it.eventKind) }

    private fun withDerivedScoreResultEvents(input: NotificationTextInput, events: List<NotificationTextEvent>): List<NotificationTextEvent> {
        val fullComboKeys = events.filter { it.eventKind == Kinds.FULL_COMBO }.map { statusKey(input, it) }.toMutableSet()
        val goldKeys = events.filter { it.eventKind == Kinds.GOLD_STARS }.map { statusKey(input, it) }.toMutableSet()
        val multiInstrument = isMultiInstrumentPlayerSong(events)
        val derived = mutableListOf<NotificationTextEvent>()
        events.filter { it.eventKind in Kinds.scoreResult }.forEach { event ->
            val state = scoreResultState(input, events, event, multiInstrument) ?: return@forEach
            val key = statusKey(input, event)
            if (state.newFullCombo == true && fullComboKeys.add(key)) {
                derived += derivedEvent(input, event, Kinds.FULL_COMBO, "full_combo", state)
            }
            val stars = state.newStars
            if (stars != null && stars >= 6 && goldKeys.add(key)) {
                derived += derivedEvent(input, event, Kinds.GOLD_STARS, "stars", state)
            }
        }
        return events + derived
    }

    private fun scoreResultState(
        input: NotificationTextInput, events: List<NotificationTextEvent>, event: NotificationTextEvent, multiInstrument: Boolean,
    ): NotificationScoreResult? {
        if (event.state.hasResult) return event.state
        if (multiInstrument && !eventMatchesTopLevel(input, event)) return null
        if (!topLevelPayloadBelongs(input, events, event)) return null
        return input.payloadState.takeIf { it.hasResult }
    }

    private fun topLevelPayloadBelongs(input: NotificationTextInput, events: List<NotificationTextEvent>, event: NotificationTextEvent): Boolean {
        val scoreEvents = events.count { it.eventKind in Kinds.scoreResult }
        if (scoreEvents != 1 && !eventMatchesTopLevel(input, event)) return false
        val eventInstrument = event.instrument ?: return true
        val inputInstrument = input.instrument ?: return true
        return eventInstrument == inputInstrument
    }

    private fun eventMatchesTopLevel(input: NotificationTextInput, event: NotificationTextEvent): Boolean {
        if (event.eventKind != input.eventKind) return false
        val inputInstrument = input.instrument ?: return false
        if (event.instrument != inputInstrument) return false
        return matches(input.metric, event.metric) && matches(input.oldNumeric, event.oldNumeric) &&
            matches(input.newNumeric, event.newNumeric) && matches(input.oldRank, event.oldRank) && matches(input.newRank, event.newRank)
    }

    private fun <T> matches(left: T?, right: T?): Boolean = left == null || right == null || left == right

    private fun derivedEvent(
        input: NotificationTextInput, source: NotificationTextEvent, kind: String, metric: String, state: NotificationScoreResult,
    ): NotificationTextEvent = NotificationTextEvent(
        eventKind = kind,
        instrument = source.instrument ?: input.instrument,
        metric = metric,
        oldNumeric = if (metric == "stars") state.oldStars else null,
        newNumeric = if (metric == "stars") state.newStars else null,
    )

    private fun statusKey(input: NotificationTextInput, event: NotificationTextEvent): String = (event.instrument ?: input.instrument)?.wireId.orEmpty()

    private fun removeRedundantStarEvents(events: List<NotificationTextEvent>): List<NotificationTextEvent> {
        val goldKeys = events.filter { it.eventKind == Kinds.GOLD_STARS }.map { it.instrument?.wireId.orEmpty() }.toSet()
        return events.filterNot { it.eventKind == "player_stars_improved" && it.instrument?.wireId.orEmpty() in goldKeys }
    }

    // endregion

    // region Classification

    private fun isPlayerInstrumentAggregate(events: List<NotificationTextEvent>): Boolean {
        val aggregate = events.filter { it.eventKind in Kinds.instrumentAggregate }
        return aggregate.size > 1 && aggregate.size == events.size && aggregate.any { it.eventKind in Kinds.instrumentAggregateProgress }
    }

    private fun isMultiAggregateRank(events: List<NotificationTextEvent>): Boolean = events.count { it.eventKind in Copy.rankNames } > 1

    private fun isMultiInstrumentPlayerSong(events: List<NotificationTextEvent>): Boolean =
        events.filter { it.eventKind in Kinds.playerSong }.mapNotNull { it.instrumentLabel }.toSet().size > 1

    // endregion

    // region Title

    private fun title(input: NotificationTextInput, events: List<NotificationTextEvent>): String {
        val baseTitle = input.songTitle ?: input.title
        val instrumentLabel = input.instrumentLabel?.trim()?.takeIf { it.isNotEmpty() }
        if (baseTitle != null && isMultiInstrumentPlayerSong(events)) return baseTitle
        if (baseTitle != null && instrumentLabel != null && events.any { it.eventKind in Kinds.playerSong }) return "$baseTitle · $instrumentLabel"
        if (isPlayerInstrumentAggregate(events)) return (instrumentLabel ?: input.scopeLabel)?.let { "$it · Improvements" } ?: "Instrument Updates"
        val rankEvents = events.filter { it.eventKind in Copy.rankNames }
        if (rankEvents.size > 1) return (instrumentLabel ?: input.scopeLabel)?.let { "Rank Updates · $it" } ?: "Rank Updates"
        rankEvents.firstOrNull()?.let { return "${Copy.rankNames.getValue(it.eventKind)} Improved" }
        events.firstNotNullOfOrNull { Copy.progressTitles[it.eventKind] }?.let { return it }
        return input.title ?: input.songTitle ?: "Notification"
    }

    // endregion

    // region Clauses

    private fun clauses(input: NotificationTextInput, events: List<NotificationTextEvent>): List<NotificationClause> = when {
        isPlayerInstrumentAggregate(events) -> instrumentAggregateClauses(events)
        isMultiAggregateRank(events) -> rankUpdateClauses(events)
        isMultiInstrumentPlayerSong(events) -> multiInstrumentSongClauses(input, events)
        else -> events.flatMapIndexed { index, event -> eventClauses(input, event, primary = index == 0) }
    }

    private fun rankUpdateClauses(events: List<NotificationTextEvent>): List<NotificationClause> = events.mapNotNull { event ->
        val rank = Copy.rankNames[event.eventKind] ?: return@mapNotNull null
        val oldRank = formatRank(event.oldRank)
        val newRank = formatRank(event.newRank)
        NotificationClause("For $rank, moved from $oldRank to $newRank.", filterEmphasis(listOf(rank, oldRank, newRank)))
    }

    private fun instrumentAggregateClauses(events: List<NotificationTextEvent>): List<NotificationClause> {
        val byKind = events.associateBy { it.eventKind }
        val clauses = listOfNotNull(
            totalScoreAggregateClause(byKind),
            fullComboAggregateClause(byKind),
            aggregateRankClause(byKind["player_skill_rank_improved"], AggregateRank.Skill),
            aggregateRankClause(byKind["player_weighted_rank_improved"], AggregateRank.Weighted),
            aggregateRankClause(byKind["player_max_score_rank_improved"], AggregateRank.MaxScore),
        )
        if (clauses.isNotEmpty()) return clauses
        return events.flatMapIndexed { index, event -> eventClauses(NotificationTextInput(event.eventKind), event, primary = index == 0) }
    }

    private fun totalScoreAggregateClause(byKind: Map<String, NotificationTextEvent>): NotificationClause? {
        val valueEvent = byKind["player_total_score_improved"]
        val rankEvent = byKind["player_total_score_rank_improved"]
        val newScore = NotificationText.number(valueEvent?.newNumeric, Copy.Fallback.SCORE)
        val oldRank = formatRank(rankEvent?.oldRank)
        val newRank = formatRank(rankEvent?.newRank)
        return when {
            valueEvent != null && rankEvent != null -> NotificationClause(
                "Your total score increased to $newScore points and your total score rank moved up from $oldRank to $newRank.",
                filterEmphasis(listOf(newScore, "total score rank", oldRank, newRank)),
            )
            valueEvent != null -> NotificationClause("Your total score increased to $newScore points.", filterEmphasis(listOf(newScore)))
            else -> aggregateRankClause(rankEvent, AggregateRank.TotalScore)
        }
    }

    private fun fullComboAggregateClause(byKind: Map<String, NotificationTextEvent>): NotificationClause? {
        val countEvent = byKind["player_fc_count_improved"]
        val rankEvent = byKind["player_fc_rate_rank_improved"]
        val newCount = NotificationText.number(countEvent?.newNumeric, Copy.Fallback.COUNT)
        val oldRank = formatRank(rankEvent?.oldRank)
        val newRank = formatRank(rankEvent?.newRank)
        return when {
            countEvent != null && rankEvent != null -> NotificationClause(
                "Your Full Combo count increased to $newCount and your Full Combo percentage rank moved up from $oldRank to $newRank.",
                filterEmphasis(listOf(newCount, "Full Combo percentage rank", oldRank, newRank)),
            )
            countEvent != null -> NotificationClause("Your Full Combo count increased to $newCount.", filterEmphasis(listOf(newCount)))
            else -> aggregateRankClause(rankEvent, AggregateRank.FullCombo)
        }
    }

    /** `notifications.copy.instrumentAggregate.*Rank` statements and their bold rank names. */
    private enum class AggregateRank(val subject: String, val emphasis: String = subject) {
        TotalScore("total score rank"),
        FullCombo("Full Combo percentage rank"),
        Skill("adjusted percentile rank"),
        Weighted("percentile rank, weighted by number of entries,", "percentile rank, weighted by number of entries"),
        MaxScore("max score rank"),
    }

    private fun aggregateRankClause(event: NotificationTextEvent?, rank: AggregateRank): NotificationClause? {
        event ?: return null
        val oldRank = formatRank(event.oldRank)
        val newRank = formatRank(event.newRank)
        return NotificationClause("Your ${rank.subject} moved up from $oldRank to $newRank.", filterEmphasis(listOf(rank.emphasis, oldRank, newRank)))
    }

    private fun multiInstrumentSongClauses(input: NotificationTextInput, events: List<NotificationTextEvent>): List<NotificationClause> =
        groupedInstrumentEvents(events).map { (label, groupEvents) ->
            val scoped = input.copy(instrumentLabel = label)
            val details = groupEvents.flatMap { eventClauses(scoped, it, primary = false) }
            val updates = Copy.fragment(details.map { it.text })
            NotificationClause("For $label, $updates.", filterEmphasis(listOf(label) + details.flatMap { it.emphasisTerms }))
        }

    private fun groupedInstrumentEvents(events: List<NotificationTextEvent>): List<Pair<String, List<NotificationTextEvent>>> {
        val groups = LinkedHashMap<String, MutableList<NotificationTextEvent>>()
        events.filter { it.eventKind in Kinds.playerSong }.forEach { event ->
            val label = event.instrumentLabel ?: return@forEach
            groups.getOrPut(label) { mutableListOf() } += event
        }
        return groups.map { (label, groupEvents) -> label to groupEvents.sortedBy { priority(it.eventKind) } }
            .sortedBy { (label, _) -> labelOrder(label) }
    }

    private fun labelOrder(label: String): Int = Instrument.entries.indexOfFirst { it.label == label }.takeIf { it >= 0 } ?: 1000

    private fun eventClauses(input: NotificationTextInput, event: NotificationTextEvent, primary: Boolean): List<NotificationClause> {
        val values = buildValues(input, event)
        val text = (if (primary) Copy.primary(event.eventKind, values) else Copy.detail(event.eventKind, values)) ?: return emptyList()
        val clause = NotificationClause(text, emphasisTerms(event, values))
        if (primary && event.eventKind == "player_first_score") {
            return listOf(clause, NotificationClause("started at ${values.newRank}", filterEmphasis(listOf(values.newRank))))
        }
        return listOf(clause)
    }

    private fun buildValues(input: NotificationTextInput, event: NotificationTextEvent): NotificationTextValues = NotificationTextValues(
        song = input.songTitle ?: input.title ?: Copy.Fallback.SONG,
        newScore = NotificationText.number(event.newNumeric, Copy.Fallback.SCORE),
        oldScore = NotificationText.number(event.oldNumeric, Copy.Fallback.SCORE),
        oldRank = formatRank(event.oldRank),
        newRank = formatRank(event.newRank),
        oldStars = NotificationText.number(event.oldNumeric, Copy.Fallback.STARS),
        newStars = NotificationText.number(event.newNumeric, Copy.Fallback.STARS),
        oldDifficulty = event.oldLabel ?: NotificationText.number(event.oldNumeric, Copy.Fallback.DIFFICULTY),
        newDifficulty = event.newLabel ?: NotificationText.number(event.newNumeric, Copy.Fallback.DIFFICULTY),
        oldCount = NotificationText.number(event.oldNumeric, Copy.Fallback.COUNT),
        newCount = NotificationText.number(event.newNumeric, Copy.Fallback.COUNT),
        instrument = event.instrumentLabel ?: input.instrumentLabel ?: Copy.Fallback.INSTRUMENT,
        scope = input.scopeLabel ?: input.instrumentLabel ?: Copy.Fallback.RANKINGS,
    )

    private fun emphasisTerms(event: NotificationTextEvent, values: NotificationTextValues): List<String> {
        val terms = mutableListOf(
            values.newScore, values.oldScore, values.oldRank, values.newRank, values.oldDifficulty, values.newDifficulty,
            values.oldCount, values.newCount, values.instrument, Copy.Fallback.COMBO, values.scope,
        )
        if (event.eventKind in Kinds.playerSong) terms += values.song
        when (event.eventKind) {
            Kinds.GOLD_STARS -> terms += listOf("Gold Stars", "gold stars")
            Kinds.FULL_COMBO -> terms += "Full Combo"
            "player_stars_improved" -> terms += "${values.oldStars} to ${values.newStars} stars"
        }
        return filterEmphasis(terms)
    }

    // endregion

    // region Emphasis

    /** Port of `filterEmphasisTerms`: trimmed, non-fallback, unique, longest first (stable). */
    fun filterEmphasis(terms: List<String?>): List<String> =
        terms.mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }.filter { it !in Copy.Fallback.all }.distinct().sortedByDescending { it.length }

    /**
     * Port of `emphasizeText`: bold the first (longest) candidate starting at each position,
     * scanning left to right, merging adjacent runs of the same weight.
     *
     * @param text Final message.
     * @param terms Candidate terms from every clause.
     * @return Runs that concatenate back to [text].
     */
    fun emphasize(text: String, terms: List<String>): List<NotificationMessagePart> {
        val candidates = filterEmphasis(terms).filter { it in text }
        if (candidates.isEmpty()) return listOf(NotificationMessagePart(text))
        val parts = mutableListOf<NotificationMessagePart>()
        fun append(chunk: String, emphasis: Boolean) {
            val last = parts.lastOrNull()
            if (last != null && last.emphasis == emphasis) parts[parts.lastIndex] = last.copy(text = last.text + chunk)
            else parts += NotificationMessagePart(chunk, emphasis)
        }
        var index = 0
        while (index < text.length) {
            val term = candidates.firstOrNull { text.startsWith(it, index) }
            if (term != null) {
                append(term, true)
                index += term.length
            } else {
                append(text[index].toString(), false)
                index += 1
            }
        }
        return parts
    }

    // endregion

    // region Flags

    private fun uniqueFlags(eventKinds: List<String>): List<NotificationFlagKind> = eventKinds.map(NotificationFlagKind::forEventKind).distinct()

    private fun flagGroups(events: List<NotificationTextEvent>): List<NotificationFlagGroup> {
        if (!isMultiInstrumentPlayerSong(events)) return emptyList()
        return groupedInstrumentEvents(events).mapNotNull { (label, groupEvents) ->
            val instrument = groupEvents.firstNotNullOfOrNull { it.instrument } ?: Instrument.entries.firstOrNull { it.label == label } ?: return@mapNotNull null
            val flags = uniqueFlags(groupEvents.map { it.eventKind })
            flags.takeIf { it.isNotEmpty() }?.let { NotificationFlagGroup(instrument, label, it) }
        }
    }

    // endregion

    private fun formatRank(rank: Double?): String = rank?.let { "#" + NotificationText.number(it, Copy.Fallback.RANK) } ?: Copy.Fallback.RANK

    private fun priority(eventKind: String): Int = Kinds.priority[eventKind] ?: 1000
}

// endregion

// region Copy (en.json)

/** Player-scoped `notifications.*` copy from `FortniteFestivalWeb/src/i18n/en.json`. */
private object Copy {
    const val UNKNOWN = "New improvement detected."

    /** `notifications.values.*` fallbacks; none of them is ever bolded. */
    object Fallback {
        const val SONG = "this song"
        const val SCORE = "a new score"
        const val RANK = "your new rank"
        const val STARS = "more"
        const val DIFFICULTY = "a higher difficulty"
        const val COUNT = "more"
        const val INSTRUMENT = "this instrument"
        const val COMBO = "this combo"
        const val RANKINGS = "these rankings"
        val all = setOf(SONG, SCORE, RANK, STARS, DIFFICULTY, INSTRUMENT, COMBO, RANKINGS)
    }

    val rankNames = mapOf(
        "player_weighted_rank_improved" to "Weighted Percentile Rank",
        "player_skill_rank_improved" to "Adjusted Percentile Rank",
        "player_total_score_rank_improved" to "Total Score Rank",
        "player_fc_rate_rank_improved" to "Full Combo Rank",
        "player_max_score_rank_improved" to "Max Score % Rank",
    )

    val progressTitles = mapOf(
        "player_total_score_improved" to "Total Score Improved",
        "player_fc_count_improved" to "Full Combo Count Improved",
    )

    /** `notifications.copy.primary.*` for player event kinds, or null for a kind without primary copy. */
    fun primary(kind: String, v: NotificationTextValues): String? = when (kind) {
        "player_first_score" -> "Your first ${v.instrument} play on ${v.song} scored ${v.newScore} points"
        "player_score_pb" -> "You set a new personal best on ${v.instrument} for ${v.song} with ${v.newScore} points"
        "player_song_rank_improved" -> "You climbed from ${v.oldRank} to ${v.newRank} on ${v.instrument} for ${v.song}"
        "player_stars_improved" -> "You improved from ${v.oldStars} to ${v.newStars} stars on ${v.instrument} for ${v.song}"
        "player_gold_stars_achieved" -> "You earned gold stars on ${v.instrument} for ${v.song}"
        "player_fc_achieved" -> "You got a Full Combo on ${v.instrument} for ${v.song}"
        "player_difficulty_bumped" -> "You improved your difficulty on ${v.instrument} for ${v.song} from ${v.oldDifficulty} to ${v.newDifficulty}"
        "player_weighted_rank_improved" -> "You moved up from ${v.oldRank} to ${v.newRank} in ${v.instrument} percentile rankings, weighted by number of entries"
        "player_skill_rank_improved" -> "You moved up from ${v.oldRank} to ${v.newRank} in ${v.instrument} adjusted percentile rankings"
        "player_total_score_rank_improved" -> "You moved up from ${v.oldRank} to ${v.newRank} in ${v.instrument} total score rankings"
        "player_fc_rate_rank_improved" -> "You moved up from ${v.oldRank} to ${v.newRank} in ${v.instrument} Full Combo rankings"
        "player_max_score_rank_improved" -> "You moved up from ${v.oldRank} to ${v.newRank} in ${v.instrument} max score rankings"
        "player_total_score_improved" -> "Your ${v.instrument} total score increased to ${v.newScore} points"
        "player_fc_count_improved" -> "Your ${v.instrument} Full Combo count increased to ${v.newCount}"
        else -> null
    }

    /** `notifications.copy.detail.*` for player song event kinds, or null for a kind without detail copy. */
    fun detail(kind: String, v: NotificationTextValues): String? = when (kind) {
        "player_first_score" -> "your first play scored ${v.newScore} points and started at ${v.newRank}"
        "player_score_pb" -> "your play set a new personal best with ${v.newScore} points"
        "player_song_rank_improved" -> "climbed from ${v.oldRank} to ${v.newRank}"
        "player_stars_improved" -> "improved from ${v.oldStars} to ${v.newStars} stars"
        "player_gold_stars_achieved" -> "earned gold stars"
        "player_fc_achieved" -> "got a Full Combo"
        "player_difficulty_bumped" -> "improved difficulty from ${v.oldDifficulty} to ${v.newDifficulty}"
        else -> null
    }

    /** `notifications.copy.join.*`. */
    fun sentence(clauses: List<String>): String = when (clauses.size) {
        1 -> "${clauses[0]}."
        2 -> "${clauses[0]} and ${clauses[1]}."
        else -> "${clauses.dropLast(1).joinToString(", ")}, and ${clauses.last()}."
    }

    /** `notifications.copy.joinFragment.*`. */
    fun fragment(clauses: List<String>): String = when (clauses.size) {
        0 -> UNKNOWN
        1 -> clauses[0]
        2 -> "${clauses[0]} and ${clauses[1]}"
        else -> "${clauses.dropLast(1).joinToString(", ")}, and ${clauses.last()}"
    }
}

// endregion

// region Event kinds

private object Kinds {
    const val FULL_COMBO = "player_fc_achieved"
    const val GOLD_STARS = "player_gold_stars_achieved"

    val priority = mapOf(
        "service_new_shop_song" to 5, "player_first_score" to 10, "player_score_pb" to 20,
        FULL_COMBO to 30, GOLD_STARS to 40, "player_stars_improved" to 50,
        "player_song_rank_improved" to 60, "player_difficulty_bumped" to 70,
        "player_total_score_improved" to 75, "player_fc_count_improved" to 76,
        "player_total_score_rank_improved" to 80, "player_skill_rank_improved" to 90,
        "player_weighted_rank_improved" to 100, "player_fc_rate_rank_improved" to 110,
        "player_max_score_rank_improved" to 120,
    )

    val scoreResult = setOf("player_first_score", "player_score_pb")

    val playerSong = setOf(
        "player_first_score", "player_score_pb", "player_song_rank_improved", "player_stars_improved",
        GOLD_STARS, FULL_COMBO, "player_difficulty_bumped",
    )

    val instrumentAggregateProgress = setOf("player_total_score_improved", "player_fc_count_improved")

    val instrumentAggregate = setOf(
        "player_total_score_improved", "player_total_score_rank_improved", "player_fc_count_improved",
        "player_fc_rate_rank_improved", "player_skill_rank_improved", "player_weighted_rank_improved",
        "player_max_score_rank_improved",
    )
}

// endregion
