using System.Globalization;
using System.Text.Json.Serialization;

namespace Festival.Core.Domain;

#region Sort mode
/// <summary>Catalogue sort modes that work without a selected profile.</summary>
public enum SongSortMode
{
    /// <summary>Title.</summary>
    Title,
    /// <summary>Artist.</summary>
    Artist,
    /// <summary>Release year (missing sorts as zero).</summary>
    Year,
    /// <summary>Duration (missing sorts as zero).</summary>
    Duration,
}

/// <summary>Labels for <see cref="SongSortMode"/>.</summary>
public static class SongSortModeInfo
{
    /// <summary>All modes in menu order.</summary>
    public static IReadOnlyList<SongSortMode> All { get; } = Enum.GetValues<SongSortMode>();

    /// <summary>User-facing label.</summary>
    /// <param name="mode">Sort mode.</param>
    /// <returns>Title Case label.</returns>
    public static string Label(this SongSortMode mode) => mode switch
    {
        SongSortMode.Title => "Title",
        SongSortMode.Artist => "Artist",
        SongSortMode.Year => "Year",
        _ => "Duration",
    };
}
#endregion

#region Filter
/// <summary>
/// Public-data Songs filter: one charted instrument and an inclusive 1–7 display difficulty range for it
/// (or for any charted instrument when none is chosen). Bounded and typed so it persists safely.
/// </summary>
/// <param name="Instrument">Single chart, or <see langword="null"/> for all.</param>
/// <param name="MinDifficulty">Lowest display level, 1–7.</param>
/// <param name="MaxDifficulty">Highest display level, 1–7.</param>
public sealed record SongFilter(Instrument? Instrument = null, int MinDifficulty = 1, int MaxDifficulty = 7)
{
    /// <summary>The unfiltered default.</summary>
    public static SongFilter None { get; } = new();

    /// <summary>Whether this filter changes the list.</summary>
    [JsonIgnore]
    public bool IsActive => Instrument is not null || MinDifficulty > 1 || MaxDifficulty < 7;

    /// <summary>Whether the values are in range and ordered.</summary>
    [JsonIgnore]
    public bool IsValid => MinDifficulty is >= 1 and <= 7 && MaxDifficulty is >= 1 and <= 7 && MinDifficulty <= MaxDifficulty;

    /// <summary>Whether a song passes this filter.</summary>
    /// <param name="song">Catalogue row.</param>
    /// <returns><see langword="true"/> when kept.</returns>
    public bool Matches(Song song)
    {
        if (Instrument is { } chart)
            return song.Difficulty?.ChartedValue(chart) is { } raw && InRange(DifficultyScale.BarsForRaw(raw));
        if (MinDifficulty <= 1 && MaxDifficulty >= 7) return true;
        return InstrumentInfo.All.Any(i => song.Difficulty?.ChartedValue(i) is { } raw && InRange(DifficultyScale.BarsForRaw(raw)));
    }

    /// <summary>Drops a chart the user has hidden in Settings.</summary>
    /// <param name="visible">Settings-visible charts.</param>
    /// <returns>This filter, or one without the hidden chart.</returns>
    public SongFilter ScopedTo(IReadOnlyCollection<Instrument> visible) =>
        Instrument is { } chart && !visible.Contains(chart) ? this with { Instrument = null } : this;

    /// <summary>Whether a bar count is inside the range.</summary>
    /// <param name="bars">1–7.</param>
    /// <returns><see langword="true"/> when inside.</returns>
    private bool InRange(int bars) => bars >= MinDifficulty && bars <= MaxDifficulty;
}
#endregion

#region Pipeline
/// <summary>A grouped list section: header label plus its rows in sorted order.</summary>
/// <param name="Label">White Title Case header text.</param>
/// <param name="Songs">Rows.</param>
public sealed record SongSection(string Label, IReadOnlyList<Song> Songs);

