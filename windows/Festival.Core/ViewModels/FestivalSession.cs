using CommunityToolkit.Mvvm.ComponentModel;

namespace Festival.Core.ViewModels;

#region Session
/// <summary>
/// Process-lifetime app state shared by every page: the service client, persisted settings,
/// the current catalogue and the artwork byte cache. Create and use on the UI thread.
/// </summary>
public sealed partial class FestivalSession : ObservableObject
{
    private readonly ISettingsStore store;
    private Task<SongsResponse>? catalogLoad;

    /// <summary>Creates the session and restores settings (including the selected player).</summary>
    /// <param name="api">Service client.</param>
    /// <param name="store">Settings persistence.</param>
    /// <param name="time">Clock for debounces and countdowns.</param>
    public FestivalSession(FestivalApiClient api, ISettingsStore store, TimeProvider? time = null)
    {
        Api = api;
        this.store = store;
        Time = time ?? TimeProvider.System;
        settings = store.Load();
        Artwork = new ArtworkByteCache(api.GetArtworkBytesAsync);
        api.PublicationChanged += (_, _) => Artwork.Clear();
    }

    /// <summary>Service client.</summary>
    public FestivalApiClient Api { get; }

    /// <summary>Clock used by view models.</summary>
    public TimeProvider Time { get; }

    /// <summary>Bounded process-only art cache.</summary>
    public ArtworkByteCache Artwork { get; }

    /// <summary>Whether the persisted settings were corrupt and replaced by defaults this launch.</summary>
    public bool SettingsRecovered => store.RecoveredFromCorruption;

    /// <summary>Current persisted settings.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasPlayer), nameof(SelectedPlayer))]
    private AppSettings settings;

    /// <summary>Latest validated catalogue, if loaded.</summary>
    [ObservableProperty]
    private SongsResponse? catalog;

    /// <summary>Selected player, if any.</summary>
    public SelectedPlayer? SelectedPlayer => Settings.SelectedPlayer;

    /// <summary>Whether a player is selected (adds Suggestions, Rivals and Statistics).</summary>
    public bool HasPlayer => Settings.SelectedPlayer is not null;

    /// <summary>Applies and persists a settings change.</summary>
    /// <param name="change">Pure transformation of the current settings.</param>
    public void UpdateSettings(Func<AppSettings, AppSettings> change)
    {
        var next = change(Settings).Sanitized();
        if (next == Settings) return;
        Settings = next;
        store.Save(next);
    }

    /// <summary>Selects a validated search result and persists it.</summary>
    /// <param name="result">Account search result.</param>
    /// <returns><see langword="true"/> when the identity was valid and selected.</returns>
    public bool SelectPlayer(PlayerSearchResult result)
    {
        var player = new SelectedPlayer(result.AccountId, result.DisplayName.Trim());
        if (!player.IsValid) return false;
        UpdateSettings(s => s with { SelectedPlayer = player });
        return true;
    }

    /// <summary>Deselects the player (score predicates are cleared; public preferences stay).</summary>
    public void DeselectPlayer() => UpdateSettings(s => s with { SelectedPlayer = null });

    /// <summary>Loads the catalogue once per publication; concurrent callers share the request.</summary>
    /// <param name="force">Re-read even when a catalogue is loaded (Retry, refresh); joins an in-flight read.</param>
    /// <param name="cancellationToken">Cancels only this caller's wait.</param>
    /// <returns>Validated catalogue.</returns>
    public async Task<SongsResponse> LoadCatalogAsync(bool force = false, CancellationToken cancellationToken = default)
    {
        if (!force && Catalog is { } loaded) return loaded;
        catalogLoad ??= Api.GetSongsAsync(CancellationToken.None);
        var task = catalogLoad;
        try
        {
            var songs = await task.WaitAsync(cancellationToken);
            Catalog = songs;
            return songs;
        }
        finally
        {
            if (task.IsCompleted && ReferenceEquals(task, catalogLoad)) catalogLoad = null;
        }
    }

    /// <summary>Finds a song in the loaded catalogue.</summary>
    /// <param name="songId">Song ID.</param>
    /// <returns>The song, or <see langword="null"/>.</returns>
    public Song? FindSong(string songId) => Catalog?.Songs.FirstOrDefault(s => s.SongId == songId);
}
#endregion
