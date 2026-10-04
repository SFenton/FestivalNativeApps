using System.Text.Json.Serialization;

namespace Festival.Core.Domain;

#region Shop filter
/// <summary>
/// Applied public Item Shop availability filter: two independent toggles. Leaving Tomorrow offers count as available.
/// Independent of any selected player's scores and inert while the Item Shop is hidden.
/// </summary>
public sealed record SongShopFilter
{
    /// <summary>The inactive default.</summary>
    public static SongShopFilter None { get; } = new(available: true, unavailable: true);

    /// <summary>Creates a normalized filter.</summary>
    /// <param name="available">Whether songs with a same-publication Shop offer are shown.</param>
    /// <param name="unavailable">Whether songs without a same-publication Shop offer are shown.</param>
    public SongShopFilter(bool available = true, bool unavailable = true)
    {
        AvailableValue = available;
        UnavailableValue = unavailable;
    }

    /// <summary>Creates the serializer entry point. Missing availability fields are repaired by <see cref="Normalized"/>.</summary>
    public SongShopFilter()
    {
    }

    /// <summary>Saved "Available in Item Shop" toggle. Null means the key was absent in an older settings file.</summary>
    [JsonPropertyName("available")] public bool? AvailableValue { get; set; }

    /// <summary>Saved "Not Available in Item Shop" toggle. Null means the key was absent in an older settings file.</summary>
    [JsonPropertyName("unavailable")] public bool? UnavailableValue { get; set; }

    /// <summary>Settings v2 legacy "In Shop" toggle, read only for migration.</summary>
    [JsonPropertyName("inShop")] public bool? LegacyInShop { get; set; }

    /// <summary>Settings v2 legacy "Leaving Tomorrow" toggle, read only for migration.</summary>
    [JsonPropertyName("leavingTomorrow")] public bool? LegacyLeavingTomorrow { get; set; }

    /// <summary>Whether songs with a same-publication Shop offer are shown.</summary>
    [JsonIgnore] public bool Available => AvailableValue ?? true;

    /// <summary>Whether songs without a same-publication Shop offer are shown.</summary>
    [JsonIgnore] public bool Unavailable =>
        UnavailableValue ?? (AvailableValue is null && (LegacyInShop == true || LegacyLeavingTomorrow == true) ? false : true);

    /// <summary>Whether either availability toggle hides rows.</summary>
    [JsonIgnore] public bool IsActive => !Available || !Unavailable;

    /// <summary>Returns a v3-only shape, migrating v2 In Shop/Leaving Tomorrow to "available only".</summary>
    /// <returns>Normalized filter.</returns>
    public SongShopFilter Normalized() => new(Available, Unavailable);

    /// <summary>Filters rows without changing their order.</summary>
    /// <param name="songs">Rows in their current order.</param>
    /// <param name="offers">Validated offers from the catalogue's publication; <see langword="null"/> means unavailable, not empty.</param>
    /// <returns>Matching rows (a validated empty Shop yields an honest empty list).</returns>
    /// <exception cref="InvalidOperationException">An active filter has no validated feed (callers pause instead).</exception>
    public IReadOnlyList<Song> Filter(IReadOnlyList<Song> songs, IReadOnlyDictionary<string, ShopSong>? offers)
    {
        if (!IsActive) return songs;
        if (offers is null) throw new InvalidOperationException("Shop filter requires a validated feed.");
        if (!Available && !Unavailable) return [];
        return [.. songs.Where(s => offers.ContainsKey(s.SongId) ? Available : Unavailable)];
    }

    /// <summary>Content equality over the effective v3 toggles only.</summary>
    /// <param name="other">Other filter.</param>
    /// <returns><see langword="true"/> when equivalent.</returns>
    public bool Equals(SongShopFilter? other) => other is not null && Available == other.Available && Unavailable == other.Unavailable;

    /// <summary>Hash consistent with <see cref="Equals(SongShopFilter?)"/>.</summary>
    /// <returns>Hash code.</returns>
    public override int GetHashCode() => HashCode.Combine(Available, Unavailable);
}
#endregion

#region General filter
/// <summary>Year, duration and Double Bass filters that apply with or without a selected profile.</summary>
public sealed record SongGeneralFilter
{
    /// <summary>The inactive default.</summary>
    public static SongGeneralFilter None { get; } = new();

