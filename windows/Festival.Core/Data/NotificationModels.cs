using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Wire
/// <summary>
/// One coalesced sub-event (service <c>ImprovementNotificationEventPayload</c>, player subset). The display values are
/// read leniently like the web's <c>numberValue</c>/<c>booleanValue</c>: a value of the wrong type reads as absent
/// instead of failing the whole feed.
/// </summary>
public sealed record NotificationEventPayload
{
    /// <summary>Event kind.</summary>
    [JsonPropertyName("eventKind")] public string? EventKind { get; init; }
    /// <summary>Service instrument key.</summary>
    [JsonPropertyName("instrument")] public string? Instrument { get; init; }
    /// <summary>Raw metric.</summary>
    [JsonPropertyName("metric")] public string? Metric { get; init; }
    /// <summary>Previous value (score, stars, difficulty or count).</summary>
    [JsonPropertyName("oldNumeric"), JsonConverter(typeof(LenientNumberConverter))] public double? OldNumeric { get; init; }
    /// <summary>New value.</summary>
    [JsonPropertyName("newNumeric"), JsonConverter(typeof(LenientNumberConverter))] public double? NewNumeric { get; init; }
    /// <summary>Previous rank.</summary>
    [JsonPropertyName("oldRank"), JsonConverter(typeof(LenientNumberConverter))] public double? OldRank { get; init; }
    /// <summary>New rank.</summary>
    [JsonPropertyName("newRank"), JsonConverter(typeof(LenientNumberConverter))] public double? NewRank { get; init; }
    /// <summary>Previous value's display label (e.g. a difficulty name).</summary>
    [JsonPropertyName("oldLabel"), JsonConverter(typeof(LenientStringConverter))] public string? OldLabel { get; init; }
    /// <summary>New value's display label.</summary>
    [JsonPropertyName("newLabel"), JsonConverter(typeof(LenientStringConverter))] public string? NewLabel { get; init; }
    /// <summary>Whether the previous score was a Full Combo.</summary>
    [JsonPropertyName("oldFullCombo"), JsonConverter(typeof(LenientBooleanConverter))] public bool? OldFullCombo { get; init; }
    /// <summary>Whether the new score is a Full Combo.</summary>
    [JsonPropertyName("newFullCombo"), JsonConverter(typeof(LenientBooleanConverter))] public bool? NewFullCombo { get; init; }
    /// <summary>Previous stars.</summary>
    [JsonPropertyName("oldStars"), JsonConverter(typeof(LenientNumberConverter))] public double? OldStars { get; init; }
    /// <summary>New stars (6 = gold).</summary>
    [JsonPropertyName("newStars"), JsonConverter(typeof(LenientNumberConverter))] public double? NewStars { get; init; }
}

/// <summary>Typed subset of the notification <c>payload</c> object.</summary>
public sealed record NotificationPayload
{
    /// <summary>Coalesced sub-events.</summary>
    [JsonPropertyName("coalescedEvents")] public IReadOnlyList<NotificationEventPayload>? CoalescedEvents { get; init; }
    /// <summary>Every chart a coalesced row touches (service instrument keys).</summary>
    [JsonPropertyName("coalescedInstruments")] public IReadOnlyList<string>? CoalescedInstruments { get; init; }
    /// <summary>Whether the row's previous score was a Full Combo (score rows).</summary>
    [JsonPropertyName("oldFullCombo"), JsonConverter(typeof(LenientBooleanConverter))] public bool? OldFullCombo { get; init; }
    /// <summary>Whether the row's new score is a Full Combo (score rows).</summary>
    [JsonPropertyName("newFullCombo"), JsonConverter(typeof(LenientBooleanConverter))] public bool? NewFullCombo { get; init; }
    /// <summary>The row's previous stars (score rows).</summary>
    [JsonPropertyName("oldStars"), JsonConverter(typeof(LenientNumberConverter))] public double? OldStars { get; init; }
    /// <summary>The row's new stars (score rows; 6 = gold).</summary>
    [JsonPropertyName("newStars"), JsonConverter(typeof(LenientNumberConverter))] public double? NewStars { get; init; }
    /// <summary>Shop song title (<c>service_new_shop_song</c>, which has no account).</summary>
    [JsonPropertyName("songTitle")] public string? SongTitle { get; init; }
    /// <summary>Shop song artist.</summary>
    [JsonPropertyName("artist")] public string? Artist { get; init; }
    /// <summary>Shop song art reference.</summary>
    [JsonPropertyName("albumArt")] public string? AlbumArt { get; init; }
}

/// <summary>One notification (service <c>ImprovementNotificationDto</c>).</summary>
public sealed record ImprovementNotification
{
    /// <summary>Event ID.</summary>
    [JsonPropertyName("eventId")] public long EventId { get; init; }
    /// <summary>Stable notification ID (a GUID in production).</summary>
    [JsonPropertyName("notificationGuid")] public string NotificationGuid { get; init; } = "";
    /// <summary>Account, absent for service notifications.</summary>
    [JsonPropertyName("accountId")] public string? AccountId { get; init; }
    /// <summary>Event kind.</summary>
    [JsonPropertyName("eventKind")] public string EventKind { get; init; } = "";
    /// <summary>Song.</summary>
    [JsonPropertyName("songId")] public string? SongId { get; init; }
    /// <summary>Service instrument key.</summary>
    [JsonPropertyName("instrument")] public string? Instrument { get; init; }
    /// <summary>Raw metric.</summary>
    [JsonPropertyName("metric")] public string? Metric { get; init; }
    /// <summary>Previous value.</summary>
    [JsonPropertyName("oldNumeric")] public double? OldNumeric { get; init; }
    /// <summary>New value.</summary>
    [JsonPropertyName("newNumeric")] public double? NewNumeric { get; init; }
    /// <summary>Previous rank.</summary>
    [JsonPropertyName("oldRank")] public int? OldRank { get; init; }
    /// <summary>New rank.</summary>
    [JsonPropertyName("newRank")] public int? NewRank { get; init; }
    /// <summary>Payload (coalesced events, shop song details).</summary>
    [JsonPropertyName("payload")] public NotificationPayload? Payload { get; init; }
    /// <summary>Detection time.</summary>
    [JsonPropertyName("detectedAt")] public DateTimeOffset DetectedAt { get; init; }
    /// <summary>Expiry time.</summary>
    [JsonPropertyName("expiresAt")] public DateTimeOffset ExpiresAt { get; init; }

