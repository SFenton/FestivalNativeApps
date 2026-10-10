namespace Festival.Core.ViewModels;

#region Row item
/// <summary>One Songs row with everything the template shows, computed once per list rebuild.</summary>
public sealed class SongRowItem
{
    /// <summary>Creates a row.</summary>
    /// <param name="song">Catalogue row.</param>
    public SongRowItem(Song song) => Song = song;

    /// <summary>Catalogue row.</summary>
    public Song Song { get; }

    /// <summary>Title.</summary>
    public string Title => Song.Title;

    /// <summary>Artist · year · duration.</summary>
    public string Subtitle => Song.Subtitle;

    /// <summary>Same-publication Shop accent, if any.</summary>
    public ShopHighlight? Highlight { get; init; }

    /// <summary>Same-publication Item Shop member with highlighting on (the row's pulsing border; web <c>shopHighlight</c>).</summary>
    public bool InShop { get; init; }

    /// <summary>Border pulse for this row, or <see langword="null"/> when it is not highlighted.</summary>
    public SongRowShopPulse? Pulse => SongRowShopPulse.For(InShop, Highlight);

    /// <summary>Selected-player status chips (empty when chips don't apply).</summary>
    public IReadOnlyList<SongInstrumentBadge> Chips { get; init; } = [];

    /// <summary>Chart the metadata/filter cell describes, if any.</summary>
    public Instrument? Chart { get; init; }

    /// <summary>Raw difficulty for the chart meter (single-chart filter without metadata).</summary>
    public double? ChartRaw { get; init; }

    /// <summary>Selected-player metadata pills (empty when not applicable).</summary>
    public IReadOnlyList<SongMetadataField> Metadata { get; init; } = [];

    /// <summary>Explicit non-scored text ("No score", "Scores syncing", paused…), or <see langword="null"/>.</summary>
    public string? ScoreState { get; init; }

    /// <summary>Whether the chart name is spoken/shown with metadata (a non-Lead chart).</summary>
    public bool NamesChart => Chart is { } chart && chart != Instrument.Lead && Metadata.Count > 0;

    /// <summary>Whether the keys icon variant applies.</summary>
    public bool Keyboard => Song.UsesKeyboardIcon;

    /// <summary>Full row announcement: title, subtitle, Shop state, chart statuses or metadata.</summary>
    public string Announcement
    {
        get
        {
            var parts = new List<string> { Title, Subtitle };
            if (Highlight is { } h) parts.Add("Item Shop: " + h.Label());
            if (Chips.Count > 0) parts.AddRange(Chips.Select(c => c.Announcement));
            if (Metadata.Count > 0)
            {
                if (NamesChart) parts.Add(Chart!.Value.Label() + " chart");
                parts.AddRange(Metadata.Select(m => m.Announcement));
            }
            else if (Chart is { } chart && ChartRaw is { } raw)
            {
                parts.Add($"{chart.Label()}, {DifficultyScale.Announcement(raw)}");
            }
            if (ScoreState is { } state) parts.Add(state);
            return string.Join(", ", parts.Where(p => p.Length > 0));
        }
    }

    /// <summary>Whether <paramref name="other"/> shows exactly what this row shows (same song, accent, chips, metadata and state).</summary>
    /// <param name="other">Row from another rebuild.</param>
    /// <returns><see langword="true"/> when the two rows render identically.</returns>
    public bool SameContent(SongRowItem other) =>
        ReferenceEquals(this, other) ||
        (Equals(Song, other.Song) && Highlight == other.Highlight && InShop == other.InShop && Chart == other.Chart &&
         ChartRaw == other.ChartRaw && ScoreState == other.ScoreState && Chips.SequenceEqual(other.Chips) &&
         Metadata.SequenceEqual(other.Metadata));
}

/// <summary>A grouped list section of row items.</summary>
/// <param name="Label">Header ("" hides the header).</param>
/// <param name="Rows">Rows.</param>
/// <param name="AutomationId">Heading automation ID (Item Shop buckets), or empty.</param>
public sealed record SongRowSection(string Label, IReadOnlyList<SongRowItem> Rows, string AutomationId = "")
{
    /// <summary>
    /// Whether two section lists render identically. Songs keeps its current list when a rebuild changes nothing, so a
    /// returning page keeps its item objects and its scroll place (back-keeps-place R2/R3, issue #560).
    /// </summary>
    /// <param name="current">Shown sections.</param>
    /// <param name="next">Freshly projected sections.</param>
    /// <returns><see langword="true"/> when every label, heading ID and row matches in order.</returns>
    public static bool SameContent(IReadOnlyList<SongRowSection> current, IReadOnlyList<SongRowSection> next)
    {
        if (ReferenceEquals(current, next)) return true;
        if (current.Count != next.Count) return false;
        for (var i = 0; i < current.Count; i++)
        {
            var (a, b) = (current[i], next[i]);
            if (a.Label != b.Label || a.AutomationId != b.AutomationId || a.Rows.Count != b.Rows.Count) return false;
            for (var r = 0; r < a.Rows.Count; r++)
                if (!a.Rows[r].SameContent(b.Rows[r])) return false;
        }
        return true;
    }
}

/// <summary>A notice above the Songs list: a saved choice that can't apply right now, or the player-score state.</summary>
/// <param name="AutomationId">Cross-platform test ID (<c>fst.songs.sort-paused</c>, <c>fst.songs.filter-paused</c>, …).</param>
/// <param name="Message">Readable text.</param>
public sealed record SongNotice(string AutomationId, string Message)
{
    /// <summary>Player scores unavailable (syncing, denied, publication mismatch).</summary>
    public const string ProfilePausedId = "fst.songs.profile-paused";

    /// <summary>A saved Item Shop sort shows Title order.</summary>
    public const string SortPausedId = "fst.songs.sort-paused";

    /// <summary>A saved Item Shop filter isn't applied.</summary>
    public const string ShopFilterPausedId = "fst.songs.filter-paused";

    /// <summary>Saved player score filters aren't applied.</summary>
    public const string ScoreFilterPausedId = "fst.songs.score-filter-paused";
}
#endregion
