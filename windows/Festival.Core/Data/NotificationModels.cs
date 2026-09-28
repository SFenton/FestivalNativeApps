using System.Globalization;
using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Wire
/// <summary>One coalesced sub-event (web <c>NotificationTextEvent</c>; typed subset).</summary>
public sealed record NotificationEventPayload
{
    /// <summary>Event kind.</summary>
    [JsonPropertyName("eventKind")] public string? EventKind { get; init; }
    /// <summary>Service instrument key.</summary>
    [JsonPropertyName("instrument")] public string? Instrument { get; init; }
    /// <summary>Raw metric.</summary>
    [JsonPropertyName("metric")] public string? Metric { get; init; }
}

/// <summary>Typed subset of the notification <c>payload</c> object.</summary>
public sealed record NotificationPayload
{
    /// <summary>Coalesced sub-events.</summary>
    [JsonPropertyName("coalescedEvents")] public IReadOnlyList<NotificationEventPayload>? CoalescedEvents { get; init; }
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

#region Text
/// <summary>A row ready for display.</summary>
/// <param name="Id">Notification GUID.</param>
/// <param name="Title">Title, e.g. "Song · Lead".</param>
/// <param name="Message">Sentence.</param>
/// <param name="Flag">Title Case flag label (web <c>notifications.flags.*</c>), or <see langword="null"/> for shop songs.</param>
/// <param name="DetectedAt">Detection time.</param>
/// <param name="Destination">Navigation target, if any.</param>
public sealed record NotificationPresentation(
    string Id, string Title, string Message, string? Flag, DateTimeOffset DetectedAt, NotificationDestination? Destination);

/// <summary>
/// The player-scoped single-event subset of the web <c>notificationText.ts</c> / <c>en.json</c> copy engine. Band copy,
/// multi-event clause joining and flag groups are not ported; unknown kinds fall back to "New improvement detected.".
/// </summary>
public static class NotificationText
{
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

    private static readonly Dictionary<string, string> RankNames = new()
    {
        ["player_weighted_rank_improved"] = "Weighted Percentile Rank",
        ["player_skill_rank_improved"] = "Adjusted Percentile Rank",
        ["player_total_score_rank_improved"] = "Total Score Rank",
        ["player_fc_rate_rank_improved"] = "Full Combo Rank",
        ["player_max_score_rank_improved"] = "Max Score % Rank",
    };

    private static readonly HashSet<string> PlayerSongKinds =
    [
        "player_first_score", "player_score_pb", "player_song_rank_improved", "player_stars_improved",
        "player_gold_stars_achieved", "player_fc_achieved", "player_difficulty_bumped",
    ];

    /// <summary>Formats a row.</summary>
    /// <param name="item">Notification.</param>
    /// <param name="songTitle">Catalogue title for the song, when resolved.</param>
    /// <returns>Presentation.</returns>
    public static NotificationPresentation Format(ImprovementNotification item, string? songTitle)
    {
        var destination = NotificationRouting.Destination(item);
        if (item.EventKind == "service_new_shop_song")
        {
            var shopTitle = Trimmed(item.Payload?.SongTitle) ?? Trimmed(songTitle) ?? "New Song";
            var artist = Trimmed(item.Payload?.Artist) ?? "Unknown Artist";
            return new(item.NotificationGuid, $"New Song · {shopTitle} - {artist}", $"{shopTitle} by {artist} has been added to the Item Shop.",
                null, item.DetectedAt, destination);
        }

        var instrumentLabel = item.ParsedInstrument?.Label();
        var song = Trimmed(songTitle) ?? "this song";
        var message = Templates.TryGetValue(item.EventKind, out var template)
            ? Fill(template, item, song, instrumentLabel ?? "this instrument") + "."
            : "New improvement detected.";
        if (item.EventKind == "player_first_score") message = message[..^1] + $" and started at {Rank(item.NewRank)}.";
        return new(item.NotificationGuid, Title(item, songTitle, instrumentLabel), message, Flag(item.EventKind), item.DetectedAt, destination);
    }

