namespace Festival.Core.ViewModels;

#region Score source
/// <summary>
/// The selected player's score index as Songs sees it: available only when the scores, the catalogue and the
/// session share one observed publication. Anything else (loading, 202, failure, mismatch) is an explicit state,
/// never an empty success.
/// </summary>
public sealed class SongScoreSource
{
    private SongScoreSource(bool hasPlayer, IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, PlayerScore>>? index, string? rowState, string? notice)
    {
        HasPlayer = hasPlayer;
        Available = index is not null;
        RowState = rowState;
        Notice = notice;
        if (index is null) return;
        Facts = (songId, chart) => Find(index, songId, chart) is { } s ? new ChartScoreFacts(s.Score, s.IsFullCombo) : null;
        Detail = (songId, chart) => Find(index, songId, chart) is { } s ? ToDetail(s) : null;
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

    /// <summary>Builds the source for the session's current state.</summary>
    /// <param name="session">Session.</param>
    /// <returns>Score source.</returns>
    public static SongScoreSource For(FestivalSession session)
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
                    return new(true, index, null, null);
                return new(true, null, "Player scores paused until songs update",
                    "Player scores paused until songs and scores are from the same update.");
            default:
                return new(true, null, "Loading scores", null);
        }
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