    /// <summary>Parsed solo instrument, if any.</summary>
    [JsonIgnore]
    public Instrument? ParsedInstrument => InstrumentInfo.TryParse(Instrument, out var i) ? i : null;
}

/// <summary><c>GET /api/player/{accountId}/notifications</c> envelope.</summary>
public sealed record ImprovementNotificationsEnvelope
{
    /// <summary>Generation time.</summary>
    [JsonPropertyName("generatedAt")] public DateTimeOffset GeneratedAt { get; init; }
    /// <summary>Retention window.</summary>
    [JsonPropertyName("expiresAfterHours")] public double ExpiresAfterHours { get; init; }
    /// <summary>Detection run that produced the feed.</summary>
    [JsonPropertyName("sourceRunId")] public long? SourceRunId { get; init; }
    /// <summary>When that run completed.</summary>
    [JsonPropertyName("sourceCompletedAt")] public DateTimeOffset? SourceCompletedAt { get; init; }
    /// <summary>Explicit generated flag (fixtures; the service infers it).</summary>
    [JsonPropertyName("notificationsGenerated")] public bool? NotificationsGenerated { get; init; }
    /// <summary>Rows.</summary>
    [JsonPropertyName("items")] public IReadOnlyList<ImprovementNotification>? Items { get; init; }

    /// <summary>Whether a detection run ever produced this feed ("generated but empty" differs from "never generated").</summary>
    [JsonIgnore]
    public bool IsGenerated => NotificationsGenerated ?? (SourceRunId is not null || SourceCompletedAt is not null || Items is { Count: > 0 });

    /// <summary>Rejects malformed rows (unsafe IDs, duplicate GUIDs, missing kinds).</summary>
    /// <param name="limit">Requested row cap.</param>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResponse"/>.</exception>
    public void Validate(int limit)
    {
        if (Items is null || Items.Count > limit) throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in Items)
        {
            if (item is null || item.NotificationGuid is not { Length: > 0 and <= 64 } || !seen.Add(item.NotificationGuid) ||
                ProfileText.ContainsUnsafeCharacter(item.NotificationGuid) || item.EventKind is not { Length: > 0 and <= 80 } ||
                (item.SongId is { } song && (song.Length is 0 or > 200 || ProfileText.ContainsUnsafeCharacter(song))))
                throw new FestivalApiException(FestivalApiErrorKind.InvalidResponse);
        }
    }
}

/// <summary>A finite JSON number, else <see langword="null"/> (web <c>numberValue</c>).</summary>
internal sealed class LenientNumberConverter : JsonConverter<double?>
{
    /// <inheritdoc />
    public override bool HandleNull => true;

    /// <inheritdoc />
    public override double? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        double? value = reader.TokenType switch
        {
            JsonTokenType.Number when reader.TryGetDouble(out var number) && double.IsFinite(number) => number,
            JsonTokenType.String when double.TryParse(reader.GetString()?.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed)
                && double.IsFinite(parsed) => parsed,
            _ => null,
        };
        reader.Skip();
        return value;
    }

    /// <inheritdoc />
    public override void Write(Utf8JsonWriter writer, double? value, JsonSerializerOptions options)
    {
        if (value is { } number) writer.WriteNumberValue(number);
        else writer.WriteNullValue();
    }
}

/// <summary>A JSON boolean, else <see langword="null"/> (web <c>booleanValue</c>).</summary>
internal sealed class LenientBooleanConverter : JsonConverter<bool?>
{
    /// <inheritdoc />
    public override bool HandleNull => true;

    /// <inheritdoc />
    public override bool? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        bool? value = reader.TokenType switch
        {
            JsonTokenType.True => true,
            JsonTokenType.False => false,
            JsonTokenType.String => reader.GetString()?.Trim().ToLowerInvariant() switch { "true" => true, "false" => false, _ => null },
            _ => null,
        };
        reader.Skip();
        return value;
    }

    /// <inheritdoc />
    public override void Write(Utf8JsonWriter writer, bool? value, JsonSerializerOptions options)
    {
        if (value is { } flag) writer.WriteBooleanValue(flag);
        else writer.WriteNullValue();
    }
}

/// <summary>A non-blank JSON string, trimmed, else <see langword="null"/> (web <c>stringValue</c>).</summary>
internal sealed class LenientStringConverter : JsonConverter<string?>
{
    /// <inheritdoc />
    public override bool HandleNull => true;

    /// <inheritdoc />
    public override string? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var value = reader.TokenType == JsonTokenType.String ? reader.GetString()?.Trim() : null;
        reader.Skip();
        return string.IsNullOrEmpty(value) ? null : value;
    }

    /// <inheritdoc />
    public override void Write(Utf8JsonWriter writer, string? value, JsonSerializerOptions options)
    {
        if (value is null) writer.WriteNullValue();
        else writer.WriteStringValue(value);
    }
}
#endregion

#region Destination
/// <summary>Where a notification row navigates (web <c>getNotificationDestination</c>, player feed).</summary>
public abstract record NotificationDestination
{
    /// <summary>Song Detail, with the chart when the row concerns exactly one instrument.</summary>
    /// <param name="SongId">Song.</param>
    /// <param name="Instrument">Chart, or <see langword="null"/> for multi-instrument rows.</param>
    public sealed record Song(string SongId, Instrument? Instrument) : NotificationDestination;

    /// <summary>Leaderboards hub with the Rank By metric saved first (web <c>/leaderboards?rankBy=</c>).</summary>
    /// <param name="RankBy">Ranking metric.</param>
    public sealed record Rankings(string RankBy) : NotificationDestination;
}

/// <summary>Destination and ranking-metric rules (web <c>notificationDestination.ts</c>, <c>notificationRanking.ts</c>).</summary>
public static class NotificationRouting
{
    private static readonly HashSet<string> SongEventKinds =
    [
        "service_new_shop_song", "player_first_score", "player_score_pb", "player_song_rank_improved", "player_stars_improved",
        "player_gold_stars_achieved", "player_fc_achieved", "player_difficulty_bumped",
    ];

    private static readonly Dictionary<string, string> MetricByEventKind = new()
    {
        ["player_weighted_rank_improved"] = "weighted",
        ["player_skill_rank_improved"] = "adjusted",
        ["player_total_score_rank_improved"] = "totalscore",
        ["player_fc_rate_rank_improved"] = "fcrate",
        ["player_max_score_rank_improved"] = "maxscore",
    };

