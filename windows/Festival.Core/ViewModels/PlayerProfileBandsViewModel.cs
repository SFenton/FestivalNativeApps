using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace Festival.Core.ViewModels;

#region Player profile bands
/// <summary>
/// The profile's inline "{name}'s Bands" section (web <c>PlayerBandsSection.buildPlayerBandsItems</c>, issue #312): a
/// heading with a View All link, then Duos, Trios and Quads groups, each with up to <see cref="PreviewSize"/> band cards, a
/// "No Bands Yet" card when empty and "View All Bands (N)" when the group has more. The web fills it from player-stats
/// (blocked); natives read one keyless <c>GET /api/player/{id}/bands?group=&amp;page=1&amp;pageSize=6</c> per group.
/// The section loads after the profile and never holds the page spinner; any failed group fails the section with one
/// Retry that re-reads every group.
/// </summary>
public sealed partial class PlayerProfileBandsViewModel : ObservableObject
{
    /// <summary>Cards per group (the service's player-stats <c>GetPlayerBands</c> <c>previewCount</c>).</summary>
    public const int PreviewSize = 6;

    /// <summary>Groups the profile previews, in web order (All is only reachable through the title-row View All).</summary>
    public static IReadOnlyList<PlayerBandGroup> PreviewGroups { get; } = [PlayerBandGroup.Duos, PlayerBandGroup.Trios, PlayerBandGroup.Quads];

    private readonly FestivalSession session;
    private CancellationTokenSource? load;

    /// <summary>Creates the section in its loading state.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="accountId">Profile account.</param>
    /// <param name="playerName">Profile display name.</param>
    public PlayerProfileBandsViewModel(FestivalSession session, string accountId, string playerName)
    {
        this.session = session;
        AccountId = accountId;
        this.playerName = playerName;
        Status = new ServiceStatusViewModel("player-profile-bands:" + accountId, "Bands unavailable", LoadAsync, session.Time);
    }

    /// <summary>Profile account.</summary>
    public string AccountId { get; }

    /// <summary>Failed-read presentation with Retry.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Profile display name (updated when the profile read renames the player).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Title), nameof(ListLinkName), nameof(ListLinkRoute))]
    private string playerName;

    /// <summary>Load lifecycle (Loading, Loaded or Failed).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowGroups), nameof(ShowError))]
    private LoadState state = LoadState.Loading;

    /// <summary>Duos, Trios and Quads previews once loaded.</summary>
    [ObservableProperty]
    private List<PlayerProfileBandGroup> groups = [];

    /// <summary><c>{name}'s Bands</c> (web <c>player.bands</c>).</summary>
    public string Title => $"{PlayerName}'s Bands";

    /// <summary>Title-row link text (section-headers R8; owner #321: the app reads View All, never See All).</summary>
    public static string ListLinkText => ViewAllCta.ListLabel;

    /// <summary>Accessible name of the title-row link: the visible label first (WCAG 2.5.3), then the section.</summary>
    public string ListLinkName => ViewAllCta.Name(ListLinkText, Title);

    /// <summary>Player Bands on All (web <c>Routes.playerBands(id, 'all', 1, name)</c>).</summary>
    public AppRoute ListLinkRoute => new AppRoute.PlayerBands(AccountId, PlayerBandGroup.All, PlayerName);

    /// <summary>Whether the section spinner shows.</summary>
    public bool IsLoading => State is LoadState.Loading or LoadState.Idle;

    /// <summary>Whether the groups show.</summary>
    public bool ShowGroups => State == LoadState.Loaded;

