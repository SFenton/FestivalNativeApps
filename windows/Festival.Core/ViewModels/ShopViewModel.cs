using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Shop page
/// <summary>
/// Item Shop page: offers in the saved Title / Artist / Year / Duration order (<see cref="ShopOfferSort"/>) with New /
/// Leaving Tomorrow badges, official links and in-app Song Detail links for validated catalogue songs. A genuine empty
/// feed and a failed read are never interchangeable.
/// </summary>
public sealed partial class ShopViewModel : ObservableObject
{
    private readonly FestivalSession session;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    public ShopViewModel(FestivalSession session)
    {
        this.session = session;
        Status = new ServiceStatusViewModel("shop", "Item Shop unavailable", () => LoadAsync(force: true), session.Time);
        session.PropertyChanged += OnSessionChanged;
        session.PublicationAdvanced += (_, _) => _ = LoadAsync(force: true);
        SortDraft = SongSortDraft.ForShop(session);
        // Like Songs, the Sort flyout applies live: every change (and Reset) commits at once; no Cancel/Apply.
        SortDraft.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(SongSortDraft.CanApply) && SortDraft.IsLive && SortDraft.CanApply) ApplySort();
        };
        FilterRows =
        [
            new("New", "Songs that are new in the Item Shop today.", "fst.shop.filter.new", () => Filter.New, v => SetFilter(Filter with { New = v })),
            new("Available", "Songs in the Item Shop today that aren't new or leaving tomorrow.", "fst.shop.filter.available",
                () => Filter.Available, v => SetFilter(Filter with { Available = v })),
            new("Leaving Tomorrow", "Songs that are leaving the Item Shop tomorrow.", "fst.shop.filter.leaving",
                () => Filter.LeavingTomorrow, v => SetFilter(Filter with { LeavingTomorrow = v })),
        ];
    }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Sort flyout draft (the Songs Sort form with <see cref="ShopOfferSort.Modes"/>).</summary>
    public SongSortDraft SortDraft { get; }

    /// <summary>Load lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowOffers), nameof(ShowEmpty), nameof(ShowError), nameof(ShowGrid), nameof(ShowList), nameof(ShowNoMatches), nameof(CanToggleView), nameof(HasSortPause))]
    private LoadState state = LoadState.Idle;

    /// <summary>Offers in the saved sort order that pass <see cref="Filter"/>.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowNoMatches))]
    private List<ShopOfferItem> offers = [];

    /// <summary>
    /// Page filter (New / Available / Leaving Tomorrow include switches, all on by default). Kept with the cached page
    /// for the session, so the reopened flyout shows it; not persisted, so every launch shows every offer.
    /// </summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsFilterActive), nameof(FilterStatus))]
    private ShopOfferFilter filter = new();

    /// <summary>Offers in the feed before filtering.</summary>
    private int totalOffers;

    /// <summary>Why catalogue-backed Song Detail links are unavailable, or <see langword="null"/>.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasSongDetailsIssue))]
    private string? songDetailsIssue;

    /// <summary>Why the saved Duration sort shows title order instead (<c>fst.shop.sort-paused</c>), or <see langword="null"/>.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasSortPause))]
    private string? sortPaused;

    /// <summary>Whether the window is compact (forces the album-art grid, as in the installed PWA; no toggle).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowGrid), nameof(ShowList), nameof(CanToggleView))]
    private bool isCompact;

    /// <summary>Whether a read is in flight with nothing shown.</summary>
    public bool IsLoading => State == LoadState.Loading;

    /// <summary>Whether offers are shown.</summary>
    public bool ShowOffers => State == LoadState.Loaded;

    /// <summary>Whether the genuine empty-Shop card is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty;

    /// <summary>Whether the status view is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Whether the Shop is hidden in Settings (the page explains and offers a way back).</summary>
    public bool IsHidden => session.Settings.HideShop;

    /// <summary>Effective layout is the grid.</summary>
    public bool ShowGrid => ShowOffers && (IsCompact || session.Settings.ShopViewMode == ShopViewMode.Grid);

    /// <summary>Effective layout is the list.</summary>
    public bool ShowList => ShowOffers && !ShowGrid;

    /// <summary>
    /// Whether the grid/list toggle is offered: only with offers on screen (like Filter; loading, empty, failed and
    /// hidden have no layout to switch) and not in compact windows.
    /// </summary>
    public bool CanToggleView => ShowOffers && !IsCompact;

    /// <summary>Toggle label naming the other layout.</summary>
    public string ToggleLabel => session.Settings.ShopViewMode == ShopViewMode.Grid ? "List View" : "Grid View";

    /// <summary>Whether the catalogue-link notice shows.</summary>
    public bool HasSongDetailsIssue => SongDetailsIssue is not null;

    /// <summary>Whether the sort-pause notice shows (only with offers on screen).</summary>
    public bool HasSortPause => ShowOffers && SortPaused is not null;

    /// <summary>Filter switches (the Songs filter flyout's toggle rows); every change applies at once.</summary>
    public List<FilterToggleRow> FilterRows { get; }

    /// <summary>Whether a filter switch is off (gold Filter button).</summary>
    public bool IsFilterActive => Filter.IsActive;

    /// <summary>
    /// UI Automation item status of the Filter button ("Filters applied" while a switch is off, like Songs), so Narrator
    /// hears what the gold tint shows.
    /// </summary>
    public string FilterStatus => IsFilterActive ? "Filters applied" : "";

    /// <summary>Whether a non-default sort is applied (gold Sort button, like Songs).</summary>
    public bool IsSortChanged => session.Settings.ShopSort != SongSortMode.Title || !session.Settings.ShopSortAscending;

    /// <summary>Applied sort label, e.g. "Title ↑".</summary>
    public string SortSummary => session.Settings.ShopSort.Label() + (session.Settings.ShopSortAscending ? " ↑" : " ↓");

    /// <summary>
    /// Applied sort in words for UI Automation help text, e.g. "Title, ascending" (the button's name stays "Sort Item
    /// Shop", so screen readers would otherwise not hear <see cref="SortSummary"/>'s arrow label).
    /// </summary>
    public string SortDescription => session.Settings.ShopSort.Label() + (session.Settings.ShopSortAscending ? ", ascending" : ", descending");

    /// <summary>The feed has offers but the filter hides them all ("No Matching Songs", never the empty-Shop card).</summary>
    public bool ShowNoMatches => ShowOffers && Offers.Count == 0;

    /// <summary>"133 songs", or "1 of 133 songs" while filtered.</summary>
    public string CountText => IsFilterActive
        ? $"{Offers.Count:N0} of {totalOffers:N0} {(totalOffers == 1 ? "song" : "songs")}"
        : Offers.Count == 1 ? "1 song" : $"{Offers.Count:N0} songs";

    /// <summary>Loads the feed, then (best-effort) the catalogue for in-app links.</summary>
    /// <param name="force">Re-read.</param>
    /// <returns>Load task.</returns>
    public async Task LoadAsync(bool force = false)
    {
        if (IsHidden)
        {
            State = LoadState.Idle;
            return;
        }
        if (session.Shop is null || force) State = LoadState.Loading;
        ShopResponse feed;
        try
        {
            feed = await session.LoadShopAsync(force);
            Status.Clear();
        }
        catch (FestivalApiException error)
        {
            Status.Report(error);
            State = LoadState.Failed;
            return;
        }
        string? detailsIssue = null;
        if (feed.Songs.Count > 0)
        {
            try
            {
                await session.LoadCatalogAsync();
            }
            catch (FestivalApiException error)
            {
                detailsIssue = "Song details unavailable: " + ServiceIssue.From(error).Message;
            }
        }
        SongDetailsIssue = detailsIssue;
        Project(feed);
    }

    /// <summary>Loads on appearance.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    private Task AppearAsync() => State is LoadState.Idle or LoadState.Failed || session.Shop is null ? LoadAsync() : Task.CompletedTask;

    /// <summary>Switches grid/list and persists it.</summary>
    [RelayCommand]
    private void ToggleView()
    {
        session.UpdateSettings(s => s with { ShopViewMode = s.ShopViewMode == ShopViewMode.Grid ? ShopViewMode.List : ShopViewMode.Grid });
        OnPropertyChanged(nameof(ShowGrid));
        OnPropertyChanged(nameof(ShowList));
        OnPropertyChanged(nameof(ToggleLabel));
    }

    /// <summary>Saves the sort draft (the settings change re-projects both layouts).</summary>
    [RelayCommand]
    private void ApplySort() =>
        session.UpdateSettings(s => s with { ShopSort = SortDraft.Mode, ShopSortAscending = SortDraft.Ascending });

    /// <summary>Shows every offer again (Reset in the flyout, Reset Filters on the no-match notice).</summary>
    [RelayCommand]
    private void ResetFilter() => SetFilter(new());

    /// <summary>Applies a filter at once and re-reads the switches.</summary>
    /// <param name="next">New filter.</param>
    private void SetFilter(ShopOfferFilter next)
    {
        if (next == Filter) return;
        Filter = next;
        foreach (var row in FilterRows) row.Refresh();
        if (session.Shop is { } feed && State is LoadState.Loaded) Project(feed);
        else OnPropertyChanged(nameof(CountText));
    }

    /// <summary>Builds row items from a feed.</summary>
    /// <param name="feed">Validated feed.</param>
    private void Project(ShopResponse feed)
    {
        var settings = session.Settings;
        // Duration lengths come only from a catalogue of the feed's publication; otherwise title order with a notice.
        var pause = ShopOfferSort.DurationPause(settings.ShopSort, session.Catalog is not null,
            SongRelatedPublicationPolicy.Matches(session.CatalogPublicationId, session.ShopPublicationId, session.ObservedPublicationId));
        var sorted = ShopOfferSort.Sort(feed.Songs, pause is null ? settings.ShopSort : SongSortMode.Title, settings.ShopSortAscending,
            id => session.FindSong(id)?.DurationSeconds);
        SortPaused = pause;
        totalOffers = sorted.Count;
        Offers = [.. sorted.Where(Filter.Matches).Select(offer => new ShopOfferItem(
            offer,
            ShopPresentationPolicy.Highlight(offer, settings.HideShop, settings.DisableShopHighlighting),
            session.FindSong(offer.SongId) is not null))];
        OnPropertyChanged(nameof(CountText));
        // Only a genuinely empty feed is the empty Shop; a filter that hides every offer stays Loaded (ShowNoMatches).
        State = totalOffers == 0 ? LoadState.Empty : LoadState.Loaded;
    }

    /// <summary>Re-projects on highlight, visibility and sort changes.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(FestivalSession.Settings)) return;
        OnPropertyChanged(nameof(IsHidden));
        OnPropertyChanged(nameof(ShowGrid));
        OnPropertyChanged(nameof(ShowList));
        OnPropertyChanged(nameof(ToggleLabel));
        OnPropertyChanged(nameof(IsSortChanged));
        OnPropertyChanged(nameof(SortSummary));
        OnPropertyChanged(nameof(SortDescription));
        if (IsHidden) State = LoadState.Idle;
        else if (session.Shop is { } feed) Project(feed);
        else _ = LoadAsync();
    }
}