    /// <summary>Hidden release decades (e.g. 1980). Missing/invalid years are excluded while any decade is hidden.</summary>
    [JsonPropertyName("excludedDecades")] public IReadOnlyList<int> ExcludedDecades { get; set; } = [];

    /// <summary>Hidden duration minute buckets 0…10. Missing/invalid durations are excluded while any bucket is hidden.</summary>
    [JsonPropertyName("excludedDurationBuckets")] public IReadOnlyList<int> ExcludedDurationBuckets { get; set; } = [];

    /// <summary>Whether songs with Double Bass support are shown.</summary>
    [JsonPropertyName("doubleBassSupported")] public bool DoubleBassSupported { get; set; } = true;

    /// <summary>Whether songs without Double Bass support are shown.</summary>
    [JsonPropertyName("doubleBassUnsupported")] public bool DoubleBassUnsupported { get; set; } = true;

    /// <summary>Whether this filter changes the list.</summary>
    [JsonIgnore] public bool IsActive =>
        ExcludedDecades.Count > 0 || ExcludedDurationBuckets.Count > 0 || !DoubleBassSupported || !DoubleBassUnsupported;

    /// <summary>Whether saved keys are bounded, known and duplicate-free.</summary>
    [JsonIgnore] public bool IsValid =>
        AreValidDecades(ExcludedDecades) && AreValidDurationBuckets(ExcludedDurationBuckets);

    /// <summary>Repairs nullable lists from hand-edited JSON while preserving corruption for the Reset prompt.</summary>
    /// <param name="saved">Saved filter.</param>
    /// <returns>Filter with non-null lists.</returns>
    public static SongGeneralFilter Repaired(SongGeneralFilter? saved) => saved is null ? None : saved with
    {
        ExcludedDecades = saved.ExcludedDecades ?? [-1],
        ExcludedDurationBuckets = saved.ExcludedDurationBuckets ?? [-1],
    };

    /// <summary>Normalizes key order for stable persistence.</summary>
    /// <returns>Normalized filter.</returns>
    public SongGeneralFilter Normalized() => this with
    {
        ExcludedDecades = [.. ExcludedDecades.Distinct().Order()],
        ExcludedDurationBuckets = [.. ExcludedDurationBuckets.Distinct().Order()],
    };

    /// <summary>Whether a song passes the selected General filters.</summary>
    /// <param name="song">Catalogue row.</param>
    /// <returns><see langword="true"/> when kept.</returns>
    public bool Matches(Song song)
    {
        if (ExcludedDecades.Count > 0)
        {
            if (SongGeneralBuckets.DecadeOf(song.Year) is not { } decade || ExcludedDecades.Contains(decade)) return false;
        }
        if (ExcludedDurationBuckets.Count > 0)
        {
            if (SongGeneralBuckets.DurationBucketOf(song.DurationSeconds) is not { } bucket || ExcludedDurationBuckets.Contains(bucket)) return false;
        }
        if (!DoubleBassSupported || !DoubleBassUnsupported)
        {
            if (!DoubleBassSupported && !DoubleBassUnsupported) return false;
            if (song.DoubleBassSupported is not { } supported) return false;
            if (supported && !DoubleBassSupported) return false;
            if (!supported && !DoubleBassUnsupported) return false;
        }
        return true;
    }

    private static bool AreValidDecades(IReadOnlyList<int>? keys) =>
        keys is not null && keys.Count <= 1000 && keys.All(k => k > 0 && k < 10000 && k % 10 == 0) &&
        keys.Distinct().Count() == keys.Count;

    private static bool AreValidDurationBuckets(IReadOnlyList<int>? keys) =>
        keys is not null && keys.Count <= 11 && keys.All(k => k is >= 0 and <= 10) && keys.Distinct().Count() == keys.Count;

    /// <summary>Content equality for saved key lists and toggles.</summary>
    /// <param name="other">Other filter.</param>
    /// <returns><see langword="true"/> when equivalent.</returns>
    public bool Equals(SongGeneralFilter? other) =>
        other is not null && ExcludedDecades.SequenceEqual(other.ExcludedDecades) &&
        ExcludedDurationBuckets.SequenceEqual(other.ExcludedDurationBuckets) &&
        DoubleBassSupported == other.DoubleBassSupported && DoubleBassUnsupported == other.DoubleBassUnsupported;

