using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Festival.Core.Domain;

namespace Festival.Core.ViewModels;

#region Player bands
/// <summary>
/// <c>/bands/player/:accountId</c>: a player's bands filtered by group (All/Duos/Trios/Quads), 25 per page
/// (web <c>PlayerBandsPage</c>). Late responses for a previous group or page are discarded.
/// </summary>
public sealed partial class PlayerBandsViewModel : ObservableObject
{
    /// <summary>Rows per page (web <c>PLAYER_BANDS_PAGE_SIZE</c>).</summary>
    public const int PageSize = 25;

    private readonly FestivalSession session;
    private int version;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="route">Player-bands route.</param>
    public PlayerBandsViewModel(FestivalSession session, AppRoute.PlayerBands route)
    {
        this.session = session;
        AccountId = route.AccountId;
        Pager = new BandsPagerViewModel(GoToPageAsync);
        Status = new ServiceStatusViewModel("player-bands:" + route.AccountId, "Failed to load bands", LoadAsync, session.Time);
        if (session.SelectedPlayer is { } player && player.AccountId == AccountId) PlayerName = player.DisplayName;
        LoadSwap = new LoadSwap(session.Time);
        LoadSwap.PropertyChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(IsLoading));
            OnPropertyChanged(nameof(ShowRows));
            OnPropertyChanged(nameof(ShowEmpty));
            OnPropertyChanged(nameof(ShowError));
        };
    }

    /// <summary>Player whose bands are listed.</summary>
    public string AccountId { get; }

    /// <summary>Paging state.</summary>
    public BandsPagerViewModel Pager { get; }

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Cards/content load-swap gate.</summary>
    public LoadSwap LoadSwap { get; }

    /// <summary>Whether load-swap motion is allowed; the app layer supplies <c>Motion.Allowed</c>.</summary>
    public Func<bool> AnimateLoadSwaps { get; set; } = () => false;

    /// <summary>Group options in segmented-control order.</summary>
    public List<PlayerBandGroup> Groups { get; } = [.. PlayerBandGroupInfo.All];

    /// <summary>Applied group.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Subtitle), nameof(EmptyMessage), nameof(GroupIndex))]
    private PlayerBandGroup group = PlayerBandGroup.All;

    /// <summary>Load lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowRows), nameof(ShowEmpty), nameof(ShowError))]
    private LoadState state = LoadState.Idle;

    /// <summary>Band cards on this page.</summary>
    [ObservableProperty]
    private List<PlayerBandCardViewModel> entries = [];

    /// <summary>Bands across all pages, once known.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Subtitle))]
    private int? totalCount;

    /// <summary>Player name from the selection or the rows, once known.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Title))]
    private string? playerName;

    /// <summary><c>Name's Bands</c>, or <c>Player Bands</c>.</summary>
    public string Title => PlayerName is { Length: > 0 } name ? $"{name}'s Bands" : "Player Bands";

    /// <summary><c>All Bands · 12 bands</c>.</summary>
    public string Subtitle => TotalCount is { } count
        ? $"{Group.Label()} · {BandFormatting.Count(count)} {(count == 1 ? "band" : "bands")}" : Group.Label();

    /// <summary>Empty-state body.</summary>
    public string EmptyMessage => $"No {(Group == PlayerBandGroup.All ? "bands" : Group.Label())} have been recorded for this player yet.";

    /// <summary>Index of <see cref="Group"/> in <see cref="Groups"/> (segmented control binding).</summary>
    public int GroupIndex
    {
        get => (int)Group;
        set
        {
            if (value >= 0 && value < Groups.Count) Group = Groups[value];
        }
    }

    /// <summary>Whether the first read of a selection is in flight.</summary>
    public bool IsLoading => LoadSwap.IsLoading;

    /// <summary>Whether cards are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded && LoadSwap.ContentVisible;

    /// <summary>Whether the empty state is shown.</summary>
    public bool ShowEmpty => State == LoadState.Empty && LoadSwap.ContentVisible;

    /// <summary>Whether the status view is shown.</summary>
    public bool ShowError => State == LoadState.Failed && LoadSwap.ContentVisible;

    /// <summary>Changing the group returns to page one.</summary>
    /// <param name="value">New group.</param>
    partial void OnGroupChanged(PlayerBandGroup value)
    {
        Pager.Page = 1;
        _ = LoadAsync();
    }

    /// <summary>Loads the current group and page.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand]
    public async Task LoadAsync()
    {
        var requested = ++version;
        var (group, page) = (Group, Pager.Page);
        var swap = LoadSwap.BeginReloadAsync(AnimateLoadSwaps(), State is LoadState.Loaded or LoadState.Empty or LoadState.Failed && LoadSwap.ContentVisible);
        if (State is LoadState.Idle) State = LoadState.Loading;
        try
        {
            var list = await session.Api.GetPlayerBandsAsync(AccountId, group, page, PageSize);
            if (requested != version) return;
            var pages = list.PageCount(PageSize);
            if (page > pages)
            {
                Pager.PageCount = pages;
                Pager.Page = pages;
                await LoadAsync();
                return;
            }
            var swapRequest = await swap;
            await LoadSwap.CommitAsync(swapRequest, () =>
            {
                Status.Clear();
                TotalCount = list.TotalCount;
                Pager.PageCount = pages;
                PlayerName ??= list.Entries.SelectMany(e => e.Members)
                    .FirstOrDefault(m => m.AccountId == AccountId && !string.IsNullOrWhiteSpace(m.DisplayName))?.ResolvedName;
                Entries = [.. list.Entries.Select(e => new PlayerBandCardViewModel(e))];
                State = Entries.Count == 0 ? LoadState.Empty : LoadState.Loaded;
            }, AnimateLoadSwaps());
        }
        catch (FestivalApiException error)
        {
            if (requested != version) return;
            var swapRequest = await swap;
            await LoadSwap.CommitAsync(swapRequest, () =>
            {
                Status.Report(error);
                State = LoadState.Failed;
            }, AnimateLoadSwaps());
        }
    }

    /// <summary>Loads a page (pager commands).</summary>
    /// <param name="page">One-based page.</param>
    /// <returns>Load task.</returns>
    private Task GoToPageAsync(int page)
    {
        Pager.Page = Math.Clamp(page, 1, Pager.PageCount);
        return LoadAsync();
    }
}
#endregion