    private static readonly Dictionary<string, string> MetricByMetric = new()
    {
        ["weighted_rank"] = "weighted",
        ["skill_rank"] = "adjusted",
        ["adjusted_skill_rank"] = "adjusted",
        ["total_score_rank"] = "totalscore",
        ["fc_rate_rank"] = "fcrate",
        ["max_score_rank"] = "maxscore",
        ["max_score_percent_rank"] = "maxscore",
        ["composite_rank"] = "adjusted",
        ["composite_rank_weighted"] = "weighted",
        ["composite_rank_total_score"] = "totalscore",
        ["composite_rank_fc_rate"] = "fcrate",
        ["composite_rank_max_score"] = "maxscore",
    };

    /// <summary>Rank By metric for an event (kind first, then raw metric).</summary>
    /// <param name="eventKind">Event kind.</param>
    /// <param name="metric">Raw metric.</param>
    /// <returns>Metric, or <see langword="null"/> for non-rank events.</returns>
    public static string? RankingMetric(string? eventKind, string? metric)
    {
        if (eventKind?.Trim() is { Length: > 0 } kind && MetricByEventKind.TryGetValue(kind, out var byKind)) return byKind;
        return metric?.Trim() is { Length: > 0 } m && MetricByMetric.TryGetValue(m, out var byMetric) ? byMetric : null;
    }

    /// <summary>Resolves a row's destination.</summary>
    /// <param name="item">Notification.</param>
    /// <returns>Destination, or <see langword="null"/> (aggregate improvements have none).</returns>
    public static NotificationDestination? Destination(ImprovementNotification item)
    {
        var events = Events(item);
        if (item.SongId is { Length: > 0 } songId && events.Any(e => SongEventKinds.Contains(e.EventKind ?? "")))
        {
            var instruments = events.Select(e => e.Instrument).Where(i => !string.IsNullOrEmpty(i)).Distinct().Count();
            return new NotificationDestination.Song(songId, instruments > 1 ? null : item.ParsedInstrument);
        }
        foreach (var e in events)
        {
            if (RankingMetric(e.EventKind, e.Metric) is { } rankBy) return new NotificationDestination.Rankings(rankBy);
        }
        return null;
    }

    /// <summary>The row's events: coalesced payload events, else the row itself.</summary>
    /// <param name="item">Notification.</param>
    /// <returns>Events.</returns>
    internal static IReadOnlyList<NotificationEventPayload> Events(ImprovementNotification item)
    {
        var coalesced = item.Payload?.CoalescedEvents?.Where(e => !string.IsNullOrEmpty(e?.EventKind)).ToList();
        return coalesced is { Count: > 0 } ? coalesced
            : [new NotificationEventPayload { EventKind = item.EventKind, Instrument = item.Instrument, Metric = item.Metric }];
    }
}
#endregion

#region Media
/// <summary>Leading media kinds of a player-feed row (web <c>NotificationMedia</c>; combo media needs band feeds).</summary>
public enum NotificationMediaKind
{
    /// <summary>Album art only.</summary>
    Song,
    /// <summary>Album art above a two-column grid of the affected charts.</summary>
    SongInstrumentGrid,
    /// <summary>One instrument icon (no resolved art).</summary>
    SoloInstrument,
}

/// <summary>Media rules (web <c>useProfileNotificationsFeed.notificationMedia</c> and the shop-song mapping).</summary>
public static class NotificationMediaRules
{
    /// <summary>
    /// Charts a row touches: <c>coalescedInstruments</c>, the coalesced events' charts and the row's own, deduplicated in
    /// canonical chart order (web <c>notificationSurfaceInstruments</c>).
    /// </summary>
    /// <param name="item">Notification.</param>
    /// <returns>Instruments.</returns>
    public static IReadOnlyList<Instrument> SurfaceInstruments(ImprovementNotification item)
    {
        var keys = (item.Payload?.CoalescedInstruments ?? []).Concat(NotificationRouting.Events(item).Select(e => e.Instrument)).Append(item.Instrument);
        var present = new HashSet<Instrument>();
        foreach (var key in keys)
        {
            if (InstrumentInfo.TryParse(key, out var instrument)) present.Add(instrument);
        }
        return InstrumentInfo.All.Where(present.Contains).ToList();
    }
}
#endregion

#region Text
/// <summary>Flag kinds (web <c>NotificationFlagKind</c>); labels and colours follow <c>notifications.flags.*</c> / <c>FLAG_COLORS</c>.</summary>
public enum NotificationFlagKind
{
    /// <summary>"Improvement" (unknown kinds).</summary>
    Improvement,
    /// <summary>"First Play".</summary>
    FirstPlay,
    /// <summary>"New High Score".</summary>
    NewHighScore,
    /// <summary>"Full Combo".</summary>
    FullCombo,
    /// <summary>"Rank Up".</summary>
    RankUp,
    /// <summary>"Gold Stars".</summary>
    GoldStars,
    /// <summary>"Stars Up".</summary>
    StarsUp,
    /// <summary>"Difficulty Up".</summary>
    DifficultyUp,
    /// <summary>"Progress" (aggregate improvements).</summary>
    Progress,
}

/// <summary>Flag labels and pill colours.</summary>
public static class NotificationFlagKinds
{
    /// <summary>Title Case label (web <c>notifications.flags.*</c>).</summary>
    /// <param name="kind">Flag kind.</param>
    /// <returns>Label.</returns>
    public static string Label(this NotificationFlagKind kind) => kind switch
    {
        NotificationFlagKind.FirstPlay => "First Play",
        NotificationFlagKind.NewHighScore => "New High Score",
        NotificationFlagKind.FullCombo => "Full Combo",
        NotificationFlagKind.RankUp => "Rank Up",
        NotificationFlagKind.GoldStars => "Gold Stars",
        NotificationFlagKind.StarsUp => "Stars Up",
        NotificationFlagKind.DifficultyUp => "Difficulty Up",
        NotificationFlagKind.Progress => "Progress",
        _ => "Improvement",
    };

