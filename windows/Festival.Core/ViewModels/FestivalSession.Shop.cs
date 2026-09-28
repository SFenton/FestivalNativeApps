using CommunityToolkit.Mvvm.ComponentModel;

namespace Festival.Core.ViewModels;

#region Session: Item Shop and publication observations
/// <summary>
/// Process-only Item Shop feed and the publication each Songs input was observed under, so Shop badges,
/// filters and sorts never cross publications (<c>AGENTS.md</c> invariants).
/// </summary>
public sealed partial class FestivalSession
{
    private Task<ShopResponse>? shopLoad;
    private SynchronizationContext? publicationContext;
    private bool publicationHooked;

    /// <summary>Latest validated Item Shop feed, if loaded.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShopOffers))]
    private ShopResponse? shop;

    /// <summary>Why the last Shop read failed, or <see langword="null"/>.</summary>
    [ObservableProperty]
    private ServiceIssue? shopIssue;

    /// <summary>Publication observed when the catalogue was validated.</summary>
    public long? CatalogPublicationId { get; private set; }

    /// <summary>Publication observed when the Shop feed was validated.</summary>
    public long? ShopPublicationId { get; private set; }

    /// <summary>Latest publication the client has observed.</summary>
    public long? ObservedPublicationId => Api.CurrentPublication?.PublicationId;

    /// <summary>Offers by song ID for the loaded feed (any publication).</summary>
    public IReadOnlyDictionary<string, ShopSong>? ShopOffers { get; private set; }

    /// <summary>Offers only when catalogue, Shop and session share one observed publication.</summary>
    public IReadOnlyDictionary<string, ShopSong>? ShopOffersForCatalog =>
        SongRelatedPublicationPolicy.Matches(CatalogPublicationId, ShopPublicationId, ObservedPublicationId) ? ShopOffers : null;

    /// <summary>A feed exists but from a different publication than the catalogue.</summary>
    public bool ShopPublicationMismatch => Shop is not null && ShopOffersForCatalog is null;

    /// <summary>Raised on the UI context after the client observes a newer publication.</summary>
    public event EventHandler? PublicationAdvanced;

    /// <summary>Loads the Shop feed once per publication; concurrent callers share the request.</summary>
    /// <param name="force">Re-read (Retry, publication change).</param>
    /// <param name="cancellationToken">Cancels only this caller's wait.</param>
    /// <returns>Validated feed.</returns>
    public async Task<ShopResponse> LoadShopAsync(bool force = false, CancellationToken cancellationToken = default)
    {
        HookPublication();
        if (!force && Shop is { } loaded && ShopPublicationId == ObservedPublicationId) return loaded;
        shopLoad ??= Api.GetShopAsync(CancellationToken.None);
        var task = shopLoad;
        try
        {
            var feed = await task.WaitAsync(cancellationToken);
            ShopPublicationId = ObservedPublicationId;
            ShopOffers = feed.Songs.ToDictionary(s => s.SongId, StringComparer.Ordinal);
            ShopIssue = null;
            Shop = feed;
            OnPropertyChanged(nameof(ShopOffersForCatalog));
            return feed;
        }
        catch (FestivalApiException error) when (ReferenceEquals(task, shopLoad))
        {
            ShopIssue = ServiceIssue.From(error);
            throw;
        }
        finally
        {
            if (task.IsCompleted && ReferenceEquals(task, shopLoad)) shopLoad = null;
        }
    }

    /// <summary>Loads the Shop feed, recording (not throwing) a failure; hidden Shop reads nothing.</summary>
    /// <param name="force">Re-read.</param>
    /// <returns>Load task.</returns>
    public async Task TryLoadShopAsync(bool force = false)
    {
        if (Settings.HideShop) return;
        try
        {
            await LoadShopAsync(force);
        }
        catch (FestivalApiException)
        {
            // Recorded in ShopIssue; Songs shows a paused notice and Shop its status view.
        }
    }

    /// <summary>Finds a validated offer for a song (any publication; callers apply the publication policy).</summary>
    /// <param name="songId">Song ID.</param>
    /// <returns>Offer or <see langword="null"/>.</returns>
    public ShopSong? FindOffer(string songId) => ShopOffers?.GetValueOrDefault(songId);

    /// <summary>Records the catalogue's observed publication whenever a catalogue is stored.</summary>
    /// <param name="value">New catalogue.</param>
    partial void OnCatalogChanged(SongsResponse? value)
    {
        HookPublication();
        CatalogPublicationId = value is null ? null : ObservedPublicationId;
        OnPropertyChanged(nameof(ShopOffersForCatalog));
    }

    /// <summary>Subscribes once to publication changes, marshalling them to the creating context.</summary>
    private void HookPublication()
    {
        if (publicationHooked) return;
        publicationHooked = true;
        publicationContext = SynchronizationContext.Current;
        Api.PublicationChanged += (_, _) =>
        {
            if (publicationContext is { } context) context.Post(_ => RaisePublicationAdvanced(), null);
            else RaisePublicationAdvanced();
        };
    }

    /// <summary>Announces a newer publication so pages re-read their inputs.</summary>
    private void RaisePublicationAdvanced()
    {
        OnPropertyChanged(nameof(ObservedPublicationId));
        OnPropertyChanged(nameof(ShopOffersForCatalog));
        PublicationAdvanced?.Invoke(this, EventArgs.Empty);
    }
}
#endregion
