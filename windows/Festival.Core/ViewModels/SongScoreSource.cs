namespace Festival.Core.ViewModels;

#region Score source
/// <summary>
/// The selected player's score index as Songs sees it: available only when the scores, the catalogue and the
/// session share one observed publication. Anything else (loading, 202, failure, mismatch) is an explicit state,
/// never an empty success.
/// </summary>
public sealed class SongScoreSource
{
    private SongScoreSource(bool hasPlayer, IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, PlayerScore>>? index, string? rowState, string? notice,
        InvalidScoreContext? invalid = null)
    {
        HasPlayer = hasPlayer;
        Available = index is not null;
        RowState = rowState;
        Notice = notice;
        if (index is null) return;
        if (invalid is null)
        {
            Facts = (songId, chart) => Find(index, songId, chart) is { } s ? new ChartScoreFacts(s.Score, s.IsFullCombo) : null;
            Detail = (songId, chart) => Find(index, songId, chart) is { } s ? ToDetail(s) : null;
            Reason = (_, _) => null;
            return;
        }
        // Filter Invalid Scores: every lookup goes through the web's leeway-aware substitution.
        InvalidScoreResolution? Resolve(string songId, Instrument chart) =>
            Find(index, songId, chart) is { } s ? invalid.Resolve(s, songId, chart) : null;
        Facts = (songId, chart) => Resolve(songId, chart) is { Detail: { } d } r
            ? d.Facts with { OverThreshold = r.Reason == InvalidScoreReason.OverThreshold } : null;
        Detail = (songId, chart) => Resolve(songId, chart)?.Detail;
        Reason = (songId, chart) => Resolve(songId, chart)?.Reason;
    }

    /// <summary>Whether a player is selected.</summary>
    public bool HasPlayer { get; }

    /// <summary>Whether a matching, available index backs <see cref="Facts"/> and <see cref="Detail"/>.</summary>
    public bool Available { get; }

    /// <summary>Per-row text while scores are unavailable (e.g. "Scores syncing").</summary>
    public string? RowState { get; }

    /// <summary>List-level notice while scores are unavailable, or <see langword="null"/>.</summary>
    public string? Notice { get; }

    /// <summary>Filter/chip facts lookup, only when available.</summary>
    public Func<string, Instrument, ChartScoreFacts?>? Facts { get; }

    /// <summary>Metadata detail lookup, only when available.</summary>
    public Func<string, Instrument, SongScoreDetail?>? Detail { get; }

    /// <summary>Why a chart's shown score differs from the raw score (Filter Invalid Scores), only when available.</summary>
    public Func<string, Instrument, InvalidScoreReason?>? Reason { get; }

    /// <summary>Builds the source for the session's current state.</summary>
    /// <param name="session">Session.</param>
    /// <returns>Score source.</returns>
    public static SongScoreSource For(FestivalSession session) => For(session, null);

    /// <summary>
    /// Builds the Songs source: with Filter Invalid Scores on, scores resolve through <see cref="InvalidScorePolicy"/>
    /// (valid fallback, dropped, or the raw score on charts whose Over CHOpt Threshold check is set).
    /// </summary>
    /// <param name="session">Session.</param>
    /// <param name="songs">Catalogue rows (CHOpt maxima), or <see langword="null"/> for raw scores.</param>
    /// <returns>Score source.</returns>
    public static SongScoreSource ForSongs(FestivalSession session, IReadOnlyList<Song>? songs)
    {
        var settings = session.Settings;
        if (!settings.FilterInvalidScores || songs is null) return For(session, null);
        var overThreshold = settings.PlayerScoreFilter.IsValid
            ? settings.PlayerScoreFilter.ScopedTo(settings.VisibleInstruments).OverThreshold
            : [];
        return For(session, new InvalidScoreContext(songs, settings.Leeway, overThreshold));
    }

