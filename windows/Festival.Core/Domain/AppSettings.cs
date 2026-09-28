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
        };
    }

    /// <summary>Value equality, comparing the instrument list by contents.</summary>
    /// <param name="other">Other settings.</param>
    /// <returns><see langword="true"/> when every field matches.</returns>
    public bool Equals(AppSettings? other) =>
        other is not null && Version == other.Version && SelectedPlayer == other.SelectedPlayer && SongSort == other.SongSort &&
        SongSortAscending == other.SongSortAscending && SongFilter == other.SongFilter &&
        DisableAnimatedArtwork == other.DisableAnimatedArtwork && ReduceMotion == other.ReduceMotion && SaveData == other.SaveData &&
        (VisibleInstruments ?? []).SequenceEqual(other.VisibleInstruments ?? []);

    /// <summary>Hash consistent with <see cref="Equals(AppSettings?)"/>.</summary>
    /// <returns>Hash code.</returns>
    public override int GetHashCode() => HashCode.Combine(SelectedPlayer, SongSort, SongSortAscending, SongFilter, VisibleInstruments?.Count);

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
