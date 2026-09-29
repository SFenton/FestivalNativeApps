package com.festivalscoretracker.android.core.notifications

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import java.text.NumberFormat
import java.time.Instant
import java.util.Locale
import kotlinx.serialization.Serializable

// region Wire

/**
 * One coalesced sub-event (web `NotificationTextEvent`, typed subset).
 *
 * @property eventKind Event kind.
 * @property instrument Service instrument key.
 * @property metric Raw metric.
 */
@Serializable
data class NotificationEventPayload(val eventKind: String? = null, val instrument: String? = null, val metric: String? = null)

/**
 * Typed subset of the notification `payload` object.
 *
 * @property coalescedEvents Coalesced sub-events.
 * @property coalescedInstruments Every chart the coalesced row touches.
 * @property songTitle Shop song title (`service_new_shop_song` has no account).
 * @property artist Shop song artist.
 * @property albumArt Shop song art reference.
 */
@Serializable
data class NotificationPayload(
    val coalescedEvents: List<NotificationEventPayload>? = null,
    val coalescedInstruments: List<String>? = null,
    val songTitle: String? = null,
    val artist: String? = null,
    val albumArt: String? = null,
)

/**
 * One notification (service `ImprovementNotificationDto`).
 *
 * @property eventId Event ID.
 * @property notificationGuid Stable notification ID.
 * @property accountId Account, absent for service notifications.
 * @property eventKind Event kind.
 * @property songId Song.
 * @property instrument Service instrument key.
 * @property metric Raw metric.
 * @property oldNumeric Previous value.
 * @property newNumeric New value.
 * @property oldRank Previous rank.
 * @property newRank New rank.
 * @property payload Coalesced events or shop-song details.
 * @property detectedAt ISO-8601 detection time.
 * @property expiresAt ISO-8601 expiry time.
 */
@Serializable
data class ImprovementNotification(
    val eventId: Long = 0,
    val notificationGuid: String = "",
    val accountId: String? = null,
    val eventKind: String = "",
    val songId: String? = null,
    val instrument: String? = null,
    val metric: String? = null,
    val oldNumeric: Double? = null,
    val newNumeric: Double? = null,
    val oldRank: Int? = null,
    val newRank: Int? = null,
    val payload: NotificationPayload? = null,
    val detectedAt: String? = null,
    val expiresAt: String? = null,
) {
    /** Parsed chart, if any. */
    val parsedInstrument: Instrument? get() = Instrument.fromWireId(instrument)

    /** Parsed detection time (epoch when missing or malformed, so it sorts last). */
    val detectedInstant: Instant get() = detectedAt?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: Instant.EPOCH
}

/**
 * `GET /api/player/{accountId}/notifications` envelope.
 *
 * @property generatedAt Generation time.
 * @property expiresAfterHours Retention window.
 * @property sourceRunId Detection run that produced the feed.
 * @property sourceCompletedAt When that run completed.
 * @property notificationsGenerated Explicit generated flag.
 * @property items Rows.
 */
@Serializable
data class NotificationsEnvelope(
    val generatedAt: String? = null,
    val expiresAfterHours: Double = 0.0,
    val sourceRunId: Long? = null,
    val sourceCompletedAt: String? = null,
    val notificationsGenerated: Boolean? = null,
    val items: List<ImprovementNotification>? = null,
) {
    /** Whether a detection run ever produced this feed ("generated but empty" differs from "never generated"). */
    val isGenerated: Boolean
        get() = notificationsGenerated ?: (sourceRunId != null || sourceCompletedAt != null || !items.isNullOrEmpty())

    /**
     * Reject malformed rows (unsafe or duplicate GUIDs, missing kinds, unsafe song IDs).
     *
     * @param limit Requested row cap.
     * @throws FestivalApiException.InvalidResponse when malformed.
     */
    fun validate(limit: Int) {
        val rows = items ?: throw FestivalApiException.InvalidResponse()
        if (rows.size > limit) throw FestivalApiException.InvalidResponse()
        val seen = HashSet<String>()
        rows.forEach { item ->
            val guidOk = item.notificationGuid.length in 1..64 && seen.add(item.notificationGuid) && isSafe(item.notificationGuid)
            val kindOk = item.eventKind.length in 1..80
            val songOk = item.songId == null || (item.songId.length in 1..200 && isSafe(item.songId))
            if (!guidOk || !kindOk || !songOk) throw FestivalApiException.InvalidResponse()
        }
    }

    private fun isSafe(text: String): Boolean = text.none { it.isISOControl() || it == '/' || it == '\\' }
}