    /// <summary>Opaque pill background as <c>0xAARRGGBB</c> (web <c>FLAG_COLORS</c>; white text passes 4.5:1 on each).</summary>
    /// <param name="kind">Flag kind.</param>
    /// <returns>ARGB colour.</returns>
    public static uint Argb(this NotificationFlagKind kind) => kind switch
    {
        NotificationFlagKind.FirstPlay => 0xFF6D28D9,
        NotificationFlagKind.NewHighScore => 0xFF0F766E,
        NotificationFlagKind.FullCombo => 0xFF7C2D12,
        NotificationFlagKind.RankUp => 0xFF1D4ED8,
        NotificationFlagKind.GoldStars => 0xFF92400E,
        NotificationFlagKind.StarsUp => 0xFFBE123C,
        NotificationFlagKind.DifficultyUp => 0xFF047857,
        NotificationFlagKind.Progress => 0xFF4338CA,
        _ => 0xFF4B5563,
    };
}

/// <summary>One run of message text; emphasized runs are bold (web <c>NotificationMessagePart</c>).</summary>
/// <param name="Text">Text.</param>
/// <param name="Emphasis">Bold.</param>
public sealed record NotificationMessagePart(string Text, bool Emphasis = false);

/// <summary>One chart's flags on a multi-chart row (web <c>NotificationFlagGroup</c>).</summary>
/// <param name="Instrument">Chart, drawn as the group's leading icon.</param>
/// <param name="Flags">Unique flags in event priority order.</param>
public sealed record NotificationFlagGroup(Instrument Instrument, IReadOnlyList<NotificationFlagKind> Flags)
{
    /// <summary>Chart label.</summary>
    public string Label => Instrument.Label();

    /// <summary>Screen-reader text (web group <c>aria-label</c>), e.g. "Lead: New High Score, Rank Up".</summary>
    public string AccessibleText => $"{Label}: {string.Join(", ", Flags.Select(f => f.Label()))}";
}

/// <summary>A row ready for display.</summary>
/// <param name="Id">Notification GUID.</param>
/// <param name="Title">Title, e.g. "Song · Lead".</param>
/// <param name="Message">Message; statement-style rows separate their clauses with a blank line (web <c>pre-line</c>).</param>
/// <param name="DetectedAt">Detection time.</param>
/// <param name="Destination">Navigation target, if any.</param>
/// <param name="AlbumArt">Leading media: the song's art (web "song" / "songInstrumentGrid"), if any.</param>
/// <param name="MediaInstrument">Leading media when there is no art: the instrument (web "soloInstrument"; Lead when the row names none).</param>
public sealed record NotificationPresentation(
    string Id, string Title, string Message, DateTimeOffset DetectedAt, NotificationDestination? Destination,
    string? AlbumArt = null, Instrument? MediaInstrument = null)
{
    /// <summary>Charts drawn under the art when the row touches several (empty otherwise).</summary>
    public IReadOnlyList<Instrument> GridInstruments { get; init; } = [];

    /// <summary><see cref="Message"/> split into plain and bold runs.</summary>
    public IReadOnlyList<NotificationMessagePart>? MessageParts { get; init; }

    /// <summary>Unique flags across every displayed event, in priority order (empty for shop songs).</summary>
    public IReadOnlyList<NotificationFlagKind> Flags { get; init; } = [];

    /// <summary>Per-chart flags for multi-chart song rows (web <c>flagGroups</c>); when present they replace <see cref="Flags"/>.</summary>
    public IReadOnlyList<NotificationFlagGroup> FlagGroups { get; init; } = [];

    /// <summary>Leading media kind.</summary>
    public NotificationMediaKind MediaKind => AlbumArt is null ? NotificationMediaKind.SoloInstrument
        : GridInstruments.Count > 1 ? NotificationMediaKind.SongInstrumentGrid : NotificationMediaKind.Song;

    /// <summary>Message runs, or the whole message as one plain run.</summary>
    public IReadOnlyList<NotificationMessagePart> Parts => MessageParts ?? [new(Message)];

    /// <summary>Whether the row shows any flag chip.</summary>
    public bool HasFlags => Flags.Count > 0 || FlagGroups.Count > 0;

    /// <summary>
    /// The chips as screen-reader text: each group's "Chart: Flag, Flag", else the flags comma-separated; empty when the row
    /// has none.
    /// </summary>
    public string FlagsText => FlagGroups.Count > 0
        ? string.Join(". ", FlagGroups.Select(g => g.AccessibleText))
        : string.Join(", ", Flags.Select(f => f.Label()));
}

/// <summary>
/// The player-scoped port of the web <c>notificationText.ts</c> / <c>en.json</c> copy engine: every coalesced event
/// (plus Full Combo / gold stars derived from a score's result), multi-chart, rank-update and instrument-aggregate
/// statements, emphasis and per-chart flag groups. Band and combo copy are not ported; unknown kinds fall back to
/// "New improvement detected.".
/// </summary>
public static class NotificationText
{
    #region Copy
    private static readonly Dictionary<string, string> Templates = new()
    {
        ["player_first_score"] = "Your first {instrument} play on {song} scored {newScore} points",
        ["player_score_pb"] = "You set a new personal best on {instrument} for {song} with {newScore} points",
        ["player_song_rank_improved"] = "You climbed from {oldRank} to {newRank} on {instrument} for {song}",
        ["player_stars_improved"] = "You improved from {oldStars} to {newStars} stars on {instrument} for {song}",
        ["player_gold_stars_achieved"] = "You earned gold stars on {instrument} for {song}",
        ["player_fc_achieved"] = "You got a Full Combo on {instrument} for {song}",
        ["player_difficulty_bumped"] = "You improved your difficulty on {instrument} for {song} from {oldDifficulty} to {newDifficulty}",
        ["player_weighted_rank_improved"] = "You moved up from {oldRank} to {newRank} in {instrument} percentile rankings, weighted by number of entries",
        ["player_skill_rank_improved"] = "You moved up from {oldRank} to {newRank} in {instrument} adjusted percentile rankings",
        ["player_total_score_rank_improved"] = "You moved up from {oldRank} to {newRank} in {instrument} total score rankings",
        ["player_fc_rate_rank_improved"] = "You moved up from {oldRank} to {newRank} in {instrument} Full Combo rankings",
        ["player_max_score_rank_improved"] = "You moved up from {oldRank} to {newRank} in {instrument} max score rankings",
        ["player_total_score_improved"] = "Your {instrument} total score increased to {newScore} points",
        ["player_fc_count_improved"] = "Your {instrument} Full Combo count increased to {newCount}",
    };

