package com.festivalscoretracker.android.core.notifications

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rankings.RankingMetric
import java.text.NumberFormat
import java.time.Instant
import java.util.Locale
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.nullable
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

// region Wire

/**
 * Web `numberValue`: a finite JSON number or numeric string, else null (never a decode failure).
 */
internal object LenientDoubleSerializer : KSerializer<Double?> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("LenientDouble", PrimitiveKind.DOUBLE).nullable

    override fun deserialize(decoder: Decoder): Double? {
        val element = (decoder as? JsonDecoder)?.decodeJsonElement() ?: return decoder.decodeDouble()
        val primitive = element as? JsonPrimitive ?: return null
        if (primitive is JsonNull) return null
        return primitive.content.trim().toDoubleOrNull()?.takeIf { it.isFinite() }
    }

    override fun serialize(encoder: Encoder, value: Double?) {
        if (value == null) encoder.encodeNull() else encoder.encodeDouble(value)
    }
}

/**
 * Web `booleanValue`: a JSON boolean or "true"/"false" string, else null (never a decode failure).
 */
internal object LenientBooleanSerializer : KSerializer<Boolean?> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("LenientBoolean", PrimitiveKind.BOOLEAN).nullable

    override fun deserialize(decoder: Decoder): Boolean? {
        val element = (decoder as? JsonDecoder)?.decodeJsonElement() ?: return decoder.decodeBoolean()
        val primitive = element as? JsonPrimitive ?: return null
        if (primitive is JsonNull) return null
        return when (primitive.content.trim().lowercase()) {
            "true" -> true
            "false" -> false
            else -> null
        }
    }

    override fun serialize(encoder: Encoder, value: Boolean?) {
        if (value == null) encoder.encodeNull() else encoder.encodeBoolean(value)
    }
}

/**
 * Web `stringValue`: a non-blank JSON string, trimmed, else null (never a decode failure).
 */
internal object LenientStringSerializer : KSerializer<String?> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("LenientString", PrimitiveKind.STRING).nullable

    override fun deserialize(decoder: Decoder): String? {
        val element = (decoder as? JsonDecoder)?.decodeJsonElement() ?: return decoder.decodeString()
        val primitive = element as? JsonPrimitive ?: return null
        if (!primitive.isString) return null
        return primitive.content.trim().takeIf { it.isNotEmpty() }
    }

    override fun serialize(encoder: Encoder, value: String?) {
        if (value == null) encoder.encodeNull() else encoder.encodeString(value)
    }
}

/**
 * One coalesced sub-event (web `ImprovementNotificationEventPayload`, player fields). Fields
 * decode leniently like the web's `normalizePayloadEvent`, so one malformed event never fails
 * the feed.
 *
 * @property eventKind Event kind.
 * @property instrument Service instrument key (live events usually omit it: the row's chart).
 * @property metric Raw metric.
 * @property oldNumeric Previous value.
 * @property newNumeric New value.
 * @property oldRank Previous rank.
 * @property newRank New rank.
 * @property oldLabel Previous value's display label (difficulty).
 * @property newLabel New value's display label (difficulty).
 * @property oldFullCombo Previous Full Combo state.
 * @property newFullCombo New Full Combo state.
 * @property oldStars Previous stars.
 * @property newStars New stars (6 = gold).
 */
@Serializable
data class NotificationEventPayload(
    @Serializable(with = LenientStringSerializer::class) val eventKind: String? = null,
    @Serializable(with = LenientStringSerializer::class) val instrument: String? = null,
    @Serializable(with = LenientStringSerializer::class) val metric: String? = null,
    @Serializable(with = LenientDoubleSerializer::class) val oldNumeric: Double? = null,
    @Serializable(with = LenientDoubleSerializer::class) val newNumeric: Double? = null,
    @Serializable(with = LenientDoubleSerializer::class) val oldRank: Double? = null,
    @Serializable(with = LenientDoubleSerializer::class) val newRank: Double? = null,
    @Serializable(with = LenientStringSerializer::class) val oldLabel: String? = null,
    @Serializable(with = LenientStringSerializer::class) val newLabel: String? = null,
    @Serializable(with = LenientBooleanSerializer::class) val oldFullCombo: Boolean? = null,
    @Serializable(with = LenientBooleanSerializer::class) val newFullCombo: Boolean? = null,
    @Serializable(with = LenientDoubleSerializer::class) val oldStars: Double? = null,
    @Serializable(with = LenientDoubleSerializer::class) val newStars: Double? = null,
)

/**
 * Typed subset of the notification `payload` object.
 *
 * @property coalescedEvents Coalesced sub-events.
 * @property coalescedInstruments Every chart the coalesced row touches.
 * @property songTitle Shop song title (`service_new_shop_song` has no account).
 * @property artist Shop song artist.
 * @property albumArt Shop song art reference.
 * @property oldFullCombo Previous Full Combo state of the row's score event.
 * @property newFullCombo New Full Combo state of the row's score event.
 * @property oldStars Previous stars of the row's score event.
 * @property newStars New stars of the row's score event (6 = gold).
 */
