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
/// <c>validScores</c> variant valid at that leeway (rank from its <c>rankTiers</c>, population from the catalogue's
/// <c>populationTiers</c>), else by the legacy <c>validScore</c> fields, else dropped — always with an explicit reason. The data comes from the selected player's profile read and the
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
        if (score.ValidScores is { Count: > 0 }) return Variant(score, raw, song, chart, leeway);
        return Legacy(score, raw);
    }

    /// <summary>
    /// Resolves one raw score by Song Details' rule (web <c>filterPlayerScores</c>, invalid-scores R4), branching on
    /// <c>minLeeway</c> like the web: when present, a score valid at the leeway stays and an invalid one is replaced
    /// only by an eligible <c>validScores</c> variant (never the legacy fields); when absent, a score within the CHOpt
    /// ceiling stays and an invalid one is replaced only by the legacy <c>validScore</c> fields (never a variant).
    /// There is no Over CHOpt Threshold exemption.
    /// </summary>
    /// <param name="score">Raw wire score.</param>
    /// <param name="raw">Its unfiltered detail.</param>
    /// <param name="song">Catalogue row (CHOpt maximum, population curve).</param>
    /// <param name="chart">Chart.</param>
    /// <param name="leeway">Leeway percent.</param>
    /// <returns>Effective detail and reason.</returns>
    public static InvalidScoreResolution ResolveFiltered(PlayerScore score, SongScoreDetail raw, Song? song, Instrument chart, double leeway)
    {
        if (score.MinLeeway is { } min)
        {
            if (min <= leeway) return new(raw, null);
            return score.ValidScores is { Count: > 0 }
                ? Variant(score, raw, song, chart, leeway)
                : new(null, InvalidScoreReason.NoFallback);
        }
        if (Threshold(song, chart, leeway) is not { } limit || score.Score <= limit) return new(raw, null);
        return Legacy(score, raw);
    }

    /// <summary>Substitutes the best <c>validScores</c> variant valid at the leeway (web <c>validScores.find</c>).</summary>
    /// <param name="score">Raw wire score with a non-empty <c>validScores</c>.</param>
    /// <param name="raw">Its unfiltered detail.</param>
    /// <param name="song">Catalogue row (population curve).</param>
    /// <param name="chart">Chart.</param>
    /// <param name="leeway">Leeway percent.</param>
    /// <returns>The variant's detail, or no score when none is eligible.</returns>
    private static InvalidScoreResolution Variant(PlayerScore score, SongScoreDetail raw, Song? song, Instrument chart, double leeway)
    {
        var fallback = score.ValidScores?.FirstOrDefault(v => v.MinLeeway <= leeway);
        if (fallback is null) return new(null, InvalidScoreReason.NoFallback);
        return new(raw with
        {
            Score = fallback.Score,
            Accuracy = fallback.Accuracy ?? raw.Accuracy,
            IsFullCombo = fallback.IsFullCombo ?? raw.IsFullCombo,
            Stars = fallback.Stars ?? raw.Stars,
            Rank = RankAt(fallback.RankTiers, leeway) ?? raw.Rank,
            TotalEntries = song?.FilteredPopulation(chart, leeway) ?? raw.TotalEntries,
        }, InvalidScoreReason.Fallback);
    }

    /// <summary>Substitutes the legacy <c>validScore*</c> fields (web legacy path).</summary>
    /// <param name="score">Raw wire score.</param>
    /// <param name="raw">Its unfiltered detail.</param>
    /// <returns>The legacy detail, or no score when <c>validScore</c> is absent.</returns>
    private static InvalidScoreResolution Legacy(PlayerScore score, SongScoreDetail raw)
    {
        if (score.ValidScore is not { } legacy) return new(null, InvalidScoreReason.NoFallback);
        return new(raw with
        {
            Score = legacy,
            Rank = score.ValidRank ?? 0,
            Accuracy = score.ValidAccuracy ?? raw.Accuracy,
            IsFullCombo = score.ValidIsFullCombo ?? raw.IsFullCombo,
            Stars = score.ValidStars ?? raw.Stars,
            TotalEntries = score.ValidTotalEntries ?? raw.TotalEntries,
        }, InvalidScoreReason.Fallback);
    }
}
#endregion

#region Warning
/// <summary>
/// A row's invalid-score indicator (web <c>InvalidScoreIcon</c>; Android <c>InvalidScoreWarning</c>): a pulsing icon that
/// opens a "Filtered Score" alert with OK and Settings. Red alert icon when a described score was replaced or dropped;
/// gold warning when every described chart shows its raw score on purpose (Over CHOpt Threshold).
/// </summary>
/// <param name="Reasons">Described charts and why their shown score differs, in service order.</param>
/// <param name="IsWarning">Gold warning (all Over CHOpt Threshold) instead of the red alert.</param>
/// <param name="Message">Alert body.</param>
public sealed record InvalidScoreWarning(IReadOnlyList<KeyValuePair<Instrument, InvalidScoreReason>> Reasons, bool IsWarning, string Message)
{
    /// <summary>Alert title (web <c>songs.invalidScoreTitle</c>).</summary>
    public const string Title = "Filtered Score";

