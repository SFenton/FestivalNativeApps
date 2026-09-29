using System.Globalization;

namespace Festival.Core.Domain;

#region Inputs and result
/// <summary>Everything the Songs list depends on, captured once per rebuild.</summary>
public sealed record SongListInputs
{
    /// <summary>Validated catalogue rows.</summary>
    public required IReadOnlyList<Song> Songs { get; init; }
    /// <summary>Applied search text.</summary>
    public string? Search { get; init; }
    /// <summary>Public chart/difficulty filter.</summary>
    public SongFilter Filter { get; init; } = SongFilter.None;
    /// <summary>Saved Shop filter.</summary>
    public SongShopFilter ShopFilter { get; init; } = SongShopFilter.None;
    /// <summary>Saved selected-player filter.</summary>
    public SongPlayerScoreFilter PlayerFilter { get; init; } = SongPlayerScoreFilter.None;
    /// <summary>Saved sort mode.</summary>
    public SongSortMode Sort { get; init; } = SongSortMode.Title;
    /// <summary>Saved direction.</summary>
    public bool Ascending { get; init; } = true;
    /// <summary>Settings-visible charts.</summary>
    public IReadOnlyCollection<Instrument> Visible { get; init; } = InstrumentInfo.All;
    /// <summary>Hide Item Shop setting.</summary>
    public bool HideShop { get; init; }
    /// <summary>Offers from the catalogue's publication, or <see langword="null"/> when unavailable.</summary>
    public IReadOnlyDictionary<string, ShopSong>? Offers { get; init; }
    /// <summary>A Shop feed exists but belongs to a different publication than the catalogue.</summary>
    public bool ShopPublicationMismatch { get; init; }
    /// <summary>Whether a player is selected.</summary>
    public bool HasPlayer { get; init; }
    /// <summary>Filter Invalid Scores setting (raw scores cannot stand in for valid-score variants).</summary>
    public bool FilterInvalidScores { get; init; }
    /// <summary>Per-chart score facts for a matching, available index; <see langword="null"/> when unavailable.</summary>
    public Func<string, Instrument, ChartScoreFacts?>? Scores { get; init; }
}

/// <summary>Grouped rows plus the pause notices that explain any saved choice not currently applied.</summary>
/// <param name="Sections">Grouped rows (a single unlabeled group when headings would add nothing).</param>
/// <param name="Count">Row count.</param>
/// <param name="EffectiveSort">Sort actually applied (a paused Shop sort shows Title order).</param>
/// <param name="SortPaused">Why a saved Shop sort is paused, or <see langword="null"/>.</param>
/// <param name="ShopFilterPaused">Why a saved Shop filter is paused, or <see langword="null"/>.</param>
/// <param name="ScoreFilterPaused">Why saved player filters are paused, or <see langword="null"/>.</param>
/// <param name="FiltersApplied">Whether any filter actually narrowed the list.</param>
public sealed record SongListResult(
    IReadOnlyList<SongSection> Sections, int Count, SongSortMode EffectiveSort,
    string? SortPaused, string? ShopFilterPaused, string? ScoreFilterPaused, bool FiltersApplied);
#endregion

#region Pipeline
/// <summary>Search → chart filter → Shop filter → player filter → sort → group, pausing rather than guessing.</summary>
public static class SongListPipeline
{
    /// <summary>Shop section labels in bucket order.</summary>
    public const string LeavingTomorrowLabel = "Leaving Tomorrow", InShopLabel = "In Shop", NotInShopLabel = "Not In Shop";

    /// <summary>Has FC section labels (web <c>songs.quickLinks.fc</c>/<c>noFc</c>, <c>filter.noScore</c>).</summary>
    public const string FcLabel = "FC", NoFcLabel = "No FC", NoScoreLabel = "No Score";