    /// <summary>Secondary clauses (web <c>notifications.copy.detail.*</c>).</summary>
    private static readonly Dictionary<string, string> Details = new()
    {
        ["player_first_score"] = "your first play scored {newScore} points and started at {newRank}",
        ["player_score_pb"] = "your play set a new personal best with {newScore} points",
        ["player_song_rank_improved"] = "climbed from {oldRank} to {newRank}",
        ["player_stars_improved"] = "improved from {oldStars} to {newStars} stars",
        ["player_gold_stars_achieved"] = "earned gold stars",
        ["player_fc_achieved"] = "got a Full Combo",
        ["player_difficulty_bumped"] = "improved difficulty from {oldDifficulty} to {newDifficulty}",
    };

    private static readonly Dictionary<string, string> RankNames = new()
    {
        ["player_weighted_rank_improved"] = "Weighted Percentile Rank",
        ["player_skill_rank_improved"] = "Adjusted Percentile Rank",
        ["player_total_score_rank_improved"] = "Total Score Rank",
        ["player_fc_rate_rank_improved"] = "Full Combo Rank",
        ["player_max_score_rank_improved"] = "Max Score % Rank",
    };

    /// <summary>Display order (web <c>EVENT_PRIORITY</c>; unknown kinds last).</summary>
    private static readonly Dictionary<string, int> Priorities = new()
    {
        ["player_first_score"] = 10,
        ["player_score_pb"] = 20,
        ["player_fc_achieved"] = 30,
        ["player_gold_stars_achieved"] = 40,
        ["player_stars_improved"] = 50,
        ["player_song_rank_improved"] = 60,
        ["player_difficulty_bumped"] = 70,
        ["player_total_score_improved"] = 75,
        ["player_fc_count_improved"] = 76,
        ["player_total_score_rank_improved"] = 80,
        ["player_skill_rank_improved"] = 90,
        ["player_weighted_rank_improved"] = 100,
        ["player_fc_rate_rank_improved"] = 110,
        ["player_max_score_rank_improved"] = 120,
    };

    private static readonly HashSet<string> PlayerSongKinds =
    [
        "player_first_score", "player_score_pb", "player_song_rank_improved", "player_stars_improved",
        "player_gold_stars_achieved", "player_fc_achieved", "player_difficulty_bumped",
    ];

    private static readonly HashSet<string> ScoreResultKinds = ["player_first_score", "player_score_pb"];

    private static readonly HashSet<string> AggregateKinds =
    [
        "player_total_score_improved", "player_total_score_rank_improved", "player_fc_count_improved",
        "player_fc_rate_rank_improved", "player_skill_rank_improved", "player_weighted_rank_improved",
        "player_max_score_rank_improved",
    ];

    private static readonly HashSet<string> AggregateProgressKinds = ["player_total_score_improved", "player_fc_count_improved"];

    /// <summary>Fallback wording never emphasized (web <c>FALLBACK_EMPHASIS_TERMS</c>).</summary>
    private static readonly HashSet<string> FallbackTerms = new(
        ["this song", "a new score", "your new rank", "more", "a higher difficulty", "this instrument", "this combo", "these rankings"],
        StringComparer.Ordinal);
    #endregion

    #region Events
    /// <summary>One displayed event (web normalized <c>NotificationTextEvent</c>, player subset).</summary>
    private sealed record DisplayEvent(
        string Kind, Instrument? Instrument, string? Metric, double? OldNumeric, double? NewNumeric, double? OldRank, double? NewRank,
        string? OldLabel = null, string? NewLabel = null, bool? NewFullCombo = null, double? OldStars = null, double? NewStars = null)
    {
        public bool HasScoreResult => NewFullCombo is not null || NewStars is not null;
    }

    /// <summary>
    /// The row's events: the payload's coalesced events (each falling back to the row's chart), else the row itself, plus
    /// Full Combo / gold stars derived from a score's result, without a stars event a gold one supersedes, in priority
    /// order (web <c>getDisplayEvents</c>).
    /// </summary>
    /// <param name="item">Notification.</param>
    /// <returns>Events.</returns>
    private static List<DisplayEvent> DisplayEvents(ImprovementNotification item)
    {
        var row = item.ParsedInstrument;
        var payload = item.Payload;
        var events = (payload?.CoalescedEvents ?? [])
            .Where(e => e is not null && !string.IsNullOrWhiteSpace(e.EventKind))
            .Select(e => new DisplayEvent(e.EventKind!.Trim(), InstrumentInfo.TryParse(e.Instrument, out var i) ? i : row, Trimmed(e.Metric),
                e.OldNumeric, e.NewNumeric, e.OldRank, e.NewRank, e.OldLabel, e.NewLabel, e.NewFullCombo, e.OldStars, e.NewStars))
            .ToList();
        if (events.Count == 0)
        {
            events.Add(new(item.EventKind, row, item.Metric, item.OldNumeric, item.NewNumeric, item.OldRank, item.NewRank,
                NewFullCombo: payload?.NewFullCombo, OldStars: payload?.OldStars, NewStars: payload?.NewStars));
        }

        var fullCombos = events.Where(e => e.Kind == "player_fc_achieved").Select(e => e.Instrument).ToHashSet();
        var golds = events.Where(e => e.Kind == "player_gold_stars_achieved").Select(e => e.Instrument).ToHashSet();
        var multi = IsMultiInstrument(events);
        var derived = new List<DisplayEvent>();
        foreach (var e in events.Where(e => ScoreResultKinds.Contains(e.Kind)))
        {
            var state = ScoreResult(item, events, e, multi);
            if (state is null) continue;
            if (state.NewFullCombo == true && fullCombos.Add(e.Instrument))
                derived.Add(new("player_fc_achieved", e.Instrument, "full_combo", null, null, null, null));
            if (state.NewStars >= 6 && golds.Add(e.Instrument))
                derived.Add(new("player_gold_stars_achieved", e.Instrument, "stars", state.OldStars, state.NewStars, null, null));
        }
        return events.Concat(derived)
            .Where(e => !(e.Kind == "player_stars_improved" && golds.Contains(e.Instrument)))
            .OrderBy(e => Priority(e.Kind))
            .ToList();
    }

