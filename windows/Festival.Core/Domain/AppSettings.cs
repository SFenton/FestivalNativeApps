using System.Text.Json.Serialization;

namespace Festival.Core.Domain;

#region Selected player
/// <summary>An explicitly selected public identity (never a merely viewed search result).</summary>
/// <param name="AccountId">Public account key.</param>
/// <param name="DisplayName">Display name at selection time.</param>
public sealed record SelectedPlayer(
    [property: JsonPropertyName("accountId")] string AccountId,
    [property: JsonPropertyName("displayName")] string DisplayName)
{
    /// <summary>Whether stored bytes are still safe to use for a GET.</summary>
    [JsonIgnore]
    public bool IsValid =>
        ProfileText.IsValidAccountId(AccountId) && DisplayName is { Length: > 0 and <= 200 } &&
        DisplayName == DisplayName.Trim() && !ProfileText.ContainsUnsafeCharacter(DisplayName);

    /// <summary>One- or two-letter initials for the title-bar avatar.</summary>
    [JsonIgnore]
    public string Initials
    {
        get
        {
            var words = DisplayName.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            var letters = words.Take(2).Select(w => char.ToUpperInvariant(w[0]));
            return string.Concat(letters);
        }
    }
}
#endregion

#region App settings
/// <summary>Persisted preferences. Everything is bounded and re-validated on load.</summary>
public sealed record AppSettings
{
    /// <summary>
    /// Current schema version. v3 (2026-10-02): Songs General filters (year, duration, Shop availability and Double Bass)
    /// persist separately from selected-instrument/player filters. v2 (2026-09-29): the Songs filter uses the web's bucket model (intensity buckets on
    /// <see cref="SongFilter"/>; season/percentile/stars buckets on <see cref="PlayerScoreFilter"/>); v1's difficulty
    /// range and single percentile/star choice (<see cref="LegacyScoreBandFilter"/>) are migrated by <see cref="Sanitized"/>.
    /// </summary>
    public const int CurrentVersion = 3;

    /// <summary>Schema version.</summary>
    [JsonPropertyName("version")] public int Version { get; set; } = CurrentVersion;

    /// <summary>Explicitly selected player, restored across restarts.</summary>
    [JsonPropertyName("selectedPlayer")] public SelectedPlayer? SelectedPlayer { get; set; }

    /// <summary>Applied Songs sort mode.</summary>
    [JsonPropertyName("songSort")] public SongSortMode SongSort { get; set; } = SongSortMode.Title;

    /// <summary>Applied Songs sort direction.</summary>
    [JsonPropertyName("songSortAscending")] public bool SongSortAscending { get; set; } = true;

    /// <summary>Applied Songs filter.</summary>
    [JsonPropertyName("songFilter")] public SongFilter SongFilter { get; set; } = SongFilter.None;

    /// <summary>Settings-visible charts (never empty).</summary>
    [JsonPropertyName("visibleInstruments")] public IReadOnlyList<Instrument> VisibleInstruments { get; set; } = InstrumentInfo.All;

    /// <summary>In-app additive override: stop artwork animation even when the system allows it.</summary>
    [JsonPropertyName("disableAnimatedArtwork")] public bool DisableAnimatedArtwork { get; set; }

    /// <summary>In-app additive override: reduce motion.</summary>
    [JsonPropertyName("reduceMotion")] public bool ReduceMotion { get; set; }

    /// <summary>In-app additive override: no artwork at all (data saving).</summary>
    [JsonPropertyName("saveData")] public bool SaveData { get; set; }

    /// <summary>Known Leaderboards Rank By metrics (web <c>RANKING_METRICS</c>).</summary>
    public static readonly IReadOnlyList<string> RankingMetrics = ["totalscore", "adjusted", "weighted", "fcrate", "maxscore"];

    /// <summary>Last Leaderboards Rank By metric (web <c>fst:leaderboardSettings</c>; navigation state, kept by Reset).</summary>
    [JsonPropertyName("leaderboardRankBy")] public string LeaderboardRankBy { get; set; } = "totalscore";

    #region App settings (Settings page; restored by Reset)
    /// <summary>Show per-chart status icons on unfiltered Songs rows.</summary>
    [JsonPropertyName("showInstrumentIcons")] public bool ShowInstrumentIcons { get; set; } = true;

    /// <summary>Song-row metadata order is independent of sort priority.</summary>
    [JsonPropertyName("enableVisualOrder")] public bool EnableVisualOrder { get; set; }

    /// <summary>Song-row metadata display order (every field exactly once).</summary>
    [JsonPropertyName("songRowVisualOrder")] public IReadOnlyList<MetadataField> SongRowVisualOrder { get; set; } = SettingsOrder.Normalize<MetadataField>(null);