    /// <summary>Accessible name of the icon (web <c>songs.invalidScoreAriaLabel</c>).</summary>
    public const string Label = "Invalid score indicator";

    /// <summary>Alert action that opens Settings (web <c>songs.goToSettings</c>).</summary>
    public const string SettingsCommand = "Settings";

    /// <summary>Alert dismiss action (web <c>common.ok</c>).</summary>
    public const string OkCommand = "OK";

    /// <summary>Test ID of the Filtered Score alert (Android <c>fst.songs.invalid-score.alert</c>).</summary>
    public const string AlertAutomationId = "fst.songs.invalid-score.alert";

    /// <summary>Test ID of the alert's message text.</summary>
    public const string MessageAutomationId = "fst.songs.invalid-score.message";

    /// <summary>Settings toggle named in the footer.</summary>
    private const string Toggle = "Filter Invalid Scores";

    /// <summary>Test ID of a row's indicator.</summary>
    /// <param name="songId">Row song.</param>
    /// <returns><c>fst.songs.invalid-score.&lt;songId&gt;</c>.</returns>
    public static string AutomationId(string songId) => $"fst.songs.invalid-score.{songId}";

    /// <summary>Whether two warnings render identically.</summary>
    /// <param name="other">Other warning.</param>
    /// <returns><see langword="true"/> when equal.</returns>
    public bool SameAs(InvalidScoreWarning? other) =>
        other is not null && IsWarning == other.IsWarning && Message == other.Message && Reasons.SequenceEqual(other.Reasons);

    /// <summary>
    /// Builds a row's warning, or <see langword="null"/> when the icon does not apply (web <c>SongRow</c>: with a
    /// single-chart filter only that chart is described).
    /// </summary>
    /// <param name="songTitle">Song title.</param>
    /// <param name="reasons">Every visible invalid chart's reason.</param>
    /// <param name="filterChart">Single-chart filter, or <see langword="null"/>.</param>
    /// <returns>Warning or <see langword="null"/>.</returns>
    public static InvalidScoreWarning? Of(string songTitle, IReadOnlyDictionary<Instrument, InvalidScoreReason> reasons, Instrument? filterChart)
    {
        var ordered = InstrumentInfo.All
            .Where(chart => (filterChart is null || chart == filterChart) && reasons.ContainsKey(chart))
            .Select(chart => KeyValuePair.Create(chart, reasons[chart]))
            .ToList();
        if (ordered.Count == 0) return null;
        var warning = ordered.All(r => r.Value == InvalidScoreReason.OverThreshold);
        return new(ordered, warning, Compose(songTitle, ordered, filterChart, warning));
    }

    /// <summary>The web's alert message, sentence by sentence.</summary>
    /// <param name="song">Song title.</param>
    /// <param name="ordered">Described charts.</param>
    /// <param name="filterChart">Single-chart filter.</param>
    /// <param name="allOverThreshold">Every described chart is Over CHOpt Threshold.</param>
    /// <returns>Message.</returns>
    private static string Compose(string song, List<KeyValuePair<Instrument, InvalidScoreReason>> ordered, Instrument? filterChart, bool allOverThreshold)
    {
        var names = ordered.Select(r => r.Key.Label()).ToList();
        var list = names.Count <= 2 ? string.Join(" and ", names) : $"{string.Join(", ", names.Take(names.Count - 1))}, and {names[^1]}";
        if (allOverThreshold) return $"{song} has a score on {list} that exceeds the CHOpt maximum. This is the highest unfiltered invalid score.";
        var chips = filterChart is null;
        var details = new List<string>();
        var fallbacks = ordered.Where(r => r.Value == InvalidScoreReason.Fallback).ToList();
        if (fallbacks.Count > 0)
            details.Add(!chips ? "We are showing the next valid score here."
                : fallbacks.Count == 1 ? $"The {fallbacks[0].Key.Label()} chip reflects the next valid score."
                : "The chips for these instruments reflect the next valid score.");
        foreach (var (chart, reason) in ordered.Where(r => r.Value != InvalidScoreReason.Fallback))
            details.Add(reason == InvalidScoreReason.OverThreshold
                ? $"The {chart.Label()} score shown exceeds the CHOpt maximum."
                : $"Because there is no valid other score for {chart.Label()}, the {chart.Label()} icon chip is red here.");
        var footer = ordered.Count > 1
            ? $"To see the absolute highest scores you've achieved, toggle off '{Toggle}' in App Settings."
            : $"To see the absolute highest score you've achieved, toggle off '{Toggle}' in App Settings.";
        var hint = chips
            ? "You can also temporarily filter to 'Over CHOpt Threshold' in the Filter modal when viewing scores for a specific instrument."
            : $"You can also temporarily filter to '{filterChart!.Value.Label()} Over CHOpt Threshold' in the Filter modal.";
        return $"{song} has an invalid, filtered-out score on {list}. {string.Join(" ", details)}\n\n{footer} {hint}";
    }
}
#endregion