// endregion

// region Destination

/** Where a notification row navigates (web `getNotificationDestination`, player feed). */
sealed interface NotificationDestination {
    /**
     * Song Detail.
     *
     * @property songId Song.
     * @property instrument Chart when the row concerns exactly one instrument.
     */
    data class Song(val songId: String, val instrument: Instrument?) : NotificationDestination

    /**
     * Rankings: full rankings for one instrument, else the Leaderboards hub (web `/leaderboards?rankBy=`).
     *
     * @property rankBy Ranking metric.
     * @property instrument Chart, or null for the hub.
     */
    data class Rankings(val rankBy: String, val instrument: Instrument?) : NotificationDestination
}

/** Destination and ranking-metric rules (web `notificationDestination.ts`, `notificationRanking.ts`). */
object NotificationRouting {
    private val songEventKinds = setOf(
        "service_new_shop_song", "player_first_score", "player_score_pb", "player_song_rank_improved", "player_stars_improved",
        "player_gold_stars_achieved", "player_fc_achieved", "player_difficulty_bumped",
    )

    private val metricByEventKind = mapOf(
        "player_weighted_rank_improved" to "weighted",
        "player_skill_rank_improved" to "adjusted",
        "player_total_score_rank_improved" to "totalscore",
        "player_fc_rate_rank_improved" to "fcrate",
        "player_max_score_rank_improved" to "maxscore",
    )

    private val metricByMetric = mapOf(
        "weighted_rank" to "weighted",
        "skill_rank" to "adjusted",
        "adjusted_skill_rank" to "adjusted",
        "total_score_rank" to "totalscore",
        "fc_rate_rank" to "fcrate",
        "max_score_rank" to "maxscore",
        "max_score_percent_rank" to "maxscore",
        "composite_rank" to "adjusted",
        "composite_rank_weighted" to "weighted",
        "composite_rank_total_score" to "totalscore",
        "composite_rank_fc_rate" to "fcrate",
        "composite_rank_max_score" to "maxscore",
    )

    /**
     * Rank By metric for an event (kind first, then the raw metric).
     *
     * @param eventKind Event kind.
     * @param metric Raw metric.
     * @return Metric, or null for non-rank events.
     */
    fun rankingMetric(eventKind: String?, metric: String?): String? =
        eventKind?.trim()?.let(metricByEventKind::get) ?: metric?.trim()?.let(metricByMetric::get)

    /**
     * Resolve a row's destination.
     *
     * @param item Notification.
     * @return Destination, or null (aggregate improvements have none).
     */
    fun destination(item: ImprovementNotification): NotificationDestination? {
        val events = events(item)
        val songId = item.songId
        if (!songId.isNullOrEmpty() && events.any { it.eventKind in songEventKinds }) {
            val instruments = events.mapNotNull { it.instrument?.takeIf(String::isNotEmpty) }.distinct().size
            return NotificationDestination.Song(songId, if (instruments > 1) null else item.parsedInstrument)
        }
        events.forEach { event ->
            rankingMetric(event.eventKind, event.metric)?.let { rankBy ->
                return NotificationDestination.Rankings(rankBy, Instrument.fromWireId(event.instrument))
            }
        }
        return null
    }

    /**
     * The row's events: coalesced payload events, else the row itself.
     *
     * @param item Notification.
     * @return Events.
     */
    fun events(item: ImprovementNotification): List<NotificationEventPayload> =
        item.payload?.coalescedEvents?.filter { !it.eventKind.isNullOrEmpty() }?.takeIf { it.isNotEmpty() }
            ?: listOf(NotificationEventPayload(item.eventKind, item.instrument, item.metric))
}

// endregion

// region Media

/**
 * The 64 dp leading media of a row (web `NotificationMedia`, player feed): album art when the
 * catalogue resolves the song, art over a small instrument grid when the row touches several
 * charts, else the chart's instrument icon. Combo media (band/combo rankings) is not used by
 * the player feed natives read.
 */
sealed interface NotificationMedia {
    /**
     * Album art only.
     *
     * @property artUrl Absolute artwork URL.
     */
    data class Song(val artUrl: String) : NotificationMedia

    /**
     * Album art above a two-column grid of the affected instruments.
     *
     * @property artUrl Absolute artwork URL.
     * @property instruments Affected charts in canonical order.
     */
    data class SongInstrumentGrid(val artUrl: String, val instruments: List<Instrument>) : NotificationMedia {
        /** TalkBack label ("Affected instruments: Lead, Bass"). */
        val label: String get() = "Affected instruments: " + instruments.joinToString(", ") { it.label }
    }