    /// <summary>Row title (web <c>formatNotificationTitle</c>, single event).</summary>
    /// <param name="item">Notification.</param>
    /// <param name="songTitle">Catalogue title.</param>
    /// <param name="instrumentLabel">Instrument label.</param>
    /// <returns>Title.</returns>
    private static string Title(ImprovementNotification item, string? songTitle, string? instrumentLabel)
    {
        var baseTitle = Trimmed(songTitle);
        if (baseTitle is not null && instrumentLabel is not null && PlayerSongKinds.Contains(item.EventKind))
            return $"{baseTitle} · {instrumentLabel}";
        if (RankNames.TryGetValue(item.EventKind, out var rankName)) return $"{rankName} Improved";
        return item.EventKind switch
        {
            "player_total_score_improved" => "Total Score Improved",
            "player_fc_count_improved" => "Full Combo Count Improved",
            _ => baseTitle ?? "Notification",
        };
    }

    /// <summary>Flag label (web <c>flagKind</c> + <c>notifications.flags.*</c>).</summary>
    /// <param name="eventKind">Event kind.</param>
    /// <returns>Label.</returns>
    internal static string Flag(string eventKind) => eventKind switch
    {
        "player_first_score" => "First Play",
        "player_score_pb" => "New High Score",
        "player_fc_achieved" => "Full Combo",
        _ when eventKind.Contains("rank_improved", StringComparison.Ordinal) => "Rank Up",
        "player_gold_stars_achieved" => "Gold Stars",
        "player_stars_improved" => "Stars Up",
        "player_difficulty_bumped" => "Difficulty Up",
        "player_total_score_improved" or "player_fc_count_improved" => "Progress",
        _ => "Improvement",
    };

    /// <summary>Substitutes template values with the web's fallbacks.</summary>
    /// <param name="template">Template.</param>
    /// <param name="item">Notification.</param>
    /// <param name="song">Song value.</param>
    /// <param name="instrument">Instrument value.</param>
    /// <returns>Sentence without the final period.</returns>
    private static string Fill(string template, ImprovementNotification item, string song, string instrument) => template
        .Replace("{instrument}", instrument, StringComparison.Ordinal)
        .Replace("{song}", song, StringComparison.Ordinal)
        .Replace("{newScore}", Number(item.NewNumeric, "a new score"), StringComparison.Ordinal)
        .Replace("{oldRank}", Rank(item.OldRank), StringComparison.Ordinal)
        .Replace("{newRank}", Rank(item.NewRank), StringComparison.Ordinal)
        .Replace("{oldStars}", Number(item.OldNumeric, "more"), StringComparison.Ordinal)
        .Replace("{newStars}", Number(item.NewNumeric, "more"), StringComparison.Ordinal)
        .Replace("{oldDifficulty}", Number(item.OldNumeric, "a higher difficulty"), StringComparison.Ordinal)
        .Replace("{newDifficulty}", Number(item.NewNumeric, "a higher difficulty"), StringComparison.Ordinal)
        .Replace("{newCount}", Number(item.NewNumeric, "more"), StringComparison.Ordinal);

    /// <summary>JavaScript <c>toLocaleString()</c> for en-US.</summary>
    /// <param name="value">Number.</param>
    /// <param name="fallback">Text when absent.</param>
    /// <returns>Formatted number.</returns>
    internal static string Number(double? value, string fallback) =>
        value is { } v && double.IsFinite(v) ? v.ToString("#,##0.###", CultureInfo.GetCultureInfo("en-US")) : fallback;

    /// <summary>Rank as <c>#1,234</c>, or "your new rank".</summary>
    /// <param name="rank">Rank.</param>
    /// <returns>Formatted rank.</returns>
    internal static string Rank(int? rank) => rank is { } r ? "#" + r.ToString("#,##0", CultureInfo.GetCultureInfo("en-US")) : "your new rank";

    /// <summary>Trims, mapping blank to null.</summary>
    /// <param name="text">Text.</param>
    /// <returns>Trimmed text or null.</returns>
    private static string? Trimmed(string? text) => string.IsNullOrWhiteSpace(text) ? null : text.Trim();
}
#endregion