/// <summary>One offer card/row.</summary>
/// <param name="Offer">Validated offer.</param>
/// <param name="Highlight">Effective accent.</param>
/// <param name="HasSongDetail">Whether a validated catalogue song exists for an in-app link.</param>
public sealed record ShopOfferItem(ShopSong Offer, ShopHighlight? Highlight, bool HasSongDetail)
{
    /// <summary>Grid tile pulse: gold New, red Leaving Tomorrow (web <c>ShopCard</c>; plain offers don't pulse).</summary>
    public SongRowShopPulse? Pulse => SongRowShopPulse.For(false, Highlight);

    /// <summary>Accessible name of the tile's primary action (Song Detail when matched, else the official Item Shop).</summary>
    public string TileName => HasSongDetail ? Announcement : ExternalName;

    /// <summary>Title.</summary>
    public string Title => Offer.Title;

    /// <summary>Artist · year.</summary>
    public string Subtitle => Offer.Subtitle;

    /// <summary>Badge text, or empty.</summary>
    public string BadgeText => Highlight?.Label() ?? "";

    /// <summary>Whether a badge shows.</summary>
    public bool HasBadge => Highlight is not null;

    /// <summary>Whether the badge is Leaving Tomorrow (red) rather than New (gold).</summary>
    public bool IsLeaving => Highlight == ShopHighlight.LeavingTomorrow;

    /// <summary>Song Detail route (only when <see cref="HasSongDetail"/>).</summary>
    public AppRoute DetailRoute => new AppRoute.SongDetail(Offer.SongId);

    /// <summary>Accessible name for the official-link action.</summary>
    public string ExternalName => $"{Offer.Title}, {Offer.Artist}, Open Official Item Shop";

    /// <summary>UIA ID of the official Item Shop action (the tile's context menu, the list row's cart button).</summary>
    public string ExternalAutomationId => $"fst.shop.external.{Offer.SongId}";

    /// <summary>UIA ID of the tile/row that opens Song Detail.</summary>
    public string TileAutomationId => $"fst.shop.song.{Offer.SongId}";

    /// <summary>Full announcement for the in-app action.</summary>
    public string Announcement => Highlight is { } h ? $"{Title}, {Subtitle}, {h.Label()}" : $"{Title}, {Subtitle}";
}
#endregion