    /// <summary>
    /// A score event's Full Combo / stars result: its own, else the row payload's when that payload belongs to it (web
    /// <c>scoreResultState</c>).
    /// </summary>
    /// <param name="item">Notification.</param>
    /// <param name="events">Coalesced events.</param>
    /// <param name="e">Score event.</param>
    /// <param name="multi">Whether the row spans several charts.</param>
    /// <returns>The result, or <see langword="null"/>.</returns>
    private static DisplayEvent? ScoreResult(ImprovementNotification item, List<DisplayEvent> events, DisplayEvent e, bool multi)
    {
        if (e.HasScoreResult) return e;
        var matchesRow = MatchesRow(item, e);
        if (multi && !matchesRow) return null;
        if (events.Count(c => ScoreResultKinds.Contains(c.Kind)) != 1 && !matchesRow) return null;
        var row = item.ParsedInstrument;
        if (e.Instrument is not null && row is not null && e.Instrument != row) return null;
        var payload = item.Payload;
        if (payload?.NewFullCombo is null && payload?.NewStars is null) return null;
        return e with { NewFullCombo = payload.NewFullCombo, OldStars = payload.OldStars, NewStars = payload.NewStars };
    }

    /// <summary>Whether the coalesced event is the row's own top-level event (web <c>eventMatchesTopLevelScoreResult</c>).</summary>
    /// <param name="item">Notification.</param>
    /// <param name="e">Event.</param>
    /// <returns>Match.</returns>
    private static bool MatchesRow(ImprovementNotification item, DisplayEvent e) =>
        e.Kind == item.EventKind && item.ParsedInstrument is { } row && e.Instrument == row
        && Same(item.Metric, e.Metric) && Same(item.OldNumeric, e.OldNumeric) && Same(item.NewNumeric, e.NewNumeric)
        && Same(item.OldRank, e.OldRank) && Same(item.NewRank, e.NewRank);

    private static bool Same<T>(T? a, T? b) => a is null || b is null || EqualityComparer<T>.Default.Equals(a, b);

    private static bool Same(double? a, double? b) => a is null || b is null || a == b;

    private static int Priority(string kind) => Priorities.GetValueOrDefault(kind, 1000);

    /// <summary>Song events on more than one chart (web <c>isMultiInstrumentPlayerSongNotification</c>).</summary>
    private static bool IsMultiInstrument(IEnumerable<DisplayEvent> events) =>
        events.Where(e => PlayerSongKinds.Contains(e.Kind) && e.Instrument is not null).Select(e => e.Instrument).Distinct().Count() > 1;

    /// <summary>Only per-chart totals and ranks, including a total (web <c>isPlayerInstrumentAggregateNotification</c>).</summary>
    private static bool IsAggregate(List<DisplayEvent> events) =>
        events.Count > 1 && events.All(e => AggregateKinds.Contains(e.Kind)) && events.Any(e => AggregateProgressKinds.Contains(e.Kind));

    /// <summary>Several leaderboard-rank events (web <c>isMultiAggregateRankNotification</c>).</summary>
    private static bool IsMultiRank(List<DisplayEvent> events) => events.Count(e => RankNames.ContainsKey(e.Kind)) > 1;

    /// <summary>Song events grouped by chart in canonical chart order, each in priority order (web <c>groupedInstrumentEvents</c>).</summary>
    private static IEnumerable<IGrouping<Instrument, DisplayEvent>> ByInstrument(List<DisplayEvent> events) =>
        events.Where(e => PlayerSongKinds.Contains(e.Kind) && e.Instrument is not null)
            .GroupBy(e => e.Instrument!.Value).OrderBy(g => (int)g.Key);
    #endregion

    #region Format
    /// <summary>Formats a row.</summary>
    /// <param name="item">Notification.</param>
    /// <param name="songTitle">Catalogue title for the song, when resolved.</param>
    /// <param name="albumArt">Catalogue album art for the song, when resolved (the row's leading media); shop songs fall back to the payload's art.</param>
    /// <returns>Presentation.</returns>
    public static NotificationPresentation Format(ImprovementNotification item, string? songTitle, string? albumArt = null)
    {
        var destination = NotificationRouting.Destination(item);
        var art = Trimmed(albumArt);
        if (item.EventKind == "service_new_shop_song")
        {
            var shopTitle = Trimmed(item.Payload?.SongTitle) ?? Trimmed(songTitle) ?? "New Song";
            var artist = Trimmed(item.Payload?.Artist) ?? "Unknown Artist";
            var shopArt = art ?? Trimmed(item.Payload?.AlbumArt);
            NotificationMessagePart[] parts = [new(shopTitle, true), new(" by "), new(artist, true), new(" has been added to the Item Shop.")];
            return new(item.NotificationGuid, $"New Song · {shopTitle} - {artist}", string.Concat(parts.Select(p => p.Text)),
                item.DetectedAt, destination, shopArt, shopArt is null ? Instrument.Lead : null)
            { MessageParts = parts };
        }

        var rowLabel = item.ParsedInstrument?.Label();
        var song = Trimmed(songTitle);
        var events = DisplayEvents(item);
        var multi = IsMultiInstrument(events);
        var clauses = IsAggregate(events) ? AggregateClauses(events)
            : IsMultiRank(events) ? RankClauses(events)
            : multi ? InstrumentClauses(events, song, rowLabel)
            : events.SelectMany((e, index) => EventClauses(e, index == 0, song, rowLabel)).ToList();
        var statement = IsAggregate(events) || IsMultiRank(events) || multi;
        var texts = clauses.Select(c => c.Text).ToList();
        var message = texts.Count == 0 ? "New improvement detected." : statement ? string.Join("\n\n", texts) : Sentence(texts, ".");
        var instruments = NotificationMediaRules.SurfaceInstruments(item);
        // Web media rail: art (over an instrument grid for multi-chart rows), else the row's instrument (Lead when none).
        return new(item.NotificationGuid, Title(events, song, rowLabel, multi), message, item.DetectedAt, destination,
            art, art is null ? item.ParsedInstrument ?? Instrument.Lead : null)
        {
            GridInstruments = art is not null && instruments.Count > 1 ? instruments : [],
            MessageParts = clauses.Count == 0 ? null : Emphasize(message, clauses.SelectMany(c => c.Terms)),
            Flags = events.Select(e => FlagKind(e.Kind)).Distinct().ToList(),
            FlagGroups = multi
                ? ByInstrument(events).Select(g => new NotificationFlagGroup(g.Key, g.Select(e => FlagKind(e.Kind)).Distinct().ToList())).ToList()
                : [],
        };
    }