/// <summary>Search → filter → sort → group, exactly as the web pipeline orders it.</summary>
public static class SongCatalogQuery
{
    /// <summary>Filters and sorts songs.</summary>
    /// <param name="songs">Validated catalogue.</param>
    /// <param name="search">Search text.</param>
    /// <param name="filter">Public filter.</param>
    /// <param name="mode">Sort field.</param>
    /// <param name="ascending">Direction; ties still fall back to title then song ID.</param>
    /// <returns>New ordered list.</returns>
    public static IReadOnlyList<Song> Apply(IEnumerable<Song> songs, string? search, SongFilter filter, SongSortMode mode, bool ascending)
    {
        var kept = songs.Where(s => SongSearch.Matches(s, search) && filter.Matches(s)).ToList();
        kept.Sort((a, b) => Compare(a, b, mode, ascending));
        return kept;
    }

    /// <summary>Comparison used by <see cref="Apply"/>.</summary>
    /// <param name="left">First song.</param>
    /// <param name="right">Second song.</param>
    /// <param name="mode">Sort field.</param>
    /// <param name="ascending">Direction.</param>
    /// <returns>Sign of the ordering.</returns>
    public static int Compare(Song left, Song right, SongSortMode mode, bool ascending)
    {
        var culture = CultureInfo.CurrentCulture.CompareInfo;
        var primary = mode switch
        {
            SongSortMode.Title => culture.Compare(left.Title, right.Title, CompareOptions.IgnoreCase),
            SongSortMode.Artist => culture.Compare(left.Artist, right.Artist, CompareOptions.IgnoreCase),
            SongSortMode.Year => (left.Year ?? 0).CompareTo(right.Year ?? 0),
            _ => (left.DurationSeconds ?? 0).CompareTo(right.DurationSeconds ?? 0),
        };
        if (primary == 0) primary = culture.Compare(left.Title, right.Title, CompareOptions.IgnoreCase);
        if (primary == 0) primary = string.CompareOrdinal(left.SongId, right.SongId);
        return ascending ? primary : -primary;
    }

    /// <summary>Groups sorted rows into first-seen sections for the list headers and jump index.</summary>
    /// <param name="sorted">Rows from <see cref="Apply"/>.</param>
    /// <param name="mode">The mode they were sorted by.</param>
    /// <returns>Non-empty sections in order.</returns>
    public static IReadOnlyList<SongSection> Sections(IReadOnlyList<Song> sorted, SongSortMode mode)
    {
        var result = new List<SongSection>();
        string? label = null;
        List<Song>? rows = null;
        foreach (var song in sorted)
        {
            var key = SectionKey(song, mode);
            if (key != label)
            {
                if (label is not null) result.Add(new SongSection(label, rows!));
                label = key;
                rows = [];
            }
            rows!.Add(song);
        }
        if (label is not null) result.Add(new SongSection(label, rows!));
        return result;
    }

    /// <summary>Section label for one song.</summary>
    /// <param name="song">Row.</param>
    /// <param name="mode">Sort field.</param>
    /// <returns>A–Z or #, a year, or a duration bucket.</returns>
    public static string SectionKey(Song song, SongSortMode mode) => mode switch
    {
        SongSortMode.Title => FirstLetter(song.Title),
        SongSortMode.Artist => FirstLetter(song.Artist),
        SongSortMode.Year => song.Year?.ToString(CultureInfo.InvariantCulture) ?? "Unknown Year",
        _ => DurationBucket(song.DurationSeconds),
    };

    /// <summary>Web duration quick-link bucket labels (<c>songQuickLinks.ts:193-202</c>).</summary>
    /// <param name="seconds">Duration.</param>
    /// <returns>Bucket label.</returns>
    public static string DurationBucket(int? seconds) => seconds switch
    {
        null or <= 0 => "Unknown Duration",
        < 120 => "Under 2 Minutes",
        < 180 => "2–3 Minutes",
        < 240 => "3–4 Minutes",
        < 300 => "4–5 Minutes",
        _ => "5 Minutes And Over",
    };

    /// <summary>Accent-folded uppercase A–Z initial, or <c>#</c>.</summary>
    /// <param name="text">Title or artist.</param>
    /// <returns>Single-character label.</returns>
    public static string FirstLetter(string text)
    {
        var trimmed = text.TrimStart();
        if (trimmed.Length == 0) return "#";
        // Only the first character counts (Apple SongSectionIndex): "(Don't…" and "2…" both index under #.
        var folded = trimmed[..1].Normalize(System.Text.NormalizationForm.FormKD);
        var first = char.ToUpperInvariant(folded[0]);
        return first is >= 'A' and <= 'Z' ? first.ToString() : "#";
    }
}
#endregion
