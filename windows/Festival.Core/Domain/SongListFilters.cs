using System.Text.Json.Serialization;

namespace Festival.Core.Domain;

#region Shop filter
/// <summary>
/// Applied public Item Shop filter: two independent toggles. Leaving Tomorrow implies membership;
/// both on keep leaving offers. Independent of any selected player's scores.
/// </summary>
/// <param name="InShop">Require current Shop membership.</param>
/// <param name="LeavingTomorrow">Require an offer leaving tomorrow.</param>
public sealed record SongShopFilter(
    [property: JsonPropertyName("inShop")] bool InShop = false,
    [property: JsonPropertyName("leavingTomorrow")] bool LeavingTomorrow = false)
{
    /// <summary>The inactive default.</summary>
    public static SongShopFilter None { get; } = new();

    /// <summary>Whether either toggle is on.</summary>
    [JsonIgnore] public bool IsActive => InShop || LeavingTomorrow;

    /// <summary>Filters rows without changing their order.</summary>
    /// <param name="songs">Rows in their current order.</param>
    /// <param name="offers">Validated offers from the catalogue's publication; <see langword="null"/> means unavailable, not empty.</param>
    /// <returns>Matching rows (a validated empty Shop yields an honest empty list).</returns>
    /// <exception cref="InvalidOperationException">An active filter has no validated feed (callers pause instead).</exception>
    public IReadOnlyList<Song> Filter(IReadOnlyList<Song> songs, IReadOnlyDictionary<string, ShopSong>? offers)
    {
        if (!IsActive) return songs;
        if (offers is null) throw new InvalidOperationException("Shop filter requires a validated feed.");
        return [.. songs.Where(s => offers.TryGetValue(s.SongId, out var offer) && (!LeavingTomorrow || offer.LeavingTomorrow))];
    }
}
#endregion

#region Player score filter
/// <summary>The four independent per-chart checks (source <c>FilterModal</c>).</summary>
public enum SongScoreFilterKind
{
    /// <summary>No positive score.</summary>
    MissingScores,
    /// <summary>A positive score.</summary>
    HasScores,
    /// <summary>No explicit full-combo flag.</summary>
    MissingFCs,
    /// <summary>An explicit full-combo flag.</summary>
    HasFCs,
}

/// <summary>Labels for <see cref="SongScoreFilterKind"/>.</summary>
public static class SongScoreFilterKindInfo
{
    /// <summary>All kinds in form order.</summary>
    public static IReadOnlyList<SongScoreFilterKind> All { get; } = Enum.GetValues<SongScoreFilterKind>();

    /// <summary>Title Case label.</summary>
    /// <param name="kind">Kind.</param>
    /// <returns>Label.</returns>
    public static string Label(this SongScoreFilterKind kind) => kind switch
    {
        SongScoreFilterKind.MissingScores => "Missing Scores",
        SongScoreFilterKind.HasScores => "Has Scores",
        SongScoreFilterKind.MissingFCs => "Missing FCs",
        _ => "Has FCs",
    };
}

/// <summary>One chart's score facts used by filters and status chips.</summary>
/// <param name="Score">Score (0 or absent row = no score).</param>
/// <param name="IsFullCombo">Explicit FC flag (never inferred from accuracy).</param>
public readonly record struct ChartScoreFacts(long Score, bool? IsFullCombo);

/// <summary>
/// Selected-player predicates: AND within one chart's checks, OR across active charts. Bounded and typed so they
/// persist safely; hidden charts stay saved but inactive; cleared on confirmed deselection.
/// </summary>
public sealed record SongPlayerScoreFilter
{
    /// <summary>The inactive default.</summary>
    public static SongPlayerScoreFilter None { get; } = new();

    /// <summary>Charts requiring no positive score.</summary>
    [JsonPropertyName("missingScores")] public IReadOnlyList<Instrument> MissingScores { get; set; } = [];
    /// <summary>Charts requiring a positive score.</summary>
    [JsonPropertyName("hasScores")] public IReadOnlyList<Instrument> HasScores { get; set; } = [];
    /// <summary>Charts without an explicit FC.</summary>
    [JsonPropertyName("missingFCs")] public IReadOnlyList<Instrument> MissingFCs { get; set; } = [];
    /// <summary>Charts with an explicit FC.</summary>
    [JsonPropertyName("hasFCs")] public IReadOnlyList<Instrument> HasFCs { get; set; } = [];

    /// <summary>Whether any check is set.</summary>
    [JsonIgnore]
    public bool IsActive => Lists().Any(l => l.Count > 0);

    /// <summary>Whether the saved lists are bounded, known and duplicate-free (corrupt data needs an explicit Reset).</summary>
    [JsonIgnore]
    public bool IsValid => Lists().All(l => l is not null && l.Count <= InstrumentInfo.All.Count && l.All(Enum.IsDefined) && l.Distinct().Count() == l.Count);

    /// <summary>Whether a check is set for a chart.</summary>
    /// <param name="kind">Check.</param>
    /// <param name="instrument">Chart.</param>
    /// <returns><see langword="true"/> when set.</returns>
    public bool Contains(SongScoreFilterKind kind, Instrument instrument) => List(kind).Contains(instrument);

    /// <summary>Sets or clears one check without touching the other three.</summary>
    /// <param name="kind">Check.</param>
    /// <param name="instrument">Chart.</param>
    /// <param name="enabled">New value.</param>
    /// <returns>Updated filter (lists kept in service order).</returns>
    public SongPlayerScoreFilter With(SongScoreFilterKind kind, Instrument instrument, bool enabled)
    {
        var set = List(kind).ToHashSet();
        if (enabled) set.Add(instrument);
        else set.Remove(instrument);
        Instrument[] ordered = [.. InstrumentInfo.All.Where(set.Contains)];
        return kind switch
        {
            SongScoreFilterKind.MissingScores => this with { MissingScores = ordered },
            SongScoreFilterKind.HasScores => this with { HasScores = ordered },
            SongScoreFilterKind.MissingFCs => this with { MissingFCs = ordered },
            _ => this with { HasFCs = ordered },
        };
    }