    /// <summary>Hash consistent with <see cref="Equals(SongGeneralFilter?)"/>.</summary>
    /// <returns>Hash code.</returns>
    public override int GetHashCode() => HashCode.Combine(
        ExcludedDecades.Count, ExcludedDurationBuckets.Count, DoubleBassSupported, DoubleBassUnsupported);
}

/// <summary>Catalogue-derived keys and labels for the Songs filter's General section.</summary>
public static class SongGeneralBuckets
{
    /// <summary>Release decade for a positive year.</summary>
    /// <param name="year">Release year.</param>
    /// <returns>Decade key, or <see langword="null"/>.</returns>
    public static int? DecadeOf(int? year) => year is > 0 and { } y ? y / 10 * 10 : null;

    /// <summary>Duration minute bucket for a positive duration.</summary>
    /// <param name="seconds">Duration in seconds.</param>
    /// <returns>Bucket 0…10, or <see langword="null"/>.</returns>
    public static int? DurationBucketOf(int? seconds) => seconds is > 0 and { } s ? Math.Min(10, s / 60) : null;

    /// <summary>Decade options present in the catalogue.</summary>
    /// <param name="songs">Catalogue rows.</param>
    /// <returns>Sorted decade keys.</returns>
    public static IReadOnlyList<int> Decades(IEnumerable<Song> songs) => [.. songs.Select(s => DecadeOf(s.Year)).OfType<int>().Distinct().Order()];

    /// <summary>Duration options: 0…9 always, plus 10 only when a song is at least ten minutes.</summary>
    /// <param name="songs">Catalogue rows.</param>
    /// <returns>Bucket keys.</returns>
    public static IReadOnlyList<int> DurationBuckets(IEnumerable<Song> songs) =>
        songs.Select(s => DurationBucketOf(s.DurationSeconds)).Any(b => b == 10) ? [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10] : [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

    /// <summary>User-facing decade label.</summary>
    /// <param name="decade">Decade key.</param>
    /// <returns>Label.</returns>
    public static string DecadeLabel(int decade) => $"{decade}s";

    /// <summary>User-facing duration label.</summary>
    /// <param name="bucket">Minute bucket.</param>
    /// <returns>Label.</returns>
    public static string DurationLabel(int bucket) => bucket switch
    {
        0 => "Under 1 Minute",
        10 => "10+ Minutes",
        _ => $"{bucket}-{bucket + 1} Minutes",
    };
}
#endregion

#region Player score filter
/// <summary>The independent per-chart checks (source <c>FilterModal</c>).</summary>
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
    /// <summary>
    /// A raw score over the chart's CHOpt maximum plus leeway (web <c>overThreshold</c>); only while Filter Invalid Scores
    /// is on, where it shows that chart's raw invalid scores instead of their valid fallbacks.
    /// </summary>
    OverThreshold,
}

/// <summary>Labels for <see cref="SongScoreFilterKind"/>.</summary>
public static class SongScoreFilterKindInfo
{
    /// <summary>All kinds in form order.</summary>
    public static IReadOnlyList<SongScoreFilterKind> All { get; } = Enum.GetValues<SongScoreFilterKind>();

    /// <summary>The kinds the filter form offers: Over CHOpt Threshold only while Filter Invalid Scores is on (web).</summary>
    /// <param name="filterInvalidScores">Filter Invalid Scores setting.</param>
    /// <returns>Kinds in form order.</returns>
    public static IReadOnlyList<SongScoreFilterKind> Offered(bool filterInvalidScores) =>
        filterInvalidScores ? All : [.. All.Where(k => k != SongScoreFilterKind.OverThreshold)];

    /// <summary>Title Case label.</summary>
    /// <param name="kind">Kind.</param>
    /// <returns>Label.</returns>
    public static string Label(this SongScoreFilterKind kind) => kind switch
    {
        SongScoreFilterKind.MissingScores => "Missing Scores",
        SongScoreFilterKind.HasScores => "Has Scores",
        SongScoreFilterKind.MissingFCs => "Missing FCs",
        SongScoreFilterKind.OverThreshold => "Over CHOpt Threshold",
        _ => "Has FCs",
    };
}