@Serializable
data class NotificationPayload(
    val coalescedEvents: List<NotificationEventPayload>? = null,
    val coalescedInstruments: List<String>? = null,
    val songTitle: String? = null,
    val artist: String? = null,
    val albumArt: String? = null,
    @Serializable(with = LenientBooleanSerializer::class) val oldFullCombo: Boolean? = null,
    @Serializable(with = LenientBooleanSerializer::class) val newFullCombo: Boolean? = null,
    @Serializable(with = LenientDoubleSerializer::class) val oldStars: Double? = null,
    @Serializable(with = LenientDoubleSerializer::class) val newStars: Double? = null,
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
                // Live coalesced events carry no instrument of their own; they belong to the row's chart.
                val instrument = event.instrument?.takeIf(String::isNotEmpty) ?: item.instrument
                return NotificationDestination.Rankings(rankBy, Instrument.fromWireId(instrument))
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

    /**
     * Hide experimental rank changes while Settings → Experimental Ranks is off (web
     * `projectExperimentalRankNotification`, experimental-ranks R4). A row with no rank
     * events is kept as is; a row whose rank events are all experimental is dropped; a
     * mixed coalesced row keeps only its other events, led by the first of them.
     *
     * @param item Notification.
     * @param experimentalRanks `AppSettings.experimentalRanks`.
     * @return The row to show, or null to hide it.
     */
    fun projectExperimentalRanks(item: ImprovementNotification, experimentalRanks: Boolean): ImprovementNotification? {
        if (experimentalRanks) return item
        val events = events(item)
        if (events.none { rankingMetric(it.eventKind, it.metric) != null }) return item
        val visible = events.filter { event ->
            val metric = rankingMetric(event.eventKind, event.metric) ?: return@filter true
            RankingMetric.fromWireId(metric)?.isExperimental != true
        }
        if (visible.isEmpty()) return null
        if (visible.size == events.size) return item
        val primary = visible.first()
        return item.copy(
            eventKind = primary.eventKind ?: item.eventKind,
            metric = primary.metric,
            oldNumeric = primary.oldNumeric,
            newNumeric = primary.newNumeric,
            oldRank = primary.oldRank?.toInt(),
            newRank = primary.newRank?.toInt(),
            payload = (item.payload ?: NotificationPayload()).copy(coalescedEvents = visible),
        )
    }
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
    ;

    companion object {
        /**
         * Flag kind for an event kind (web `flagKind`, player kinds).
         *
         * @param eventKind Event kind.
         * @return Kind.
         */
        fun forEventKind(eventKind: String): NotificationFlagKind = when {
            eventKind == "player_first_score" -> FirstPlay
            eventKind == "player_score_pb" -> NewHighScore
            eventKind == "player_fc_achieved" -> FullCombo
            "rank_improved" in eventKind -> RankUp
            eventKind == "player_gold_stars_achieved" -> GoldStars
            eventKind == "player_stars_improved" -> StarsUp
            eventKind == "player_difficulty_bumped" -> DifficultyUp
            eventKind == "player_total_score_improved" || eventKind == "player_fc_count_improved" -> Progress
            else -> Improvement
        }
    }
}

/**
 * The flags of one chart in a multi-chart song row (web `NotificationFlagGroup`).
 *
 * @property instrument Chart.
 * @property label Chart label.
 * @property flags Unique flags for that chart, in event priority order.
 */