    /// <summary>Runs the pipeline.</summary>
    /// <param name="input">Captured inputs.</param>
    /// <returns>Rows, sections and notices.</returns>
    public static SongListResult Run(SongListInputs input)
    {
        IReadOnlyList<Song> rows = [.. input.Songs.Where(s => SongSearch.Matches(s, input.Search) && input.Filter.Matches(s))];

        var shopPaused = input.ShopFilter.IsActive ? ShopPauseReason(input, "filters") : null;
        if (input.ShopFilter.IsActive && shopPaused is null) rows = input.ShopFilter.Filter(rows, input.Offers);

        var scorePaused = ScorePauseReason(input);
        var scoped = input.PlayerFilter.ScopedTo(input.Visible);
        if (scorePaused is null && scoped.IsActive)
            rows = scoped.Filter(rows, input.Scores!, input.Visible, input.Filter.Instrument);

        var sortPaused = input.Sort == SongSortMode.Shop ? ShopPauseReason(input, "sort") : null;
        var effective = input.Sort == SongSortMode.Shop && sortPaused is not null ? SongSortMode.Title : input.Sort;
        var sorted = rows.ToList();
        var fcFacts = effective == SongSortMode.HasFC ? FcFacts(input) : null;
        if (effective == SongSortMode.Shop)
        {
            var offers = input.Offers!;
            sorted.Sort((a, b) => CompareShop(a, b, offers, input.Ascending));
        }
        else if (effective == SongSortMode.HasFC)
        {
            sorted.Sort((a, b) => CompareHasFC(a, b, fcFacts, input.Ascending));
        }
        else
        {
            sorted.Sort((a, b) => SongCatalogQuery.Compare(a, b, effective, input.Ascending));
        }

        var sections = effective switch
        {
            SongSortMode.Shop => ShopSections(sorted, input.Offers!),
            SongSortMode.HasFC => HasFCSections(sorted, fcFacts),
            _ => SongCatalogQuery.Sections(sorted, effective),
        };
        var applied = input.Filter.IsActive || (input.ShopFilter.IsActive && shopPaused is null) || (scoped.IsActive && scorePaused is null);
        return new SongListResult(sections, sorted.Count, effective, sortPaused, shopPaused, scorePaused, applied);
    }

    /// <summary>Shop ordering: members first when ascending; ties title → artist → year → ID; descending reverses all.</summary>
    /// <param name="left">First song.</param>
    /// <param name="right">Second song.</param>
    /// <param name="offers">Validated membership.</param>
    /// <param name="ascending">Direction.</param>
    /// <returns>Sign of the ordering.</returns>
    public static int CompareShop(Song left, Song right, IReadOnlyDictionary<string, ShopSong> offers, bool ascending)
    {
        var culture = CultureInfo.CurrentCulture.CompareInfo;
        var primary = offers.ContainsKey(right.SongId).CompareTo(offers.ContainsKey(left.SongId));
        if (primary == 0) primary = culture.Compare(left.Title, right.Title, CompareOptions.IgnoreCase);
        if (primary == 0) primary = culture.Compare(left.Artist, right.Artist, CompareOptions.IgnoreCase);
        if (primary == 0) primary = (left.Year ?? 0).CompareTo(right.Year ?? 0);
        if (primary == 0) primary = string.CompareOrdinal(left.SongId, right.SongId);
        return ascending ? primary : -primary;
    }

    /// <summary>Score facts on the filtered chart, or <see langword="null"/> when Has FC falls back to title order.</summary>
    /// <param name="input">Inputs.</param>
    /// <returns>Lookup by song ID.</returns>
    private static Func<string, ChartScoreFacts?>? FcFacts(SongListInputs input)
    {
        if (!input.HasPlayer || input.Scores is not { } scores || input.Filter.ScopedTo(input.Visible).Instrument is not { } chart) return null;
        return songId => scores(songId, chart);
    }

    /// <summary>
    /// Has FC ordering (web <c>compareByMode</c> for <c>hasfc</c>): scored rows before unscored, then non-FC before FC;
    /// ties by title then ID; descending reverses all. Without facts every row ties, giving title order.
    /// </summary>
    /// <param name="left">First song.</param>
    /// <param name="right">Second song.</param>
    /// <param name="facts">Filtered-chart facts, or <see langword="null"/>.</param>
    /// <param name="ascending">Direction.</param>
    /// <returns>Sign of the ordering.</returns>
    public static int CompareHasFC(Song left, Song right, Func<string, ChartScoreFacts?>? facts, bool ascending)
    {
        var primary = 0;
        if (facts is not null)
        {
            var a = Scored(facts(left.SongId));
            var b = Scored(facts(right.SongId));
            primary = (a, b) switch
            {
                (null, null) => 0,
                (null, _) => 1,
                (_, null) => -1,
                _ => (a.Value.IsFullCombo == true).CompareTo(b.Value.IsFullCombo == true),
            };
        }
        if (primary == 0) primary = CultureInfo.CurrentCulture.CompareInfo.Compare(left.Title, right.Title, CompareOptions.IgnoreCase);
        if (primary == 0) primary = string.CompareOrdinal(left.SongId, right.SongId);
        return ascending ? primary : -primary;
    }

