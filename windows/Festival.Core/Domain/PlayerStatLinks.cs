namespace Festival.Core.Domain;

#region Songs presets
/// <summary>
/// A Songs filter preset opened from a player-page stat (web <c>OverallSummarySection</c> / <c>InstrumentStatsSection</c>
/// settings updaters). Overall presets reset every filter and check one box on every visible chart (web
/// <c>songsPlayedUpdater</c>/<c>fullCombosUpdater</c>); instrument presets filter to that chart and clear only its own
/// checks first (web <c>cleanFilters</c>), keeping other charts' checks and the Shop filter.
/// </summary>
/// <param name="Instrument">Chart, or <see langword="null"/> for an overall preset.</param>
/// <param name="Check">Score check to set, or <see langword="null"/> for a band-only preset.</param>
/// <param name="TopPercent">Placement band (web <c>instPercentileBucketUpdater</c>), instrument presets only.</param>
/// <param name="Stars">Star level (web <c>instStarsUpdater</c>), instrument presets only.</param>
public sealed record SongsStatPreset(Instrument? Instrument, SongScoreFilterKind? Check, int? TopPercent = null, int? Stars = null)
{
    /// <summary>Applies the preset to saved settings.</summary>
    /// <param name="settings">Current settings.</param>
    /// <returns>Settings with the Songs sort/filter replaced.</returns>
    /// <remarks>
    /// The web sorts instrument presets by Score; native Songs has no Score sort, so every preset sorts by Title
    /// ascending (the iPhone and Android ports do the same).
    /// </remarks>
    public AppSettings ApplyTo(AppSettings settings)
    {
        var visible = settings.VisibleInstruments;
        if (Instrument is not { } chart)
        {
            return settings with
            {
                SongFilter = SongFilter.None,
                ShopFilter = SongShopFilter.None,
                PlayerScoreFilter = Check is { } all ? SongPlayerScoreFilter.None.WithAll(all, visible, true) : SongPlayerScoreFilter.None,
                ScoreBandFilter = null,
                SongSort = SongSortMode.Title,
                SongSortAscending = true,
            };
        }
        var current = settings.PlayerScoreFilter.IsValid ? settings.PlayerScoreFilter : SongPlayerScoreFilter.None;
        var cleaned = SongScoreFilterKindInfo.All.Aggregate(current, (filter, kind) => filter.With(kind, chart, false));
        var band = new SongScoreBandFilter(chart, TopPercent, Stars);
        return settings with
        {
            SongFilter = new SongFilter(chart),
            PlayerScoreFilter = Check is { } check ? cleaned.With(check, chart, true) : cleaned,
            ScoreBandFilter = band.IsActive ? band : null,
            // Web percentile rows keep the sort mode (ascending); every other preset sorts, which natively means Title.
            SongSort = TopPercent is not null && Stars is null ? settings.SongSort : SongSortMode.Title,
            SongSortAscending = true,
        };
    }
}
#endregion

#region Stat links
/// <summary>Where a clickable player-page stat leads (web <c>StatBox.onClick</c>).</summary>
public abstract record PlayerStatLink
{
    private PlayerStatLink()
    {
    }

    /// <summary>Whether following the link first selects the shown player (web <c>withProfileSwitch</c> for Songs presets).</summary>
    public abstract bool RequiresSelection { get; }

    /// <summary>Destination for the tile's help text, e.g. "Opens Songs filtered to Lead".</summary>
    public abstract string Hint { get; }

    /// <summary>Songs with a filter preset (Songs Played, Full Combos).</summary>
    /// <param name="Preset">Preset.</param>
    public sealed record Songs(SongsStatPreset Preset) : PlayerStatLink
    {
        /// <inheritdoc />
        public override bool RequiresSelection => true;

        /// <inheritdoc />
        public override string Hint => Preset switch
        {
            { Instrument: { } chart, TopPercent: { } top } => $"Opens {chart.Label()} songs in the {SongScoreBandFilter.BandLabel(top)}",
            { Instrument: { } chart, Stars: { } stars } => $"Opens {chart.Label()} songs with {SongScoreBandFilter.StarsLabel(stars)}",
            { Instrument: { } chart } => $"Opens Songs filtered to {chart.Label()}",
            _ => "Opens Songs filtered",
        };
    }

    /// <summary>A song's detail page (Best Rank).</summary>
    /// <param name="SongId">Song.</param>
    /// <param name="Instrument">Chart holding the rank.</param>
    public sealed record SongDetail(string SongId, Instrument Instrument) : PlayerStatLink
    {
        /// <inheritdoc />
        public override bool RequiresSelection => false;

        /// <inheritdoc />
        public override string Hint => "Opens the song";

        /// <summary>Route.</summary>
        public AppRoute Route => new AppRoute.SongDetail(SongId, Instrument);
    }

    /// <summary>The chart's full Total Score rankings (Global Rank), on the page holding <paramref name="Rank"/> when known.</summary>
    /// <param name="Instrument">Chart.</param>
    /// <param name="Rank">The player's Total Score rank, if known.</param>
    public sealed record FullRankings(Instrument Instrument, int? Rank = null) : PlayerStatLink
    {
        /// <inheritdoc />
        public override bool RequiresSelection => false;

        /// <inheritdoc />
        public override string Hint => $"Opens {Instrument.Label()} rankings";

        /// <summary>Route (web <c>rankBy=totalscore</c>).</summary>
        public AppRoute Route => new AppRoute.FullRankings(Instrument, "totalscore", LeaderboardPaging.PageForRank(Rank ?? 0));
    }
}

/// <summary>What the page must do before following a link.</summary>
public enum PlayerLinkStep
{
    /// <summary>Not followable now (selection paused for a Songs preset).</summary>
    Blocked,
    /// <summary>Follow at once.</summary>
    Go,
    /// <summary>Select the shown player first, then follow.</summary>
    SelectThenGo,
    /// <summary>Confirm switching away from another selected player, select, then follow.</summary>
    ConfirmSwitchThenGo,
}

/// <summary>Select-first rules for player-page links (web <c>withProfileSwitch</c>; Apple Lane AP3).</summary>
public static class PlayerLinkPolicy
{
    /// <summary>Plans a link for the page's identity state.</summary>
    /// <param name="link">Link.</param>
    /// <param name="isSelected">Shown player is the selected one.</param>
    /// <param name="canSelect">A verified, current read can be selected.</param>
    /// <param name="hasOtherSelection">Another player is selected.</param>
    /// <returns>Step.</returns>
    public static PlayerLinkStep Plan(PlayerStatLink link, bool isSelected, bool canSelect, bool hasOtherSelection)
    {
        if (isSelected) return PlayerLinkStep.Go;
        if (canSelect) return hasOtherSelection ? PlayerLinkStep.ConfirmSwitchThenGo : PlayerLinkStep.SelectThenGo;
        // Selection paused: Songs presets would filter someone else's scores; other destinations still open.
        return link.RequiresSelection ? PlayerLinkStep.Blocked : PlayerLinkStep.Go;
    }
}
#endregion