    /**
     * One instrument icon (no resolved art).
     *
     * @property instrument Chart (Lead when the row names none, like the web).
     */
    data class SoloInstrument(val instrument: Instrument) : NotificationMedia
}

/** Media rules (web `useProfileNotificationsFeed.notificationMedia` / shop-song mapping). */
object NotificationMediaRules {
    /**
     * Charts a row touches: `coalescedInstruments`, the coalesced events' charts and the row's
     * own, deduplicated in canonical chart order (web `notificationSurfaceInstruments`).
     *
     * @param item Notification.
     * @return Instruments.
     */
    fun surfaceInstruments(item: ImprovementNotification): List<Instrument> {
        val keys = item.payload?.coalescedInstruments.orEmpty() +
            NotificationRouting.events(item).mapNotNull { it.instrument } + listOfNotNull(item.instrument)
        val present = keys.mapNotNull(Instrument::fromWireId).toSet()
        return Instrument.entries.filter { it in present }
    }

    /**
     * The row's media.
     *
     * @param item Notification.
     * @param artUrl Resolved absolute album-art URL (catalogue first, shop payload second), if any.
     * @return Media.
     */
    fun media(item: ImprovementNotification, artUrl: String?): NotificationMedia {
        val art = artUrl?.takeIf { it.isNotBlank() }
        if (item.eventKind == "service_new_shop_song") {
            return art?.let(NotificationMedia::Song) ?: NotificationMedia.SoloInstrument(Instrument.Lead)
        }
        val instruments = surfaceInstruments(item)
        return when {
            art != null && instruments.size > 1 -> NotificationMedia.SongInstrumentGrid(art, instruments)
            art != null -> NotificationMedia.Song(art)
            else -> NotificationMedia.SoloInstrument(item.parsedInstrument ?: Instrument.Lead)
        }
    }
}

// endregion

// region Text

/** Flag kinds and their web labels (`notifications.flags.*`); colours live in the UI. */
enum class NotificationFlagKind(val label: String) {
    Improvement("Improvement"),
    FirstPlay("First Play"),
    NewHighScore("New High Score"),
    FullCombo("Full Combo"),
    RankUp("Rank Up"),
    GoldStars("Gold Stars"),
    StarsUp("Stars Up"),
    DifficultyUp("Difficulty Up"),
    Progress("Progress"),
}

/**
 * One run of message text; emphasized runs are bold (web `NotificationMessagePart`).
 *
 * @property text Text.
 * @property emphasis Bold.
 */
data class NotificationMessagePart(val text: String, val emphasis: Boolean = false)

/**
 * A row ready for display.
 *
 * @property id Notification GUID.
 * @property title Title, e.g. "Song · Lead".
 * @property message Sentence.
 * @property flag Title Case flag label, or null for shop songs.
 * @property detectedAt Detection time.
 * @property destination Navigation target, if any.
 * @property messageParts [message] split into plain and emphasized runs.
 * @property flagKind Kind behind [flag] (drives the pill colour), or null for shop songs.
 * @property media Leading media.
 */
data class NotificationPresentation(
    val id: String,
    val title: String,
    val message: String,
    val flag: String?,
    val detectedAt: Instant,
    val destination: NotificationDestination?,
    val messageParts: List<NotificationMessagePart> = listOf(NotificationMessagePart(message)),
    val flagKind: NotificationFlagKind? = null,
    val media: NotificationMedia = NotificationMedia.SoloInstrument(Instrument.Lead),
)

/**
 * The player-scoped single-event subset of the web `notificationText.ts` /
 * `en.json` copy engine (as on iPhone and Windows). Band copy, multi-event
 * clause joining and flag groups are not ported; unknown kinds fall back to
 * "New improvement detected.".
 */
