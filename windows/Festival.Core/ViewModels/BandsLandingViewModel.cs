using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Bands landing
/// <summary>
/// <c>/bands</c>: the web page is a band search, but band search can write server state on a GET, so this landing
/// shows what stays safely reachable — the selected player's bands (first page preview) and the public Band Rankings.
/// </summary>
public sealed partial class BandsLandingViewModel : ObservableObject, IDisposable
{
    /// <summary>Bands previewed for the selected player.</summary>
    public const int PreviewSize = 6;

    private readonly FestivalSession session;
    private int version;

    /// <summary>Creates the landing model and follows player selection.</summary>
    /// <param name="session">Shared session.</param>
    public BandsLandingViewModel(FestivalSession session)
    {
        this.session = session;
        Status = new ServiceStatusViewModel("bands-landing", "Failed to load bands", LoadAsync, session.Time);
        session.PropertyChanged += OnSessionChanged;
    }

    /// <summary>Preview read failure.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Links into Band Rankings, one per size.</summary>
    public List<BandRankingLink> RankingLinks { get; } = [.. BandTypeInfo.All.Select(t => new BandRankingLink(t))];

    /// <summary>Why lookup by name is not offered.</summary>
    public string Footnote =>
        "Band lookup by name isn't available: the service's band search can register band data as a side effect " +
        "of a search, so this app doesn't call it. Browse Band Rankings or a selected player's bands instead.";

    /// <summary>Preview lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowEmpty), nameof(ShowError))]
    private LoadState state = LoadState.Idle;

    /// <summary>Preview cards.</summary>
    [ObservableProperty]
    private List<PlayerBandCardViewModel> yourBands = [];

    /// <summary>Selected player's band count, once known.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ViewAllText), nameof(HasMore))]
    private int totalCount;

    /// <summary>Whether a player is selected (shows Your Bands).</summary>
    public bool HasPlayer => session.HasPlayer;

    /// <summary><c>Name's Bands</c>.</summary>
    public string YourBandsTitle => session.SelectedPlayer is { } p ? $"{p.DisplayName}'s Bands" : "Your Bands";

    /// <summary>Route to the selected player's full band list.</summary>
    public AppRoute? ViewAllRoute => session.SelectedPlayer is { } p ? new AppRoute.PlayerBands(p.AccountId) : null;

    /// <summary><c>View All 12 Bands</c>.</summary>
    public string ViewAllText => TotalCount > 0 ? $"View All {BandFormatting.Count(TotalCount)} Bands" : "View All Bands";

    /// <summary>Whether more bands exist than the preview shows.</summary>
    public bool HasMore => TotalCount > YourBands.Count;

    /// <summary>Whether the preview is loading.</summary>
    public bool IsLoading => HasPlayer && State is LoadState.Loading or LoadState.Idle;

    /// <summary>Whether preview cards are shown.</summary>
    public bool ShowRows => HasPlayer && State == LoadState.Loaded;

    /// <summary>Whether the "No bands found" note is shown.</summary>
    public bool ShowEmpty => HasPlayer && State == LoadState.Empty;

    /// <summary>Whether the preview failure is shown.</summary>
    public bool ShowError => HasPlayer && State == LoadState.Failed;

    /// <summary>Loads the selected player's first bands (no-op without a player).</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        var requested = ++version;
        if (session.SelectedPlayer is not { } player)
        {
            YourBands = [];
            TotalCount = 0;
            State = LoadState.Idle;
            return;
        }
        State = LoadState.Loading;
        try
        {
            var list = await session.Api.GetPlayerBandsAsync(player.AccountId, PlayerBandGroup.All, 1, PreviewSize);
            if (requested != version) return;
            Status.Clear();
            YourBands = [.. list.Entries.Select(e => new PlayerBandCardViewModel(e))];
            TotalCount = list.TotalCount;
            OnPropertyChanged(nameof(HasMore));
            State = YourBands.Count == 0 ? LoadState.Empty : LoadState.Loaded;
        }
        catch (FestivalApiException error)
        {
            if (requested != version) return;
            Status.Report(error);
            State = LoadState.Failed;
        }
    }

    /// <summary>Stops following the session.</summary>
    public void Dispose() => session.PropertyChanged -= OnSessionChanged;

    /// <summary>Reloads when the selected player changes.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(FestivalSession.Settings)) return;
        OnPropertyChanged(nameof(HasPlayer));
        OnPropertyChanged(nameof(YourBandsTitle));
        OnPropertyChanged(nameof(ViewAllRoute));
        OnPropertyChanged(nameof(IsLoading));
        OnPropertyChanged(nameof(ShowRows));
        OnPropertyChanged(nameof(ShowEmpty));
        OnPropertyChanged(nameof(ShowError));
        _ = LoadAsync();
    }
}

/// <summary>A Band Rankings link for one size.</summary>
/// <param name="BandType">Band size.</param>
public sealed record BandRankingLink(BandType BandType)
{
    /// <summary><c>Duos</c>.</summary>
    public string Label => BandType.Label();

    /// <summary><c>Two-player band lineups.</c></summary>
    public string Description => BandType switch
    {
        BandType.Duets => "Two-player band lineups.",
        BandType.Trios => "Three-player band lineups.",
        _ => "Four-player band lineups.",
    };

    /// <summary>Band Rankings route.</summary>
    public AppRoute Route => new AppRoute.BandRankings(BandType.ServiceId());

    /// <summary>Automation ID (<c>fst.bands.rankings.&lt;bandType&gt;</c>).</summary>
    public string AutomationId => "fst.bands.rankings." + BandType.ServiceId();

    /// <summary>Screen-reader name.</summary>
    public string Announcement => $"{Label} band rankings";
}
#endregion