    /// <summary>Whether every visible chart has a check (the source's global switch).</summary>
    /// <param name="kind">Check.</param>
    /// <param name="visible">Settings-visible charts.</param>
    /// <returns><see langword="true"/> when all visible charts are set.</returns>
    public bool AllVisible(SongScoreFilterKind kind, IReadOnlyCollection<Instrument> visible) =>
        visible.Count > 0 && visible.All(i => Contains(kind, i));

    /// <summary>Sets or clears a check on every visible chart only (hidden choices stay saved).</summary>
    /// <param name="kind">Check.</param>
    /// <param name="visible">Settings-visible charts.</param>
    /// <param name="enabled">New value.</param>
    /// <returns>Updated filter.</returns>
    public SongPlayerScoreFilter WithAll(SongScoreFilterKind kind, IReadOnlyCollection<Instrument> visible, bool enabled) =>
        visible.Aggregate(this, (filter, chart) => filter.With(kind, chart, enabled));

    /// <summary>The filter restricted to visible charts (hidden checks are inactive, not erased).</summary>
    /// <param name="visible">Settings-visible charts.</param>
    /// <returns>Scoped filter.</returns>
    public SongPlayerScoreFilter ScopedTo(IReadOnlyCollection<Instrument> visible) => new()
    {
        MissingScores = [.. MissingScores.Where(visible.Contains)],
        HasScores = [.. HasScores.Where(visible.Contains)],
        MissingFCs = [.. MissingFCs.Where(visible.Contains)],
        HasFCs = [.. HasFCs.Where(visible.Contains)],
    };

    /// <summary>Applies OR across active charted instruments and AND within each chart's checks.</summary>
    /// <param name="songs">Search-, chart- and Shop-filtered rows.</param>
    /// <param name="scores">Score facts for a matching, available index (<see langword="null"/> for no row).</param>
    /// <param name="visible">Settings-visible charts.</param>
    /// <param name="selectedInstrument">Optional single-chart Songs filter.</param>
    /// <returns>Matching rows in source order.</returns>
    public IReadOnlyList<Song> Filter(
        IReadOnlyList<Song> songs, Func<string, Instrument, ChartScoreFacts?> scores,
        IReadOnlyCollection<Instrument> visible, Instrument? selectedInstrument)
    {
        var scoped = ScopedTo(visible);
        var charts = InstrumentInfo.All
            .Where(c => (selectedInstrument is null || selectedInstrument == c) && scoped.Lists().Any(l => l.Contains(c)))
            .ToArray();
        if (charts.Length == 0) return songs;
        return [.. songs.Where(song => charts.Any(chart => scoped.Matches(song, chart, scores(song.SongId, chart))))];
    }

    /// <summary>Whether one chart's checks all hold for a song.</summary>
    /// <param name="song">Row.</param>
    /// <param name="chart">Chart.</param>
    /// <param name="facts">Score facts, if any.</param>
    /// <returns><see langword="true"/> when matched.</returns>
    private bool Matches(Song song, Instrument chart, ChartScoreFacts? facts)
    {
        if (!song.Supports(chart)) return false;
        var scored = facts is { Score: > 0 };
        var fullCombo = facts?.IsFullCombo == true;
        var missing = MissingScores.Contains(chart);
        var has = HasScores.Contains(chart);
        var missingFc = MissingFCs.Contains(chart);
        var hasFc = HasFCs.Contains(chart);
        var scoreMatches = !(missing || has) || (missing && !scored) || (has && scored);
        var comboMatches = !(missingFc || hasFc) || (missingFc && !fullCombo) || (hasFc && fullCombo);
        return scoreMatches && comboMatches;
    }

    /// <summary>The list for one check.</summary>
    /// <param name="kind">Check.</param>
    /// <returns>Chart list.</returns>
    private IReadOnlyList<Instrument> List(SongScoreFilterKind kind) => kind switch
    {
        SongScoreFilterKind.MissingScores => MissingScores,
        SongScoreFilterKind.HasScores => HasScores,
        SongScoreFilterKind.MissingFCs => MissingFCs,
        _ => HasFCs,
    };

    /// <summary>All four lists.</summary>
    /// <returns>Lists in kind order.</returns>
    private IEnumerable<IReadOnlyList<Instrument>> Lists() => [MissingScores, HasScores, MissingFCs, HasFCs];

    /// <summary>Content equality for the four lists.</summary>
    /// <param name="other">Other filter.</param>
    /// <returns><see langword="true"/> when every list matches.</returns>
    public bool Equals(SongPlayerScoreFilter? other) =>
        other is not null && MissingScores.SequenceEqual(other.MissingScores) && HasScores.SequenceEqual(other.HasScores) &&
        MissingFCs.SequenceEqual(other.MissingFCs) && HasFCs.SequenceEqual(other.HasFCs);

    /// <summary>Hash consistent with <see cref="Equals(SongPlayerScoreFilter?)"/>.</summary>
    /// <returns>Hash code.</returns>
    public override int GetHashCode() => HashCode.Combine(MissingScores.Count, HasScores.Count, MissingFCs.Count, HasFCs.Count);
}
#endregion

#region Shop view
/// <summary>Item Shop layout preference (compact windows always use the list).</summary>
public enum ShopViewMode
{
    /// <summary>Artwork grid.</summary>
    Grid,
    /// <summary>Compact list.</summary>
    List,
}
#endregion