object NotificationText {
    private val templates = mapOf(
        "player_first_score" to "Your first {instrument} play on {song} scored {newScore} points",
        "player_score_pb" to "You set a new personal best on {instrument} for {song} with {newScore} points",
        "player_song_rank_improved" to "You climbed from {oldRank} to {newRank} on {instrument} for {song}",
        "player_stars_improved" to "You improved from {oldStars} to {newStars} stars on {instrument} for {song}",
        "player_gold_stars_achieved" to "You earned gold stars on {instrument} for {song}",
        "player_fc_achieved" to "You got a Full Combo on {instrument} for {song}",
        "player_difficulty_bumped" to "You improved your difficulty on {instrument} for {song} from {oldDifficulty} to {newDifficulty}",
        "player_weighted_rank_improved" to "You moved up from {oldRank} to {newRank} in {instrument} percentile rankings, weighted by number of entries",
        "player_skill_rank_improved" to "You moved up from {oldRank} to {newRank} in {instrument} adjusted percentile rankings",
        "player_total_score_rank_improved" to "You moved up from {oldRank} to {newRank} in {instrument} total score rankings",
        "player_fc_rate_rank_improved" to "You moved up from {oldRank} to {newRank} in {instrument} Full Combo rankings",
        "player_max_score_rank_improved" to "You moved up from {oldRank} to {newRank} in {instrument} max score rankings",
        "player_total_score_improved" to "Your {instrument} total score increased to {newScore} points",
        "player_fc_count_improved" to "Your {instrument} Full Combo count increased to {newCount}",
    )

    private val rankNames = mapOf(
        "player_weighted_rank_improved" to "Weighted Percentile Rank",
        "player_skill_rank_improved" to "Adjusted Percentile Rank",
        "player_total_score_rank_improved" to "Total Score Rank",
        "player_fc_rate_rank_improved" to "Full Combo Rank",
        "player_max_score_rank_improved" to "Max Score % Rank",
    )

    private val playerSongKinds = setOf(
        "player_first_score", "player_score_pb", "player_song_rank_improved", "player_stars_improved",
        "player_gold_stars_achieved", "player_fc_achieved", "player_difficulty_bumped",
    )

    /** Fallback wording never emphasized (web `FALLBACK_EMPHASIS_TERMS`). */
    private val fallbackTerms = setOf("this song", "a new score", "your new rank", "more", "a higher difficulty", "this instrument")

    /**
     * Format a row.
     *
     * @param item Notification.
     * @param songTitle Catalogue title for the song, when resolved.
     * @param artUrl Absolute album-art URL for the row's song, when resolved.
     * @return Presentation.
     */
    fun format(item: ImprovementNotification, songTitle: String?, artUrl: String? = null): NotificationPresentation {
        val destination = NotificationRouting.destination(item)
        val media = NotificationMediaRules.media(item, artUrl)
        if (item.eventKind == "service_new_shop_song") {
            val shopTitle = trimmed(item.payload?.songTitle) ?: trimmed(songTitle) ?: "New Song"
            val artist = trimmed(item.payload?.artist) ?: "Unknown Artist"
            val parts = listOf(
                NotificationMessagePart(shopTitle, emphasis = true),
                NotificationMessagePart(" by "),
                NotificationMessagePart(artist, emphasis = true),
                NotificationMessagePart(" has been added to the Item Shop."),
            )
            return NotificationPresentation(
                item.notificationGuid, "New Song · $shopTitle - $artist", parts.joinToString("") { it.text },
                null, item.detectedInstant, destination, parts, null, media,
            )
        }
        val instrumentLabel = item.parsedInstrument?.label
        val song = trimmed(songTitle) ?: "this song"
        var message = templates[item.eventKind]?.let { fill(it, item, song, instrumentLabel ?: "this instrument") + "." }
            ?: "New improvement detected."
        if (item.eventKind == "player_first_score") message = message.dropLast(1) + " and started at ${rank(item.newRank)}."
        val kind = flagKind(item.eventKind)
        return NotificationPresentation(
            item.notificationGuid, title(item, songTitle, instrumentLabel), message, kind.label, item.detectedInstant, destination,
            emphasize(message, emphasisTerms(item, song, instrumentLabel)), kind, media,
        )
    }

    /**
     * Words bolded in a player message (web `emphasisTermsForEvent`): the substituted values,
     * the song for song events, and the achievement wording.
     */
    private fun emphasisTerms(item: ImprovementNotification, song: String, instrument: String?): List<String> = buildList {
        add(number(item.newNumeric, "a new score"))
        add(rank(item.oldRank))
        add(rank(item.newRank))
        instrument?.let(::add)
        if (item.eventKind in playerSongKinds) add(song)
        when (item.eventKind) {
            "player_gold_stars_achieved" -> add("gold stars")
            "player_fc_achieved" -> add("Full Combo")
            "player_stars_improved" -> add("${number(item.oldNumeric, "more")} to ${number(item.newNumeric, "more")} stars")
            "player_difficulty_bumped" -> add(number(item.oldNumeric, "a higher difficulty"))
        }
    }

