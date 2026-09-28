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
    /// <summary>Current schema version.</summary>
    public const int CurrentVersion = 1;

    /// <summary>Schema version.</summary>
    [JsonPropertyName("version")] public int Version { get; init; } = CurrentVersion;

    /// <summary>Explicitly selected player, restored across restarts.</summary>
    [JsonPropertyName("selectedPlayer")] public SelectedPlayer? SelectedPlayer { get; init; }

    /// <summary>Applied Songs sort mode.</summary>
    [JsonPropertyName("songSort")] public SongSortMode SongSort { get; init; } = SongSortMode.Title;

    /// <summary>Applied Songs sort direction.</summary>
    [JsonPropertyName("songSortAscending")] public bool SongSortAscending { get; init; } = true;

    /// <summary>Applied Songs filter.</summary>
    [JsonPropertyName("songFilter")] public SongFilter SongFilter { get; init; } = SongFilter.None;

    /// <summary>Settings-visible charts (never empty).</summary>
    [JsonPropertyName("visibleInstruments")] public IReadOnlyList<Instrument> VisibleInstruments { get; init; } = InstrumentInfo.All;

    /// <summary>In-app additive override: stop artwork animation even when the system allows it.</summary>
    [JsonPropertyName("disableAnimatedArtwork")] public bool DisableAnimatedArtwork { get; init; }

    /// <summary>In-app additive override: reduce motion.</summary>
    [JsonPropertyName("reduceMotion")] public bool ReduceMotion { get; init; }

    /// <summary>In-app additive override: no artwork at all (data saving).</summary>
    [JsonPropertyName("saveData")] public bool SaveData { get; init; }

    /// <summary>Known Leaderboards Rank By metrics (web <c>RANKING_METRICS</c>).</summary>
    public static readonly IReadOnlyList<string> RankingMetrics = ["totalscore", "adjusted", "weighted", "fcrate", "maxscore"];

    /// <summary>Last Leaderboards Rank By metric (web <c>fst:leaderboardSettings</c>; navigation state, kept by Reset).</summary>
    [JsonPropertyName("leaderboardRankBy")] public string LeaderboardRankBy { get; init; } = "totalscore";

    #region App settings (Settings page; restored by Reset)
    /// <summary>Show per-chart status icons on unfiltered Songs rows.</summary>
    [JsonPropertyName("showInstrumentIcons")] public bool ShowInstrumentIcons { get; init; } = true;

    /// <summary>Song-row metadata order is independent of sort priority.</summary>
    [JsonPropertyName("enableVisualOrder")] public bool EnableVisualOrder { get; init; }

    /// <summary>Song-row metadata display order (every field exactly once).</summary>
    [JsonPropertyName("songRowVisualOrder")] public IReadOnlyList<MetadataField> SongRowVisualOrder { get; init; } = SettingsOrder.Normalize<MetadataField>(null);

    /// <summary>CHOpt text-path column order (every column exactly once).</summary>
    [JsonPropertyName("pathColumnOrder")] public IReadOnlyList<PathColumnKey> PathColumnOrder { get; init; } = SettingsOrder.Normalize<PathColumnKey>(null);

    /// <summary>Hide scores above the CHOpt maximum plus leeway.</summary>
    [JsonPropertyName("filterInvalidScores")] public bool FilterInvalidScores { get; init; }

    /// <summary>Invalid-score leeway percent, −5…+5 in 0.1 steps.</summary>
    [JsonPropertyName("leeway")] public double Leeway { get; init; } = ScoreLeeway.Default;

    /// <summary>How CHOpt paths open by default.</summary>
    [JsonPropertyName("pathDefaultView")] public PathDisplayMode PathDefaultView { get; init; } = PathDisplayMode.Image;

    /// <summary>The Paths unavailable-chart warning was dismissed.</summary>
    [JsonPropertyName("pathUnavailableWarningDismissed")] public bool PathUnavailableWarningDismissed { get; init; }

    /// <summary>Experimental leaderboard ranks (not yet available: always sanitized to off).</summary>
    [JsonPropertyName("experimentalRanks")] public bool ExperimentalRanks { get; init; }

    /// <summary>Hide the Item Shop (navigation and highlights; the highlight preference is kept).</summary>
    [JsonPropertyName("hideShop")] public bool HideShop { get; init; }

    /// <summary>Stop highlighting Shop songs.</summary>
    [JsonPropertyName("disableShopHighlighting")] public bool DisableShopHighlighting { get; init; }

    /// <summary>Debug-only tap diagnostics.</summary>
    [JsonPropertyName("tapDiagnostics")] public bool TapDiagnostics { get; init; }

    /// <summary>Debug-only tap telemetry (requires diagnostics).</summary>
    [JsonPropertyName("tapTelemetry")] public bool TapTelemetry { get; init; }

    /// <summary>Show the Score metadata field.</summary>
    [JsonPropertyName("metadataScore")] public bool MetadataScore { get; init; } = true;
    /// <summary>Show the Percentage metadata field.</summary>
    [JsonPropertyName("metadataPercentage")] public bool MetadataPercentage { get; init; } = true;
    /// <summary>Show the Percentile metadata field.</summary>
    [JsonPropertyName("metadataPercentile")] public bool MetadataPercentile { get; init; } = true;
    /// <summary>Show the Season Achieved metadata field.</summary>
    [JsonPropertyName("metadataSeason")] public bool MetadataSeason { get; init; } = true;
    /// <summary>Show the Intensity metadata field.</summary>
    [JsonPropertyName("metadataIntensity")] public bool MetadataIntensity { get; init; } = true;
    /// <summary>Show the Game Difficulty metadata field.</summary>
    [JsonPropertyName("metadataDifficulty")] public bool MetadataDifficulty { get; init; } = true;
    /// <summary>Show the Stars metadata field.</summary>
    [JsonPropertyName("metadataStars")] public bool MetadataStars { get; init; } = true;
    /// <summary>Show the Last Played metadata field.</summary>
    [JsonPropertyName("metadataLastPlayed")] public bool MetadataLastPlayed { get; init; } = true;

    /// <summary>In-app additive override: stronger text and strokes.</summary>
    [JsonPropertyName("moreContrast")] public bool MoreContrast { get; init; }

    /// <summary>In-app additive override: opaque surfaces.</summary>
    [JsonPropertyName("lessTransparency")] public bool LessTransparency { get; init; }

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
        var filter = SongFilter is { IsValid: true } f && (f.Instrument is null || Enum.IsDefined(f.Instrument.Value))
            ? f.ScopedTo(visible) : SongFilter.None;
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
        LeaderboardRankBy == other.LeaderboardRankBy;

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
