namespace Festival.Core.Domain;

#region Invalid-score resolution
/// <summary>Why a chart's shown score is not the player's raw best (web <c>InvalidReason</c>).</summary>
public enum InvalidScoreReason
{
    /// <summary>The raw score is invalid; the next valid score is shown.</summary>
    Fallback,
    /// <summary>The raw score is invalid and no valid score exists at this leeway; nothing is shown.</summary>
    NoFallback,
    /// <summary>The raw invalid score is shown on purpose (Over CHOpt Threshold filter on this chart).</summary>
    OverThreshold,
}

/// <summary>The score Songs shows for one chart and why it differs from the raw score.</summary>
/// <param name="Detail">Effective score, or <see langword="null"/> when an invalid score has no valid fallback.</param>
/// <param name="Reason">Why it differs, or <see langword="null"/> for a valid raw score.</param>
public readonly record struct InvalidScoreResolution(SongScoreDetail? Detail, InvalidScoreReason? Reason);

/// <summary>
/// Filter Invalid Scores for Songs (web <c>useScoreFilter</c> + the <c>SongsPage</c> substitution; Android
/// <c>InvalidScorePolicy</c>). A score is invalid when its precomputed <c>minLeeway</c> exceeds the user's leeway or,
/// without one, when it exceeds the chart's CHOpt maximum × (1 + leeway / 100). An invalid score is replaced by the best
/// <c>validScores</c> variant valid at that leeway (rank from its <c>rankTiers</c>), else by the legacy <c>validScore</c>
/// fields, else dropped — always with an explicit reason. The data comes from the selected player's profile read and the
/// catalogue, so no per-song leaderboard read is needed.
/// </summary>
public static class InvalidScorePolicy
{
    /// <summary>Highest valid score for a chart at a leeway.</summary>
    /// <param name="song">Catalogue row.</param>
    /// <param name="chart">Chart.</param>
    /// <param name="leeway">Leeway percent.</param>
    /// <returns>Threshold, or <see langword="null"/> when the chart has no CHOpt maximum (cannot be judged).</returns>
    public static double? Threshold(Song? song, Instrument chart, double leeway) =>
        song?.MaxScore(chart) is { } max ? max * (1 + leeway / 100) : null;

    /// <summary>Whether a raw score is valid at a leeway.</summary>
    /// <param name="score">Raw wire score.</param>
    /// <param name="song">Catalogue row.</param>
    /// <param name="chart">Chart.</param>
    /// <param name="leeway">Leeway percent.</param>
    /// <returns><see langword="true"/> when valid (or not judgeable).</returns>
    public static bool IsValid(PlayerScore score, Song? song, Instrument chart, double leeway)
    {
        if (score.MinLeeway is { } min) return min <= leeway;
        return Threshold(song, chart, leeway) is not { } limit || score.Score <= limit;
    }

    /// <summary>Whether a positive raw score is over the CHOpt maximum plus leeway (web <c>!isScoreValid</c>).</summary>
    /// <param name="score">Raw score.</param>
    /// <param name="song">Catalogue row.</param>
    /// <param name="chart">Chart.</param>
    /// <param name="leeway">Leeway percent.</param>
    /// <returns><see langword="true"/> when over the threshold.</returns>
    public static bool IsOverThreshold(long score, Song? song, Instrument chart, double leeway) =>
        score > 0 && Threshold(song, chart, leeway) is { } limit && score > limit;

    /// <summary>The last rank changepoint at or below a leeway (web <c>findTier</c>).</summary>
    /// <param name="tiers">Changepoints, ascending by leeway.</param>
    /// <param name="leeway">Leeway percent.</param>
    /// <returns>Rank, or <see langword="null"/>.</returns>
    public static int? RankAt(IReadOnlyList<PlayerRankTier>? tiers, double leeway)
    {
        int? result = null;
        foreach (var tier in tiers ?? [])
        {
            if (tier.Leeway > leeway) break;
            result = tier.Rank;
        }
        return result;
    }

    /// <summary>Resolves one raw score.</summary>
    /// <param name="score">Raw wire score.</param>
    /// <param name="raw">Its unfiltered detail.</param>
    /// <param name="song">Catalogue row (CHOpt maximum).</param>
    /// <param name="chart">Chart.</param>
    /// <param name="leeway">Leeway percent.</param>
    /// <param name="showOverThreshold">Over CHOpt Threshold is on for this chart: keep the raw invalid score.</param>
    /// <returns>Effective detail and reason.</returns>
    public static InvalidScoreResolution Resolve(PlayerScore score, SongScoreDetail raw, Song? song, Instrument chart, double leeway, bool showOverThreshold)
    {
        if (IsValid(score, song, chart, leeway)) return new(raw, null);
        if (showOverThreshold) return new(raw, InvalidScoreReason.OverThreshold);
        if (score.ValidScores is { Count: > 0 } variants)
        {
            var fallback = variants.FirstOrDefault(v => v.MinLeeway <= leeway);
            if (fallback is null) return new(null, InvalidScoreReason.NoFallback);
            return new(raw with
            {
                Score = fallback.Score,
                Accuracy = fallback.Accuracy ?? raw.Accuracy,
                IsFullCombo = fallback.IsFullCombo ?? raw.IsFullCombo,
                Stars = fallback.Stars ?? raw.Stars,
                Rank = RankAt(fallback.RankTiers, leeway) ?? raw.Rank,
            }, InvalidScoreReason.Fallback);
        }
        if (score.ValidScore is not { } legacy) return new(null, InvalidScoreReason.NoFallback);
        return new(raw with
        {
            Score = legacy,
            Rank = 0,
            Accuracy = score.ValidAccuracy ?? raw.Accuracy,
            IsFullCombo = score.ValidIsFullCombo ?? raw.IsFullCombo,
        }, InvalidScoreReason.Fallback);
    }
}
#endregion