    /**
     * Split text into plain and emphasized runs, longest term first (web `emphasizeText`).
     *
     * @param text Message.
     * @param terms Candidate terms; blanks and fallback wording are ignored.
     * @return Runs, adjacent runs of the same weight merged.
     */
    fun emphasize(text: String, terms: List<String>): List<NotificationMessagePart> {
        val candidates = terms.map(String::trim).filter { it.isNotEmpty() && it !in fallbackTerms && it in text }
            .distinct().sortedByDescending(String::length)
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

    private fun title(item: ImprovementNotification, songTitle: String?, instrumentLabel: String?): String {
        val base = trimmed(songTitle)
        if (base != null && instrumentLabel != null && item.eventKind in playerSongKinds) return "$base · $instrumentLabel"
        rankNames[item.eventKind]?.let { return "$it Improved" }
        return when (item.eventKind) {
            "player_total_score_improved" -> "Total Score Improved"
            "player_fc_count_improved" -> "Full Combo Count Improved"
            else -> base ?: "Notification"
        }
    }

    /**
     * Flag label (web `flagKind` + `notifications.flags.*`).
     *
     * @param eventKind Event kind.
     * @return Label.
     */
    fun flag(eventKind: String): String = flagKind(eventKind).label

    /**
     * Flag kind (web `flagKind`).
     *
     * @param eventKind Event kind.
     * @return Kind.
     */
    fun flagKind(eventKind: String): NotificationFlagKind = when {
        eventKind == "player_first_score" -> NotificationFlagKind.FirstPlay
        eventKind == "player_score_pb" -> NotificationFlagKind.NewHighScore
        eventKind == "player_fc_achieved" -> NotificationFlagKind.FullCombo
        "rank_improved" in eventKind -> NotificationFlagKind.RankUp
        eventKind == "player_gold_stars_achieved" -> NotificationFlagKind.GoldStars
        eventKind == "player_stars_improved" -> NotificationFlagKind.StarsUp
        eventKind == "player_difficulty_bumped" -> NotificationFlagKind.DifficultyUp
        eventKind == "player_total_score_improved" || eventKind == "player_fc_count_improved" -> NotificationFlagKind.Progress
        else -> NotificationFlagKind.Improvement
    }

    private fun fill(template: String, item: ImprovementNotification, song: String, instrument: String): String = template
        .replace("{instrument}", instrument)
        .replace("{song}", song)
        .replace("{newScore}", number(item.newNumeric, "a new score"))
        .replace("{oldRank}", rank(item.oldRank))
        .replace("{newRank}", rank(item.newRank))
        .replace("{oldStars}", number(item.oldNumeric, "more"))
        .replace("{newStars}", number(item.newNumeric, "more"))
        .replace("{oldDifficulty}", number(item.oldNumeric, "a higher difficulty"))
        .replace("{newDifficulty}", number(item.newNumeric, "a higher difficulty"))
        .replace("{newCount}", number(item.newNumeric, "more"))

    /**
     * JavaScript `toLocaleString()` for en-US (up to three fraction digits).
     *
     * @param value Number.
     * @param fallback Text when absent.
     * @return Formatted number.
     */
    fun number(value: Double?, fallback: String): String {
        if (value == null || !value.isFinite()) return fallback
        return NumberFormat.getNumberInstance(Locale.US).apply { maximumFractionDigits = 3 }.format(value)
    }

    /**
     * Rank as `#1,234`, or "your new rank".
     *
     * @param rank Rank.
     * @return Formatted rank.
     */
    fun rank(rank: Int?): String = rank?.let { "#" + NumberFormat.getIntegerInstance(Locale.US).format(it) } ?: "your new rank"

    /**
     * Short relative time: "Just now", "5m ago", "3h ago", "2d ago", else "Sep 28".
     *
     * @param then Detection time.
     * @param now Current time.
     * @return Label.
     */
    fun relativeTime(then: Instant, now: Instant): String {
        val seconds = java.time.Duration.between(then, now).seconds
        return when {
            seconds < 60 -> "Just now"
            seconds < 3_600 -> "${seconds / 60}m ago"
            seconds < 86_400 -> "${seconds / 3_600}h ago"
            seconds < 7 * 86_400 -> "${seconds / 86_400}d ago"
            else -> java.time.format.DateTimeFormatter.ofPattern("MMM d", Locale.US).withZone(java.time.ZoneId.systemDefault()).format(then)
        }
    }

    private fun trimmed(text: String?): String? = text?.trim()?.takeIf { it.isNotEmpty() }
}

// endregion