    /// <summary>CHOpt text-path column order (every column exactly once).</summary>
    [JsonPropertyName("pathColumnOrder")] public IReadOnlyList<PathColumnKey> PathColumnOrder { get; set; } = SettingsOrder.Normalize<PathColumnKey>(null);

    /// <summary>Hide scores above the CHOpt maximum plus leeway.</summary>
    [JsonPropertyName("filterInvalidScores")] public bool FilterInvalidScores { get; set; }

    /// <summary>Invalid-score leeway percent, −5…+5 in 0.1 steps.</summary>
    [JsonPropertyName("leeway")] public double Leeway { get; set; } = ScoreLeeway.Default;

    /// <summary>How CHOpt paths open by default.</summary>
    [JsonPropertyName("pathDefaultView")] public PathDisplayMode PathDefaultView { get; set; } = PathDisplayMode.Image;

    /// <summary>The Paths unavailable-chart warning was dismissed.</summary>
    [JsonPropertyName("pathUnavailableWarningDismissed")] public bool PathUnavailableWarningDismissed { get; set; }

    /// <summary>Experimental leaderboard ranks (not yet available: always sanitized to off).</summary>
    [JsonPropertyName("experimentalRanks")] public bool ExperimentalRanks { get; set; }

    /// <summary>Hide the Item Shop (navigation and highlights; the highlight preference is kept).</summary>
    [JsonPropertyName("hideShop")] public bool HideShop { get; set; }

    /// <summary>Stop highlighting Shop songs.</summary>
    [JsonPropertyName("disableShopHighlighting")] public bool DisableShopHighlighting { get; set; }

    /// <summary>Debug-only tap diagnostics.</summary>
    [JsonPropertyName("tapDiagnostics")] public bool TapDiagnostics { get; set; }

    /// <summary>Debug-only tap telemetry (requires diagnostics).</summary>
    [JsonPropertyName("tapTelemetry")] public bool TapTelemetry { get; set; }

    /// <summary>Show the Score metadata field.</summary>
    [JsonPropertyName("metadataScore")] public bool MetadataScore { get; set; } = true;
    /// <summary>Show the Percentage metadata field.</summary>
    [JsonPropertyName("metadataPercentage")] public bool MetadataPercentage { get; set; } = true;
    /// <summary>Show the Percentile metadata field.</summary>
    [JsonPropertyName("metadataPercentile")] public bool MetadataPercentile { get; set; } = true;
    /// <summary>Show the Season Achieved metadata field.</summary>
    [JsonPropertyName("metadataSeason")] public bool MetadataSeason { get; set; } = true;
    /// <summary>Show the Intensity metadata field.</summary>
    [JsonPropertyName("metadataIntensity")] public bool MetadataIntensity { get; set; } = true;
    /// <summary>Show the Difficulty metadata field.</summary>
    [JsonPropertyName("metadataDifficulty")] public bool MetadataDifficulty { get; set; } = true;
    /// <summary>Show the Stars metadata field.</summary>
    [JsonPropertyName("metadataStars")] public bool MetadataStars { get; set; } = true;
    /// <summary>Show the Last Played metadata field.</summary>
    [JsonPropertyName("metadataLastPlayed")] public bool MetadataLastPlayed { get; set; } = true;

    /// <summary>In-app additive override: stronger text and strokes.</summary>
    [JsonPropertyName("moreContrast")] public bool MoreContrast { get; set; }

    /// <summary>In-app additive override: opaque surfaces.</summary>
    [JsonPropertyName("lessTransparency")] public bool LessTransparency { get; set; }

    #region Songs-owned state (kept by Reset)
    /// <summary>Applied Songs General filter (year, duration and Double Bass).</summary>
    [JsonPropertyName("songGeneralFilter")] public SongGeneralFilter GeneralFilter { get; set; } = SongGeneralFilter.None;

    /// <summary>Applied Songs Item Shop filter.</summary>
    [JsonPropertyName("songShopFilter")] public SongShopFilter ShopFilter { get; set; } = SongShopFilter.None;

    /// <summary>Applied selected-player score/FC filter (cleared on confirmed deselection).</summary>
    [JsonPropertyName("songPlayerScoreFilter")] public SongPlayerScoreFilter PlayerScoreFilter { get; set; } = SongPlayerScoreFilter.None;

    /// <summary>Settings v1 single percentile/star choice on one chart (read only for migration; never written).</summary>
    [JsonPropertyName("songScoreBandFilter")] public SongScoreBandFilter? LegacyScoreBandFilter { get; set; }

    /// <summary>Item Shop grid/list preference.</summary>
    [JsonPropertyName("shopViewMode")] public ShopViewMode ShopViewMode { get; set; } = ShopViewMode.Grid;
    #endregion