    /// <summary>Row title (web <c>formatNotificationTitle</c>, player rows).</summary>
    /// <param name="events">Displayed events.</param>
    /// <param name="song">Catalogue title.</param>
    /// <param name="rowLabel">Row instrument label.</param>
    /// <param name="multi">Whether the row spans several charts.</param>
    /// <returns>Title.</returns>
    private static string Title(List<DisplayEvent> events, string? song, string? rowLabel, bool multi)
    {
        if (song is not null && multi) return song;
        if (song is not null && rowLabel is not null && events.Any(e => PlayerSongKinds.Contains(e.Kind))) return $"{song} · {rowLabel}";
        if (IsAggregate(events)) return rowLabel is null ? "Instrument Updates" : $"{rowLabel} · Improvements";
        var ranks = events.Where(e => RankNames.ContainsKey(e.Kind)).ToList();
        if (ranks.Count > 1) return rowLabel is null ? "Rank Updates" : $"Rank Updates · {rowLabel}";
        if (ranks.Count == 1) return $"{RankNames[ranks[0].Kind]} Improved";
        return events.Select(e => e.Kind).FirstOrDefault(AggregateProgressKinds.Contains) switch
        {
            "player_total_score_improved" => "Total Score Improved",
            "player_fc_count_improved" => "Full Combo Count Improved",
            _ => song ?? "Notification",
        };
    }

    /// <summary>A clause and the words it bolds.</summary>
    private sealed record Clause(string Text, IReadOnlyList<string> Terms);

    /// <summary>One event's clauses: the primary sentence (plus "started at" for a first play) or a detail fragment (web <c>formatEventClauses</c>).</summary>
    private static IEnumerable<Clause> EventClauses(DisplayEvent e, bool primary, string? song, string? rowLabel)
    {
        if (!(primary ? Templates : Details).TryGetValue(e.Kind, out var template)) yield break;
        var values = Values(e, song, rowLabel);
        yield return new(Fill(template, values), EmphasisTerms(e, values));
        if (primary && e.Kind == "player_first_score") yield return new($"started at {values["newRank"]}", [values["newRank"]]);
    }

    /// <summary>"For Lead, … ." per chart (web <c>formatMultiInstrumentSongClauses</c>).</summary>
    private static List<Clause> InstrumentClauses(List<DisplayEvent> events, string? song, string? rowLabel) =>
        ByInstrument(events).Select(group =>
        {
            var label = group.Key.Label();
            var details = group.SelectMany(e => EventClauses(e, false, song, rowLabel)).ToList();
            return new Clause($"For {label}, {Sentence(details.Select(d => d.Text).ToList(), "")}.", [label, .. details.SelectMany(d => d.Terms)]);
        }).ToList();

    /// <summary>"For Total Score Rank, moved from … to … ." per rank (web <c>formatAggregateRankUpdateClauses</c>).</summary>
    private static List<Clause> RankClauses(List<DisplayEvent> events) =>
        events.Where(e => RankNames.ContainsKey(e.Kind)).Select(e =>
        {
            var (rank, oldRank, newRank) = (RankNames[e.Kind], Rank(e.OldRank), Rank(e.NewRank));
            return new Clause($"For {rank}, moved from {oldRank} to {newRank}.", [rank, oldRank, newRank]);
        }).ToList();

    /// <summary>Paired total/Full Combo statements, then skill, weighted and max-score ranks (web <c>formatPlayerInstrumentAggregateClauses</c>).</summary>
    private static List<Clause> AggregateClauses(List<DisplayEvent> events)
    {
        var byKind = new Dictionary<string, DisplayEvent>();
        foreach (var e in events) byKind[e.Kind] = e;
        var clauses = new List<Clause>();
        void Add(string? valueKind, string? rankKind, string valueText, string rankText, string bothText, string rankTerm, string fallback)
        {
            var value = valueKind is not null ? byKind.GetValueOrDefault(valueKind) : null;
            var rank = rankKind is not null ? byKind.GetValueOrDefault(rankKind) : null;
            var number = Number(value?.NewNumeric, fallback);
            var (oldRank, newRank) = (Rank(rank?.OldRank), Rank(rank?.NewRank));
            string Fill(string text) => text.Replace("{value}", number, StringComparison.Ordinal)
                .Replace("{oldRank}", oldRank, StringComparison.Ordinal).Replace("{newRank}", newRank, StringComparison.Ordinal);
            if (value is not null && rank is not null) clauses.Add(new(Fill(bothText), [number, rankTerm, oldRank, newRank]));
            else if (value is not null) clauses.Add(new(Fill(valueText), [number]));
            else if (rank is not null) clauses.Add(new(Fill(rankText), [rankTerm, oldRank, newRank]));
        }
        Add("player_total_score_improved", "player_total_score_rank_improved",
            "Your total score increased to {value} points.",
            "Your total score rank moved up from {oldRank} to {newRank}.",
            "Your total score increased to {value} points and your total score rank moved up from {oldRank} to {newRank}.",
            "total score rank", "a new score");
        Add("player_fc_count_improved", "player_fc_rate_rank_improved",
            "Your Full Combo count increased to {value}.",
            "Your Full Combo percentage rank moved up from {oldRank} to {newRank}.",
            "Your Full Combo count increased to {value} and your Full Combo percentage rank moved up from {oldRank} to {newRank}.",
            "Full Combo percentage rank", "more");
        Add(null, "player_skill_rank_improved", "", "Your adjusted percentile rank moved up from {oldRank} to {newRank}.", "",
            "adjusted percentile rank", "");
        Add(null, "player_weighted_rank_improved", "",
            "Your percentile rank, weighted by number of entries, moved up from {oldRank} to {newRank}.", "",
            "percentile rank, weighted by number of entries", "");
        Add(null, "player_max_score_rank_improved", "", "Your max score rank moved up from {oldRank} to {newRank}.", "",
            "max score rank", "");
        return clauses;
    }

    /// <summary>"a." / "a and b." / "a, b, and c." (web <c>join</c> / <c>joinFragment</c>).</summary>
    /// <param name="clauses">Clauses (at least one).</param>
    /// <param name="end">Terminal punctuation.</param>
    /// <returns>Sentence.</returns>
    private static string Sentence(List<string> clauses, string end) => clauses.Count switch
    {
        1 => clauses[0] + end,
        2 => $"{clauses[0]} and {clauses[1]}{end}",
        _ => $"{string.Join(", ", clauses.Take(clauses.Count - 1))}, and {clauses[^1]}{end}",
    };