data class NotificationFlagGroup(val instrument: Instrument, val label: String, val flags: List<NotificationFlagKind>) {
    /** TalkBack text ("Lead: First Play, Full Combo"). */
    val spoken: String get() = "$label: " + flags.joinToString(", ") { it.label }
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
 * @property message Message; statement-style rows separate their statements with a blank line.
 * @property flags Flags in event priority order (empty for shop songs).
 * @property detectedAt Detection time.
 * @property destination Navigation target, if any.
 * @property messageParts [message] split into plain and emphasized runs.
 * @property flagGroups Per-chart flags for multi-chart song rows; when present they replace [flags] on screen.
 * @property media Leading media.
 */
data class NotificationPresentation(
    val id: String,
    val title: String,
    val message: String,
    val flags: List<NotificationFlagKind>,
    val detectedAt: Instant,
    val destination: NotificationDestination?,
    val messageParts: List<NotificationMessagePart> = listOf(NotificationMessagePart(message)),
    val flagGroups: List<NotificationFlagGroup> = emptyList(),
    val media: NotificationMedia = NotificationMedia.SoloInstrument(Instrument.Lead),
) {
    /** TalkBack text for the flags: one "Chart: flags." sentence per group, else the labels joined. */
    val spokenFlags: String
        get() = if (flagGroups.isNotEmpty()) flagGroups.joinToString(" ") { it.spoken + "." } else flags.joinToString(", ") { it.label }
}

/**
 * The player-scoped web `notificationText.ts` / `en.json` copy engine (see
 * [NotificationTextEngine]; the same port as Apple's, issue #76): coalesced events become one
 * sentence or statement-style paragraphs with bold values, every event's flag and per-chart flag
 * groups. Band and combo copy is not ported; unknown kinds fall back to "New improvement detected.".
 */
object NotificationText {
    /**
     * Format a row.
     *
     * Deliberate deviation from the web: a song the catalogue doesn't resolve reads "this song"
     * and titles fall back to "Notification", never the raw song ID.
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
                emptyList(), item.detectedInstant, destination, parts, emptyList(), media,
            )
        }
        val result = NotificationTextEngine.present(input(item, trimmed(songTitle)))
        return NotificationPresentation(
            item.notificationGuid, result.title, result.message, result.flags, item.detectedInstant, destination,
            result.messageParts, result.flagGroups, media,
        )
    }

    /**
     * Normalize a row like the web feed (`useProfileNotificationsFeed`): coalesced events take
     * the row's chart when they name none; a row without events is its own event, carrying the
     * payload's Full Combo / star state.
     */
    internal fun input(item: ImprovementNotification, songTitle: String?): NotificationTextInput {
        val instrument = item.parsedInstrument
        val label = instrument?.label
        val payload = item.payload
        val payloadState = NotificationScoreResult(payload?.oldFullCombo, payload?.newFullCombo, payload?.oldStars, payload?.newStars)
        val coalesced = payload?.coalescedEvents.orEmpty().mapNotNull { event ->
            val kind = event.eventKind?.trim()?.takeIf(String::isNotEmpty) ?: return@mapNotNull null
            NotificationTextEvent(
                eventKind = kind,
                instrument = Instrument.fromWireId(event.instrument) ?: instrument,
                metric = event.metric,
                oldNumeric = event.oldNumeric,
                newNumeric = event.newNumeric,
                oldRank = event.oldRank,
                newRank = event.newRank,
                oldLabel = trimmed(event.oldLabel),
                newLabel = trimmed(event.newLabel),
                state = NotificationScoreResult(event.oldFullCombo, event.newFullCombo, event.oldStars, event.newStars),
            )
        }
        val events = coalesced.ifEmpty {
            listOf(
                NotificationTextEvent(
                    item.eventKind, instrument, item.metric, item.oldNumeric, item.newNumeric,
                    item.oldRank?.toDouble(), item.newRank?.toDouble(), state = payloadState,
                ),
            )
        }
        return NotificationTextInput(
            eventKind = item.eventKind,
            instrument = instrument,
            instrumentLabel = label,
            scopeLabel = label,
            metric = item.metric,
            oldNumeric = item.oldNumeric,
            newNumeric = item.newNumeric,
            oldRank = item.oldRank?.toDouble(),
            newRank = item.newRank?.toDouble(),
            songTitle = songTitle,
            title = songTitle ?: label.takeIf { item.songId.isNullOrEmpty() },
            payloadState = payloadState,
            events = events,
        )
    }

    /**
     * Split text into plain and emphasized runs, longest term first (web `emphasizeText`).
     *
     * @param text Message.
     * @param terms Candidate terms; blanks and fallback wording are ignored.
     * @return Runs, adjacent runs of the same weight merged.
     */
    fun emphasize(text: String, terms: List<String>): List<NotificationMessagePart> = NotificationTextEngine.emphasize(text, terms)

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
    fun flagKind(eventKind: String): NotificationFlagKind = NotificationFlagKind.forEventKind(eventKind)

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
     * Spoken relative time: "Just now", "5 minutes ago", "1 hour ago", "2 days ago", else
     * "September 28". Rows only speak it (TalkBack), so units are words: speech engines read
     * "5m" as "5 meters" (issue #136).
     *
     * @param then Detection time.
     * @param now Current time.
     * @return Label.
     */
    fun relativeTime(then: Instant, now: Instant): String {
        val seconds = java.time.Duration.between(then, now).seconds
        fun ago(count: Long, unit: String) = "$count $unit${if (count == 1L) "" else "s"} ago"
        return when {
            seconds < 60 -> "Just now"
            seconds < 3_600 -> ago(seconds / 60, "minute")
            seconds < 86_400 -> ago(seconds / 3_600, "hour")
            seconds < 7 * 86_400 -> ago(seconds / 86_400, "day")
            else -> java.time.format.DateTimeFormatter.ofPattern("MMMM d", Locale.US).withZone(java.time.ZoneId.systemDefault()).format(then)
        }
    }

    private fun trimmed(text: String?): String? = text?.trim()?.takeIf { it.isNotEmpty() }
}

// endregion