    /// <summary>Builds the source, optionally resolving invalid scores.</summary>
    /// <param name="session">Session.</param>
    /// <param name="invalid">Invalid-score context, or <see langword="null"/> for raw scores.</param>
    /// <returns>Score source.</returns>
    private static SongScoreSource For(FestivalSession session, InvalidScoreContext? invalid)
    {
        if (!session.HasPlayer) return new(false, null, null, null);
        switch (session.SelectedProfileStatus)
        {
            case SelectedProfileStatus.Syncing:
                return new(true, null, "Scores syncing", "This player's scores are still syncing. Scores appear once they're published.");
            case SelectedProfileStatus.Failed:
                return new(true, null, "Scores unavailable",
                    "Player scores unavailable: " + (session.SelectedProfileIssue?.Message ?? "Something went wrong."));
            case SelectedProfileStatus.Available:
                if (session.SelectedScoreIndex is { } index && session.IsSelectedProfileCurrent &&
                    SongRelatedPublicationPolicy.Matches(session.CatalogPublicationId, session.SelectedProfilePublicationId, session.ObservedPublicationId))
                    return new(true, index, null, null, invalid);
                return new(true, null, "Player scores paused until songs update",
                    "Player scores paused until songs and scores are from the same update.");
            default:
                return new(true, null, "Loading scores", null);
        }
    }

    /// <summary>What <see cref="InvalidScorePolicy"/> needs for one rebuild: CHOpt maxima, leeway and the raw-score charts.</summary>
    private sealed class InvalidScoreContext
    {
        private readonly Dictionary<string, Song> songs;
        private readonly double leeway;
        private readonly HashSet<Instrument> overThreshold;

        /// <summary>Captures the context.</summary>
        /// <param name="songs">Catalogue rows.</param>
        /// <param name="leeway">Leeway percent.</param>
        /// <param name="overThreshold">Charts whose raw invalid scores stay (Over CHOpt Threshold checks).</param>
        public InvalidScoreContext(IReadOnlyList<Song> songs, double leeway, IEnumerable<Instrument> overThreshold)
        {
            this.songs = new Dictionary<string, Song>(StringComparer.Ordinal);
            foreach (var song in songs) this.songs.TryAdd(song.SongId, song);
            this.leeway = leeway;
            this.overThreshold = [.. overThreshold];
        }

        /// <summary>Resolves one raw score.</summary>
        /// <param name="score">Raw score.</param>
        /// <param name="songId">Song.</param>
        /// <param name="chart">Chart.</param>
        /// <returns>Resolution.</returns>
        public InvalidScoreResolution Resolve(PlayerScore score, string songId, Instrument chart) =>
            InvalidScorePolicy.Resolve(score, ToDetail(score), songs.GetValueOrDefault(songId), chart, leeway, overThreshold.Contains(chart));
    }

    /// <summary>Loads (or reuses) the selected player's scores; failures are recorded by the session.</summary>
    /// <param name="session">Session.</param>
    /// <param name="force">Re-read.</param>
    /// <returns>Load task.</returns>
    public static async Task LoadAsync(FestivalSession session, bool force = false)
    {
        if (!session.HasPlayer) return;
        try
        {
            await session.LoadSelectedProfileAsync(force);
        }
        catch (FestivalApiException)
        {
            // Publication bootstrap failure: the session keeps its explicit state.
        }
    }

    /// <summary>Whether a session property change affects Songs rows.</summary>
    /// <param name="propertyName">Changed property.</param>
    /// <returns><see langword="true"/> for score-state properties.</returns>
    public static bool AffectsRows(string? propertyName) => propertyName is nameof(FestivalSession.SelectedProfileStatus) or
        nameof(FestivalSession.SelectedProfile) or nameof(FestivalSession.SelectedScoreIndex) or nameof(FestivalSession.ObservedPublicationId);

    /// <summary>Maps a validated wire score to the row detail (valid last-played preferred).</summary>
    /// <param name="score">Wire row.</param>
    /// <returns>Detail.</returns>
    public static SongScoreDetail ToDetail(PlayerScore score) => new(
        score.Score, score.Accuracy, score.IsFullCombo, score.Stars, score.Season, score.Difficulty, score.Rank, score.TotalEntries,
        score.ValidLastPlayedAt ?? score.LastPlayedAt);

    /// <summary>Looks up one chart's row.</summary>
    /// <param name="index">Score index.</param>
    /// <param name="songId">Song.</param>
    /// <param name="chart">Chart.</param>
    /// <returns>Row or <see langword="null"/>.</returns>
    private static PlayerScore? Find(IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, PlayerScore>> index, string songId, Instrument chart) =>
        index.TryGetValue(songId, out var charts) && charts.TryGetValue(chart, out var score) ? score : null;
}
#endregion