    /// <summary>First-seen FC / No FC / No Score buckets; headings only when two or more exist.</summary>
    /// <param name="sorted">Rows sorted by Has FC.</param>
    /// <param name="facts">Filtered-chart facts, or <see langword="null"/> (every row is No Score).</param>
    /// <returns>Sections.</returns>
    public static IReadOnlyList<SongSection> HasFCSections(IReadOnlyList<Song> sorted, Func<string, ChartScoreFacts?>? facts) =>
        Buckets(sorted, song => Scored(facts?.Invoke(song.SongId)) is not { } f ? NoScoreLabel : f.IsFullCombo == true ? FcLabel : NoFcLabel);

    /// <summary>Only a positive score counts as scored (web <c>getHasFcBucket</c>).</summary>
    /// <param name="facts">Facts.</param>
    /// <returns>The facts, or <see langword="null"/> when unscored.</returns>
    private static ChartScoreFacts? Scored(ChartScoreFacts? facts) => facts is { Score: > 0 } ? facts : null;

    /// <summary>First-seen Leaving Tomorrow / In Shop / Not In Shop buckets; headings only when two or more exist.</summary>
    /// <param name="sorted">Rows sorted by Shop.</param>
    /// <param name="offers">Validated offers.</param>
    /// <returns>Sections (one unlabeled section when only one bucket is present).</returns>
    public static IReadOnlyList<SongSection> ShopSections(IReadOnlyList<Song> sorted, IReadOnlyDictionary<string, ShopSong> offers) =>
        Buckets(sorted, song => offers.TryGetValue(song.SongId, out var offer)
            ? offer.LeavingTomorrow ? LeavingTomorrowLabel : InShopLabel
            : NotInShopLabel);

    /// <summary>Groups rows into first-seen labelled buckets; one unlabeled section when only one bucket is present.</summary>
    /// <param name="sorted">Sorted rows.</param>
    /// <param name="labelFor">Bucket label per row.</param>
    /// <returns>Sections.</returns>
    private static IReadOnlyList<SongSection> Buckets(IReadOnlyList<Song> sorted, Func<Song, string> labelFor)
    {
        var order = new List<string>();
        var buckets = new Dictionary<string, List<Song>>();
        foreach (var song in sorted)
        {
            var label = labelFor(song);
            if (!buckets.TryGetValue(label, out var list))
            {
                buckets[label] = list = [];
                order.Add(label);
            }
            list.Add(song);
        }
        if (order.Count == 1) return [new SongSection("", buckets[order[0]])];
        return [.. order.Select(label => new SongSection(label, buckets[label]))];
    }

    /// <summary>Why Shop data cannot currently drive a saved Shop choice.</summary>
    /// <param name="input">Inputs.</param>
    /// <param name="what">"sort" or "filters".</param>
    /// <returns>Readable notice, or <see langword="null"/> when Shop data applies.</returns>
    private static string? ShopPauseReason(SongListInputs input, string what)
    {
        var fallback = what == "sort" ? "Showing title order" : "Showing all songs";
        if (input.HideShop) return $"Item Shop {what} paused while the Item Shop is hidden. {fallback}; your choice is saved.";
        if (input.ShopPublicationMismatch)
            return $"Item Shop {what} paused until songs and Item Shop data update together. {fallback}; your choice is saved.";
        if (input.Offers is null) return $"Item Shop {what} paused until Item Shop data loads. {fallback}; your choice is saved.";
        return null;
    }

    /// <summary>Why saved player filters cannot currently apply.</summary>
    /// <param name="input">Inputs.</param>
    /// <returns>Readable notice, or <see langword="null"/> when they apply (or none are set).</returns>
    private static string? ScorePauseReason(SongListInputs input)
    {
        if (!input.PlayerFilter.IsActive) return null;
        if (!input.PlayerFilter.ScopedTo(input.Visible).IsActive)
            return "Player score filters paused while their instruments are hidden in Settings. Your choices are saved.";
        if (!input.HasPlayer) return "Player score filters paused until a player is selected.";
        if (input.FilterInvalidScores)
            return "Player score filters paused while Filter Invalid Scores is on. Published raw scores can't stand in for validated scores.";
        if (input.Scores is null)
            return "Player score filters paused until the player's scores and songs are from the same update. Showing songs without score filters.";
        return null;
    }
}
#endregion
