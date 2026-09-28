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
}

/// <summary>A grouped list section of row items.</summary>
/// <param name="Label">Header ("" hides the header).</param>
/// <param name="Rows">Rows.</param>
public sealed record SongRowSection(string Label, IReadOnlyList<SongRowItem> Rows);
#endregion