    /// <summary>Template values with the web's fallbacks (web <c>buildValues</c>, player rows).</summary>
    private static Dictionary<string, string> Values(DisplayEvent e, string? song, string? rowLabel) => new()
    {
        ["song"] = song ?? "this song",
        ["newScore"] = Number(e.NewNumeric, "a new score"),
        ["oldScore"] = Number(e.OldNumeric, "a new score"),
        ["oldRank"] = Rank(e.OldRank),
        ["newRank"] = Rank(e.NewRank),
        ["oldStars"] = Number(e.OldNumeric, "more"),
        ["newStars"] = Number(e.NewNumeric, "more"),
        ["oldDifficulty"] = e.OldLabel ?? Number(e.OldNumeric, "a higher difficulty"),
        ["newDifficulty"] = e.NewLabel ?? Number(e.NewNumeric, "a higher difficulty"),
        ["oldCount"] = Number(e.OldNumeric, "more"),
        ["newCount"] = Number(e.NewNumeric, "more"),
        ["instrument"] = e.Instrument?.Label() ?? rowLabel ?? "this instrument",
        ["combo"] = "this combo",
        ["scope"] = rowLabel ?? "these rankings",
    };

    /// <summary>Substitutes <c>{name}</c> placeholders.</summary>
    private static string Fill(string template, Dictionary<string, string> values) =>
        values.Aggregate(template, (text, value) => text.Replace("{" + value.Key + "}", value.Value, StringComparison.Ordinal));

    /// <summary>Words bolded for an event (web <c>emphasisTermsForEvent</c>): its values, the song and the achievement wording.</summary>
    private static List<string> EmphasisTerms(DisplayEvent e, Dictionary<string, string> values)
    {
        List<string> terms =
        [
            values["newScore"], values["oldScore"], values["oldRank"], values["newRank"], values["oldDifficulty"],
            values["newDifficulty"], values["oldCount"], values["newCount"], values["instrument"], values["combo"], values["scope"],
        ];
        if (PlayerSongKinds.Contains(e.Kind)) terms.Add(values["song"]);
        switch (e.Kind)
        {
            case "player_gold_stars_achieved": terms.AddRange(["Gold Stars", "gold stars"]); break;
            case "player_fc_achieved": terms.Add("Full Combo"); break;
            case "player_stars_improved": terms.Add($"{values["oldStars"]} to {values["newStars"]} stars"); break;
        }
        return terms;
    }
    #endregion

    #region Emphasis and flags
    /// <summary>Splits text into plain and bold runs, longest term first (web <c>emphasizeText</c>).</summary>
    /// <param name="text">Message.</param>
    /// <param name="terms">Candidate terms; blanks and fallback wording are ignored.</param>
    /// <returns>Runs, adjacent runs of the same weight merged.</returns>
    public static IReadOnlyList<NotificationMessagePart> Emphasize(string text, IEnumerable<string> terms)
    {
        var candidates = terms.Select(t => t.Trim()).Where(t => t.Length > 0 && !FallbackTerms.Contains(t) && text.Contains(t, StringComparison.Ordinal))
            .Distinct(StringComparer.Ordinal).OrderByDescending(t => t.Length).ToList();
        if (candidates.Count == 0) return [new(text)];
        var parts = new List<NotificationMessagePart>();
        void Append(string chunk, bool emphasis)
        {
            if (parts.Count > 0 && parts[^1].Emphasis == emphasis) parts[^1] = parts[^1] with { Text = parts[^1].Text + chunk };
            else parts.Add(new(chunk, emphasis));
        }
        var index = 0;
        while (index < text.Length)
        {
            var term = candidates.FirstOrDefault(t => string.CompareOrdinal(text, index, t, 0, t.Length) == 0);
            if (term is not null)
            {
                Append(term, true);
                index += term.Length;
            }
            else
            {
                Append(text[index].ToString(), false);
                index++;
            }
        }
        return parts;
    }

    /// <summary>Flag label (web <c>flagKind</c> + <c>notifications.flags.*</c>).</summary>
    /// <param name="eventKind">Event kind.</param>
    /// <returns>Label.</returns>
    internal static string Flag(string eventKind) => FlagKind(eventKind).Label();

    /// <summary>Flag kind (web <c>flagKind</c>).</summary>
    /// <param name="eventKind">Event kind.</param>
    /// <returns>Kind.</returns>
    public static NotificationFlagKind FlagKind(string eventKind) => eventKind switch
    {
        "player_first_score" => NotificationFlagKind.FirstPlay,
        "player_score_pb" => NotificationFlagKind.NewHighScore,
        "player_fc_achieved" => NotificationFlagKind.FullCombo,
        _ when eventKind.Contains("rank_improved", StringComparison.Ordinal) => NotificationFlagKind.RankUp,
        "player_gold_stars_achieved" => NotificationFlagKind.GoldStars,
        "player_stars_improved" => NotificationFlagKind.StarsUp,
        "player_difficulty_bumped" => NotificationFlagKind.DifficultyUp,
        "player_total_score_improved" or "player_fc_count_improved" => NotificationFlagKind.Progress,
        _ => NotificationFlagKind.Improvement,
    };
    #endregion

    #region Values
    /// <summary>JavaScript <c>toLocaleString()</c> for en-US.</summary>
    /// <param name="value">Number.</param>
    /// <param name="fallback">Text when absent.</param>
    /// <returns>Formatted number.</returns>
    internal static string Number(double? value, string fallback) =>
        value is { } v && double.IsFinite(v) ? v.ToString("#,##0.###", CultureInfo.GetCultureInfo("en-US")) : fallback;

    /// <summary>Rank as <c>#1,234</c>, or "your new rank".</summary>
    /// <param name="rank">Rank.</param>
    /// <returns>Formatted rank.</returns>
    internal static string Rank(double? rank) => rank is { } r && double.IsFinite(r) ? "#" + Number(r, "") : "your new rank";

    /// <summary>Trims, mapping blank to null.</summary>
    /// <param name="text">Text.</param>
    /// <returns>Trimmed text or null.</returns>
    private static string? Trimmed(string? text) => string.IsNullOrWhiteSpace(text) ? null : text.Trim();
    #endregion
}
#endregion