    /// <summary>Whether the inline failure with Retry shows.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Reads every group's first page; a newer call supersedes an older one.</summary>
    /// <returns>Load task.</returns>
    public async Task LoadAsync()
    {
        load?.Cancel();
        var current = load = new CancellationTokenSource();
        State = LoadState.Loading;
        try
        {
            var pages = await Task.WhenAll(PreviewGroups.Select(g =>
                session.Api.GetPlayerBandsAsync(AccountId, g, 1, PreviewSize, current.Token)));
            if (current.IsCancellationRequested) return;
            Status.Clear();
            Groups = [.. PreviewGroups.Select((g, i) => new PlayerProfileBandGroup(AccountId, PlayerName, g, pages[i]))];
            State = LoadState.Loaded;
        }
        catch (OperationCanceledException)
        {
            // Superseded or the page left.
        }
        catch (FestivalApiException error)
        {
            if (current.IsCancellationRequested) return;
            Groups = [];
            Status.Report(error);
            State = LoadState.Failed;
        }
    }

    /// <summary>Cancels a pending read (profile replaced or unloaded).</summary>
    public void Cancel() => load?.Cancel();

    /// <summary>Carries a renamed player into the groups' View All routes.</summary>
    /// <param name="value">New name.</param>
    partial void OnPlayerNameChanged(string value)
    {
        if (Groups.Count > 0) Groups = [.. Groups.Select(g => g with { PlayerName = value })];
    }
}

/// <summary>One band-size group in the profile's bands section.</summary>
/// <param name="AccountId">Profile account.</param>
/// <param name="PlayerName">Profile display name (View All title).</param>
/// <param name="Group">Duos, Trios or Quads.</param>
/// <param name="Page">First page of <see cref="PlayerProfileBandsViewModel.PreviewSize"/> rows.</param>
public sealed record PlayerProfileBandGroup(string AccountId, string PlayerName, PlayerBandGroup Group, PlayerBandListResponse Page)
{
    /// <summary>Empty-group title (web <c>player.noBandsYet</c>, Title Case like the native empty states).</summary>
    public const string EmptyTitle = "No Bands Yet";

    /// <summary>Empty-group subtitle (web <c>player.noBandsYetSubtitle</c>).</summary>
    public const string EmptySubtitle = "Band lineups will appear here once this player posts band scores.";

    /// <summary>Band cards (each opens Band Detail).</summary>
    public List<PlayerBandCardViewModel> Cards { get; } = [.. Page.Entries.Select(e => new PlayerBandCardViewModel(e))];

    /// <summary><c>Duos</c>, <c>Trios</c> or <c>Quads</c>.</summary>
    public string Title => Group.Label();

    /// <summary>Service ID of the group (<c>duos</c>), part of the automation IDs.</summary>
    public string Key => Group.ServiceId();

    /// <summary>Whether the group has no bands.</summary>
    public bool IsEmpty => Cards.Count == 0;

    /// <summary>Whether cards show.</summary>
    public bool HasCards => Cards.Count > 0;

    /// <summary>Whether the group has more bands than the preview (web <c>totalCount &gt; entries.length</c>).</summary>
    public bool HasMore => Page.TotalCount > Cards.Count;

    /// <summary><c>View All Bands (12)</c> (web <c>player.viewAllBands</c>, Title Case like the native View All buttons).</summary>
    public string ViewAllText => string.Create(CultureInfo.CurrentCulture, $"{ViewAllCta.BandsLabel} ({Page.TotalCount:N0})");

    /// <summary>Accessible name of View All: the visible label, then the group (WCAG 2.5.3, like the ranking cards).</summary>
    public string ViewAllName => ViewAllCta.Name(ViewAllText, Title);

    /// <summary>Player Bands filtered to this group.</summary>
    public AppRoute ViewAllRoute => new AppRoute.PlayerBands(AccountId, Group, PlayerName);

    /// <summary>Automation ID of the group header.</summary>
    public string HeaderAutomationId => "fst.player.bands.header." + Key;

    /// <summary>Automation ID of the empty-state title.</summary>
    public string EmptyAutomationId => "fst.player.bands.empty." + Key;

    /// <summary>Automation ID of View All.</summary>
    public string ViewAllAutomationId => "fst.player.bands.view-all." + Key;
}
#endregion