    /// <summary>Whether Shop songs are highlighted (Shop visible and highlighting on).</summary>
    [JsonIgnore] public bool ShopHighlightEnabled => !HideShop && !DisableShopHighlighting;

    /// <summary>Whether a metadata field is visible.</summary>
    /// <param name="field">Field.</param>
    /// <returns>Visibility.</returns>
    public bool IsMetadataVisible(MetadataField field) => field switch
    {
        MetadataField.Score => MetadataScore,
        MetadataField.Percentage => MetadataPercentage,
        MetadataField.Percentile => MetadataPercentile,
        MetadataField.Season => MetadataSeason,
        MetadataField.Intensity => MetadataIntensity,
        MetadataField.Difficulty => MetadataDifficulty,
        MetadataField.Stars => MetadataStars,
        _ => MetadataLastPlayed,
    };

    /// <summary>Sets one metadata field's visibility (all may be off).</summary>
    /// <param name="field">Field.</param>
    /// <param name="visible">Visibility.</param>
    /// <returns>Updated settings.</returns>
    public AppSettings WithMetadataVisible(MetadataField field, bool visible) => field switch
    {
        MetadataField.Score => this with { MetadataScore = visible },
        MetadataField.Percentage => this with { MetadataPercentage = visible },
        MetadataField.Percentile => this with { MetadataPercentile = visible },
        MetadataField.Season => this with { MetadataSeason = visible },
        MetadataField.Intensity => this with { MetadataIntensity = visible },
        MetadataField.Difficulty => this with { MetadataDifficulty = visible },
        MetadataField.Stars => this with { MetadataStars = visible },
        _ => this with { MetadataLastPlayed = visible },
    };

    /// <summary>
    /// Restores app settings only (web Reset Settings). Starts from <c>this</c>, so the selected player,
    /// Songs sort/filter state and every other Songs-owned field survive.
    /// </summary>
    /// <returns>Settings with every Settings-page preference at its default.</returns>
    public AppSettings ResetAppSettings()
    {
        var defaults = new AppSettings();
        return (this with
        {
            ShowInstrumentIcons = defaults.ShowInstrumentIcons,
            EnableVisualOrder = defaults.EnableVisualOrder,
            SongRowVisualOrder = defaults.SongRowVisualOrder,
            PathColumnOrder = defaults.PathColumnOrder,
            FilterInvalidScores = defaults.FilterInvalidScores,
            Leeway = defaults.Leeway,
            PathDefaultView = defaults.PathDefaultView,
            PathUnavailableWarningDismissed = defaults.PathUnavailableWarningDismissed,
            ExperimentalRanks = defaults.ExperimentalRanks,
            HideShop = defaults.HideShop,
            DisableShopHighlighting = defaults.DisableShopHighlighting,
            TapDiagnostics = defaults.TapDiagnostics,
            TapTelemetry = defaults.TapTelemetry,
            MetadataScore = true,
            MetadataPercentage = true,
            MetadataPercentile = true,
            MetadataSeason = true,
            MetadataIntensity = true,
            MetadataDifficulty = true,
            MetadataStars = true,
            MetadataLastPlayed = true,
            VisibleInstruments = defaults.VisibleInstruments,
            ReduceMotion = defaults.ReduceMotion,
            DisableAnimatedArtwork = defaults.DisableAnimatedArtwork,
            SaveData = defaults.SaveData,
            MoreContrast = defaults.MoreContrast,
            LessTransparency = defaults.LessTransparency,
        }).Sanitized();
    }
    #endregion