/// <summary>One chart's score facts used by filters and status chips.</summary>
/// <param name="Score">Score (0 or absent row = no score).</param>
/// <param name="IsFullCombo">Explicit FC flag (never inferred from accuracy).</param>
/// <param name="OverThreshold">The score shown is a raw score over the CHOpt maximum plus leeway (Over CHOpt Threshold view).</param>
public readonly record struct ChartScoreFacts(long Score, bool? IsFullCombo, bool OverThreshold = false);

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
    /// <summary>Charts showing only raw scores over the CHOpt threshold (applies only with Filter Invalid Scores on).</summary>
    [JsonPropertyName("overThreshold")] public IReadOnlyList<Instrument> OverThreshold { get; set; } = [];
    /// <summary>Hidden season buckets on the selected instrument (0 = no score).</summary>
    [JsonPropertyName("excludedSeasons")] public IReadOnlyList<int> ExcludedSeasons { get; set; } = [];
    /// <summary>Hidden percentile buckets (<see cref="SongBuckets.PercentileKeys"/>).</summary>
    [JsonPropertyName("excludedPercentiles")] public IReadOnlyList<int> ExcludedPercentiles { get; set; } = [];
    /// <summary>Hidden star buckets (<see cref="SongBuckets.StarKeys"/>).</summary>
    [JsonPropertyName("excludedStars")] public IReadOnlyList<int> ExcludedStars { get; set; } = [];

    /// <summary>Whether any check or bucket is set.</summary>
    [JsonIgnore]
    public bool IsActive => HasChecks || HasBucketChecks;

    /// <summary>Whether any per-chart score/FC check is set.</summary>
    [JsonIgnore]
    public bool HasChecks => Lists().Any(l => l.Count > 0);

    /// <summary>Whether a Season, Percentile or Stars bucket is hidden (these need one selected instrument).</summary>
    [JsonIgnore]
    public bool HasBucketChecks => ExcludedSeasons.Count > 0 || ExcludedPercentiles.Count > 0 || ExcludedStars.Count > 0;

    /// <summary>Whether the saved lists are bounded, known and duplicate-free (corrupt data needs an explicit Reset).</summary>
    [JsonIgnore]
    public bool IsValid =>
        Lists().All(l => l is not null && l.Count <= InstrumentInfo.All.Count && l.All(Enum.IsDefined) && l.Distinct().Count() == l.Count) &&
        SongBuckets.AreValid(SongBucketKind.Season, ExcludedSeasons) && SongBuckets.AreValid(SongBucketKind.Percentile, ExcludedPercentiles) &&
        SongBuckets.AreValid(SongBucketKind.Stars, ExcludedStars);

    /// <summary>Whether this filter narrows the list for a selected instrument (buckets need one, like the web).</summary>
    /// <param name="selectedInstrument">Songs instrument, or <see langword="null"/>.</param>
    /// <returns><see langword="true"/> when something applies.</returns>
    public bool AppliesTo(Instrument? selectedInstrument) => HasChecks || (HasBucketChecks && selectedInstrument is not null);

    /// <summary>
    /// Makes a deserialized filter safe to inspect: <see langword="null"/> becomes the default, and a <c>null</c> list (only
    /// possible in hand-edited or corrupt JSON) becomes an unknown value so <see cref="IsValid"/> fails and Songs asks for
    /// an explicit Reset instead of guessing.
    /// </summary>
    /// <param name="saved">Deserialized filter.</param>
    /// <returns>A filter whose lists are never <see langword="null"/>.</returns>
    public static SongPlayerScoreFilter Repaired(SongPlayerScoreFilter? saved)
    {
        if (saved is null) return None;
        IReadOnlyList<Instrument> Charts(IReadOnlyList<Instrument>? list) => list ?? [(Instrument)(-1)];
        IReadOnlyList<int> Keys(IReadOnlyList<int>? list) => list ?? [-1];
        return new SongPlayerScoreFilter
        {
            MissingScores = Charts(saved.MissingScores), HasScores = Charts(saved.HasScores),
            MissingFCs = Charts(saved.MissingFCs), HasFCs = Charts(saved.HasFCs), OverThreshold = Charts(saved.OverThreshold),
            ExcludedSeasons = Keys(saved.ExcludedSeasons), ExcludedPercentiles = Keys(saved.ExcludedPercentiles),
            ExcludedStars = Keys(saved.ExcludedStars),
        };
    }

    /// <summary>Hidden keys of one player-scoped bucket section.</summary>
    /// <param name="kind">Season, Percentile or Stars.</param>
    /// <returns>Hidden keys (none for Intensity, which lives on <see cref="SongFilter"/>).</returns>
    public IReadOnlyList<int> Excluded(SongBucketKind kind) => kind switch
    {
        SongBucketKind.Season => ExcludedSeasons,
        SongBucketKind.Percentile => ExcludedPercentiles,
        SongBucketKind.Stars => ExcludedStars,
        _ => [],
    };

    /// <summary>Replaces one section's hidden keys.</summary>
    /// <param name="kind">Season, Percentile or Stars.</param>
    /// <param name="keys">Hidden keys.</param>
    /// <returns>Updated filter.</returns>
    public SongPlayerScoreFilter WithExcluded(SongBucketKind kind, IEnumerable<int> keys) => kind switch
    {
        SongBucketKind.Season => this with { ExcludedSeasons = SongBuckets.Normalize(keys) },
        SongBucketKind.Percentile => this with { ExcludedPercentiles = SongBuckets.Normalize(keys) },
        SongBucketKind.Stars => this with { ExcludedStars = SongBuckets.Normalize(keys) },
        _ => this,
    };

    /// <summary>
    /// Web <c>cleanFilters</c> for a stat preset: every bucket shown again and this chart's checks cleared (other charts'
    /// checks stay).
    /// </summary>
    /// <param name="instrument">Chart.</param>
    /// <returns>Updated filter.</returns>
    public SongPlayerScoreFilter CleanedFor(Instrument instrument) =>
        SongScoreFilterKindInfo.All.Aggregate(this with { ExcludedSeasons = [], ExcludedPercentiles = [], ExcludedStars = [] },
            (filter, kind) => filter.With(kind, instrument, false));

    /// <summary>Shows only one bucket of a section (web <c>buildStarFilter</c>/<c>buildPercentileFilter</c>).</summary>
    /// <param name="kind">Percentile or Stars.</param>
    /// <param name="key">The bucket to keep.</param>
    /// <returns>Updated filter.</returns>
    public SongPlayerScoreFilter Only(SongBucketKind kind, int key) => WithExcluded(kind, kind.Keys().Where(k => k != key));

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
            SongScoreFilterKind.OverThreshold => this with { OverThreshold = ordered },
            _ => this with { HasFCs = ordered },
        };
    }

    /// <summary>
    /// The filter as it applies under the current Filter Invalid Scores setting: Over CHOpt Threshold checks are inactive
    /// (kept saved) while it is off, like the web.
    /// </summary>
    /// <param name="filterInvalidScores">Filter Invalid Scores setting.</param>
    /// <returns>Effective filter.</returns>
    public SongPlayerScoreFilter Effective(bool filterInvalidScores) =>
        filterInvalidScores || OverThreshold.Count == 0 ? this : this with { OverThreshold = [] };

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
    public SongPlayerScoreFilter ScopedTo(IReadOnlyCollection<Instrument> visible) => this with
    {
        MissingScores = [.. MissingScores.Where(visible.Contains)],
        HasScores = [.. HasScores.Where(visible.Contains)],
        MissingFCs = [.. MissingFCs.Where(visible.Contains)],
        HasFCs = [.. HasFCs.Where(visible.Contains)],
        OverThreshold = [.. OverThreshold.Where(visible.Contains)],
    };

    /// <summary>
    /// Applies OR across active charted instruments and AND within each chart's checks; then, with a selected visible
    /// instrument and <paramref name="details"/>, its Season / Percentile / Stars buckets (web <c>useFilteredSongs</c>).
    /// </summary>
    /// <param name="songs">Search-, chart- and Shop-filtered rows.</param>
    /// <param name="scores">Score facts for a matching, available index (<see langword="null"/> for no row).</param>
    /// <param name="visible">Settings-visible charts.</param>
    /// <param name="selectedInstrument">Optional single-chart Songs filter.</param>
    /// <param name="details">Score details for the bucket checks (same availability rule as <paramref name="scores"/>).</param>
    /// <returns>Matching rows in source order.</returns>
    public IReadOnlyList<Song> Filter(
        IReadOnlyList<Song> songs, Func<string, Instrument, ChartScoreFacts?> scores,
        IReadOnlyCollection<Instrument> visible, Instrument? selectedInstrument,
        Func<string, Instrument, SongScoreDetail?>? details = null)
    {
        var scoped = ScopedTo(visible);
        var charts = InstrumentInfo.All
            .Where(c => (selectedInstrument is null || selectedInstrument == c) && scoped.Lists().Any(l => l.Contains(c)))
            .ToArray();
        Instrument? bucketChart = details is not null && HasBucketChecks && selectedInstrument is { } s && visible.Contains(s) ? s : null;
        if (charts.Length == 0 && bucketChart is null) return songs;
        return [.. songs.Where(song =>
            (charts.Length == 0 || charts.Any(chart => scoped.Matches(song, chart, scores(song.SongId, chart)))) &&
            (bucketChart is not { } chart || InBuckets(details!(song.SongId, chart))))];
    }

    /// <summary>Whether a score falls in shown Season, Percentile and Stars buckets.</summary>
    /// <param name="detail">The selected player's score on the chart, or <see langword="null"/>.</param>
    /// <returns><see langword="true"/> when no section hides it.</returns>
    public bool InBuckets(SongScoreDetail? detail) =>
        !ExcludedSeasons.Contains(SongBuckets.SeasonOf(detail)) &&
        !ExcludedPercentiles.Contains(SongBuckets.PercentileOf(detail)) &&
        !ExcludedStars.Contains(SongBuckets.StarsOf(detail));

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
        // Web: passes only when the shown (raw) score is positive and over the CHOpt maximum plus leeway.
        var overMatches = !OverThreshold.Contains(chart) || (scored && facts!.Value.OverThreshold);
        return scoreMatches && comboMatches && overMatches;
    }

    /// <summary>The list for one check.</summary>
    /// <param name="kind">Check.</param>
    /// <returns>Chart list.</returns>
    private IReadOnlyList<Instrument> List(SongScoreFilterKind kind) => kind switch
    {
        SongScoreFilterKind.MissingScores => MissingScores,
        SongScoreFilterKind.HasScores => HasScores,
        SongScoreFilterKind.MissingFCs => MissingFCs,
        SongScoreFilterKind.OverThreshold => OverThreshold,
        _ => HasFCs,
    };

    /// <summary>All five lists.</summary>
    /// <returns>Lists in kind order.</returns>
    private IEnumerable<IReadOnlyList<Instrument>> Lists() => [MissingScores, HasScores, MissingFCs, HasFCs, OverThreshold];

    /// <summary>Content equality for every list.</summary>
    /// <param name="other">Other filter.</param>
    /// <returns><see langword="true"/> when every list matches.</returns>
    public bool Equals(SongPlayerScoreFilter? other) =>
        other is not null && MissingScores.SequenceEqual(other.MissingScores) && HasScores.SequenceEqual(other.HasScores) &&
        MissingFCs.SequenceEqual(other.MissingFCs) && HasFCs.SequenceEqual(other.HasFCs) && OverThreshold.SequenceEqual(other.OverThreshold) &&
        ExcludedSeasons.SequenceEqual(other.ExcludedSeasons) && ExcludedPercentiles.SequenceEqual(other.ExcludedPercentiles) &&
        ExcludedStars.SequenceEqual(other.ExcludedStars);

    /// <summary>Hash consistent with <see cref="Equals(SongPlayerScoreFilter?)"/>.</summary>
    /// <returns>Hash code.</returns>
    public override int GetHashCode() => HashCode.Combine(
        MissingScores.Count, HasScores.Count, MissingFCs.Count, HasFCs.Count + 31 * OverThreshold.Count, ExcludedSeasons.Count, ExcludedPercentiles.Count,
        ExcludedStars.Count);
}
#endregion

#region Shop view
/// <summary>Item Shop layout preference (compact windows always use the grid).</summary>
public enum ShopViewMode
{
    /// <summary>Artwork grid.</summary>
    Grid,
    /// <summary>Compact list.</summary>
    List,
}
#endregion