    /// <summary>Returns a copy with every field clamped to a valid state.</summary>
    /// <returns>Sanitized settings.</returns>
    public AppSettings Sanitized()
    {
        var visible = (VisibleInstruments ?? []).Where(Enum.IsDefined).Distinct().Order().ToArray();
        if (visible.Length == 0) visible = [.. InstrumentInfo.All];
        // v1 → v2: the difficulty range becomes intensity buckets, the single band/star choice becomes bucket sets.
        // Corrupt bucket data is kept (not silently dropped) so Songs blocks until an explicit Reset.
        var filter = (SongFilter ?? SongFilter.None).Migrated() is var migrated && (migrated.Instrument is null || Enum.IsDefined(migrated.Instrument.Value))
            ? migrated.ScopedTo(visible) : SongFilter.None;
        var general = SongGeneralFilter.Repaired(GeneralFilter);
        var player = SongPlayerScoreFilter.Repaired(PlayerScoreFilter);
        if (LegacyScoreBandFilter is { IsValid: true, IsActive: true } band && band.Instrument == filter.Instrument && player.IsValid)
        {
            if (band.TopPercent is { } top) player = player.Only(SongBucketKind.Percentile, top);
            if (band.Stars is { } stars) player = player.Only(SongBucketKind.Stars, stars);
        }
        return this with
        {
            Version = CurrentVersion,
            SelectedPlayer = SelectedPlayer is { IsValid: true } ? SelectedPlayer : null,
            SongSort = Enum.IsDefined(SongSort) ? SongSort : SongSortMode.Title,
            SongFilter = filter,
            VisibleInstruments = visible,
            SongRowVisualOrder = SettingsOrder.Normalize(SongRowVisualOrder),
            PathColumnOrder = SettingsOrder.Normalize(PathColumnOrder),
            Leeway = ScoreLeeway.Clamp(Leeway),
            PathDefaultView = Enum.IsDefined(PathDefaultView) ? PathDefaultView : PathDisplayMode.Image,
            ExperimentalRanks = false,
            TapTelemetry = TapTelemetry && TapDiagnostics,
            LeaderboardRankBy = RankingMetrics.Contains(LeaderboardRankBy) ? LeaderboardRankBy : "totalscore",
            GeneralFilter = general.IsValid ? general.Normalized() : general,
            ShopFilter = (ShopFilter ?? SongShopFilter.None).Normalized(),
            PlayerScoreFilter = player,
            LegacyScoreBandFilter = null,
            ShopViewMode = Enum.IsDefined(ShopViewMode) ? ShopViewMode : ShopViewMode.Grid,
        };
    }

    /// <summary>Value equality, comparing lists by contents.</summary>
    /// <param name="other">Other settings.</param>
    /// <returns><see langword="true"/> when every field matches.</returns>
    public bool Equals(AppSettings? other) =>
        other is not null && Version == other.Version && SelectedPlayer == other.SelectedPlayer && SongSort == other.SongSort &&
        SongSortAscending == other.SongSortAscending && SongFilter == other.SongFilter &&
        DisableAnimatedArtwork == other.DisableAnimatedArtwork && ReduceMotion == other.ReduceMotion && SaveData == other.SaveData &&
        (VisibleInstruments ?? []).SequenceEqual(other.VisibleInstruments ?? []) &&
        ShowInstrumentIcons == other.ShowInstrumentIcons && EnableVisualOrder == other.EnableVisualOrder &&
        (SongRowVisualOrder ?? []).SequenceEqual(other.SongRowVisualOrder ?? []) &&
        (PathColumnOrder ?? []).SequenceEqual(other.PathColumnOrder ?? []) &&
        FilterInvalidScores == other.FilterInvalidScores && Leeway.Equals(other.Leeway) && PathDefaultView == other.PathDefaultView &&
        PathUnavailableWarningDismissed == other.PathUnavailableWarningDismissed && ExperimentalRanks == other.ExperimentalRanks &&
        HideShop == other.HideShop && DisableShopHighlighting == other.DisableShopHighlighting &&
        TapDiagnostics == other.TapDiagnostics && TapTelemetry == other.TapTelemetry &&
        MetadataScore == other.MetadataScore && MetadataPercentage == other.MetadataPercentage &&
        MetadataPercentile == other.MetadataPercentile && MetadataSeason == other.MetadataSeason &&
        MetadataIntensity == other.MetadataIntensity && MetadataDifficulty == other.MetadataDifficulty &&
        MetadataStars == other.MetadataStars && MetadataLastPlayed == other.MetadataLastPlayed &&
        MoreContrast == other.MoreContrast && LessTransparency == other.LessTransparency &&
        LeaderboardRankBy == other.LeaderboardRankBy &&
        GeneralFilter == other.GeneralFilter && ShopFilter == other.ShopFilter &&
        Equals(PlayerScoreFilter, other.PlayerScoreFilter) && ShopViewMode == other.ShopViewMode &&
        LegacyScoreBandFilter == other.LegacyScoreBandFilter;

    /// <summary>Hash consistent with <see cref="Equals(AppSettings?)"/>.</summary>
    /// <returns>Hash code.</returns>
    public override int GetHashCode() =>
        HashCode.Combine(SelectedPlayer, SongSort, SongSortAscending, SongFilter, VisibleInstruments?.Count, Leeway, HideShop);

    /// <summary>Toggles a chart's visibility; the last visible chart cannot be hidden.</summary>
    /// <param name="instrument">Chart.</param>
    /// <param name="visible">Desired visibility.</param>
    /// <returns>Updated settings (filter scoped to the new set).</returns>
    public AppSettings WithInstrumentVisible(Instrument instrument, bool visible)
    {
        var set = VisibleInstruments.ToHashSet();
        if (visible) set.Add(instrument);
        else if (set.Count > 1) set.Remove(instrument);
        var ordered = set.Order().ToArray();
        return this with { VisibleInstruments = ordered, SongFilter = SongFilter.ScopedTo(ordered) };
    }
}
#endregion
