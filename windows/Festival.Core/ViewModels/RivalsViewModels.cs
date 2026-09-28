using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Rival row
/// <summary>
/// One rival row (web <c>RivalRow</c>). As on the web, the "ahead" pill shows the rival's <c>behindCount</c> and the
/// "behind" pill its <c>aheadCount</c>: the wire counts are from the rival's perspective.
/// </summary>
/// <param name="AccountId">Rival account.</param>
/// <param name="Name">Display name (or "Unknown Player").</param>
/// <param name="Direction">Above (rival leads overall) or below.</param>
/// <param name="SharedSongCount">Shared songs.</param>
/// <param name="SongsAhead">Songs the player leads.</param>
/// <param name="SongsBehind">Songs the rival leads.</param>
/// <param name="LeaderboardRank">Rival's global rank for leaderboard rivals.</param>
/// <param name="Route">Rival Detail route carrying the row's scope.</param>
public sealed record RivalRowItem(
    string AccountId, string Name, RivalDirection Direction, int SharedSongCount, int SongsAhead, int SongsBehind,
    int? LeaderboardRank, AppRoute.RivalDetail Route)
{
    /// <summary>Row for a shared-song rival.</summary>
    /// <param name="rival">Summary.</param>
    /// <param name="direction">List half.</param>
    /// <param name="scope">Scope the list was read under.</param>
    /// <returns>Row.</returns>
    public static RivalRowItem From(RivalSummary rival, RivalDirection direction, RivalScope? scope) =>
        new(rival.AccountId, rival.DisplayName ?? UnknownName, direction, rival.SharedSongCount, rival.BehindCount, rival.AheadCount, null,
            new AppRoute.RivalDetail(rival.AccountId, rival.DisplayName, scope));

    /// <summary>Row for a leaderboard rival.</summary>
    /// <param name="rival">Summary.</param>
    /// <param name="direction">List half.</param>
    /// <param name="scope">Leaderboard scope.</param>
    /// <returns>Row.</returns>
    public static RivalRowItem From(LeaderboardRivalSummary rival, RivalDirection direction, RivalScope scope) =>
        new(rival.AccountId, rival.DisplayName ?? UnknownName, direction, rival.SharedSongCount, rival.BehindCount, rival.AheadCount,
            rival.LeaderboardRank, new AppRoute.RivalDetail(rival.AccountId, rival.DisplayName, scope));

    /// <summary>Fallback name (web <c>Unknown Player</c>).</summary>
    public const string UnknownName = "Unknown Player";

    /// <summary>Whether the player leads this rival overall (green tint).</summary>
    public bool IsWinning => Direction == RivalDirection.Below;

    /// <summary><c>{n} shared songs</c>.</summary>
    public string SharedText => string.Create(CultureInfo.CurrentCulture, $"{SharedSongCount:N0} shared songs");

    /// <summary><c>{n} songs ahead</c>.</summary>
    public string AheadText => string.Create(CultureInfo.CurrentCulture, $"{SongsAhead:N0} songs ahead");

    /// <summary><c>{n} songs behind</c>.</summary>
    public string BehindText => string.Create(CultureInfo.CurrentCulture, $"{SongsBehind:N0} songs behind");

    /// <summary><c>#rank</c> for leaderboard rivals, else empty.</summary>
    public string RankText => LeaderboardRank is { } rank ? string.Create(CultureInfo.CurrentCulture, $"#{rank:N0}") : "";

    /// <summary>Whether a rank is shown.</summary>
    public bool HasRank => LeaderboardRank is not null;

    /// <summary>Screen-reader name.</summary>
    public string AccessibleName =>
        $"{Name}{(HasRank ? ", rank " + RankText[1..] : "")}, {(IsWinning ? "behind you" : "ahead of you")}, {SharedText}, {AheadText}, {BehindText}";

    /// <summary>UIA automation ID.</summary>
    public string AutomationId => "fst.rivals.row." + AccountId;
}
#endregion

#region Section
/// <summary>One independently loaded hub section (Common, Combined, or one chart) showing three rivals above and below.</summary>
public sealed partial class RivalSectionViewModel : ObservableObject
{
    /// <summary>Rows previewed from each half (web <c>PREVIEW_COUNT</c>).</summary>
    public const int PreviewCount = 3;

    private readonly Func<CancellationToken, Task<(List<RivalRowItem> Above, List<RivalRowItem> Below)>> load;
    private CancellationTokenSource? loading;

    /// <summary>Creates a section.</summary>
    /// <param name="id">Stable ID (<c>common</c>, <c>combo</c> or a service instrument ID).</param>
    /// <param name="title">Card title.</param>
    /// <param name="icon">Instrument icon, if any.</param>
    /// <param name="scope">Scope for View All.</param>
    /// <param name="load">Reads above/below rows.</param>
    /// <param name="time">Clock for the status countdown.</param>
    public RivalSectionViewModel(string id, string title, Instrument? icon, RivalScope scope,
        Func<CancellationToken, Task<(List<RivalRowItem> Above, List<RivalRowItem> Below)>> load, TimeProvider time)
    {
        Id = id;
        Title = title;
        Icon = icon;
        ViewAllRoute = new AppRoute.AllRivals(scope);
        this.load = load;
        Status = new ServiceStatusViewModel("rivals:" + id, title + " unavailable", () => LoadAsync(), time);
    }

    /// <summary>Stable section ID.</summary>
    public string Id { get; }

    /// <summary>Card title.</summary>
    public string Title { get; }

    /// <summary>Instrument icon, if any.</summary>
    public Instrument? Icon { get; }

    /// <summary>Whether an icon is shown.</summary>
    public bool HasIcon => Icon is not null;

    /// <summary>Icon file.</summary>
    public string IconFile => Icon?.IconFile() ?? "";

    /// <summary>Accessible name of the See All link.</summary>
    public string SeeAllName => "See all " + Title;

    /// <summary>All Rivals route for this scope.</summary>
    public AppRoute.AllRivals ViewAllRoute { get; }

    /// <summary>UIA automation ID (leaderboard sections are distinct so recycled Song-tab cards never match).</summary>
    public string AutomationId => "fst.rivals.section." + (ViewAllRoute.Scope is RivalScope.Leaderboard ? "leaderboard." : "") + Id;

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Load lifecycle.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowRows), nameof(ShowError), nameof(IsLoading))]
    private LoadState state = LoadState.Idle;

    /// <summary>Preview rows (up to three above, then up to three below).</summary>
    [ObservableProperty]
    private List<RivalRowItem> rows = [];

    /// <summary>Whether rows are shown.</summary>
    public bool ShowRows => State == LoadState.Loaded;

    /// <summary>Whether the inline status is shown.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Whether the placeholder is shown.</summary>
    public bool IsLoading => State is LoadState.Loading or LoadState.Idle;

    /// <summary>Loads (or reloads) the section.</summary>
    /// <param name="cancellationToken">Cancelled when the hub rebuilds.</param>
    /// <returns>Load task.</returns>
    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        loading?.Cancel();
        var cts = loading = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        State = LoadState.Loading;
        try
        {
            var (above, below) = await load(cts.Token);
            if (cts.IsCancellationRequested) return;
            Status.Clear();
            Rows = [.. above.Take(PreviewCount), .. below.Take(PreviewCount)];
            State = Rows.Count == 0 ? LoadState.Empty : LoadState.Loaded;
        }
        catch (OperationCanceledException)
        {
            // Superseded.
        }
        catch (FestivalApiException error)
        {
            if (cts.IsCancellationRequested) return;
            Status.Report(error);
            State = LoadState.Failed;
        }
    }

    /// <summary>Stops an in-flight load.</summary>
    public void Cancel() => loading?.Cancel();
}
#endregion

#region Hub
/// <summary>Song Rivals or Leaderboard Rivals.</summary>
public enum RivalsTab
{
    /// <summary>Shared-song rivals.</summary>
    Song,
    /// <summary>Global leaderboard neighbours.</summary>
    Leaderboard,
}

/// <summary>What the hub shows instead of (or around) its sections.</summary>
public enum RivalsHubState
{
    /// <summary>No player selected.</summary>
    NoPlayer,
    /// <summary>Sections are loading and none has rows yet.</summary>
    Loading,
    /// <summary>At least one section is shown.</summary>
    Loaded,
    /// <summary>Every section settled empty.</summary>
    Empty,
}

/// <summary>
/// <c>/rivals</c>: Song Rivals (Common Rivals when two or more charts are visible, the Settings-derived Combined or
/// Pro Drums Family scope, then one section per visible chart) or Leaderboard Rivals (one section per chart, optional
/// rank-by metric with experimental ranks). Sections load independently; empty ones are removed.
/// </summary>
public sealed partial class RivalsHubViewModel : ObservableObject
{
    private readonly FestivalSession session;
    private readonly List<RivalSectionViewModel> all = [];
    private CancellationTokenSource? build;
    private string? builtKey;
    private bool active;

    /// <summary>Creates the hub.</summary>
    /// <param name="session">Shared session.</param>
    public RivalsHubViewModel(FestivalSession session)
    {
        this.session = session;
        FindRival = GlobalSearchViewModel.ForPlayers(session, excludeSelected: true);
    }

    /// <summary>Find Rival: the global-search engine limited to players, without the selected player.</summary>
    public GlobalSearchViewModel FindRival { get; }

    /// <summary>
    /// Rival Detail for a Find Rival result: no scope, so it merges every visible chart, and the live fallback is allowed
    /// because an arbitrary account usually has no precomputed rivalry (web <c>RivalsPage.handleFindRivalSelect</c>).
    /// </summary>
    /// <param name="result">Search result.</param>
    /// <returns>Route.</returns>
    public static AppRoute.RivalDetail FindRivalRoute(GlobalPlayerResult result) =>
        new(result.AccountId, result.DisplayName, AllowLiveFallback: true);

    /// <summary>Visible (non-empty) sections in order.</summary>
    public ObservableCollection<RivalSectionViewModel> Sections { get; } = [];

    /// <summary>Selected tab.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Title), nameof(ShowMetricPicker), nameof(IsLeaderboardTab), nameof(ToggleTabLabel))]
    private RivalsTab tab = RivalsTab.Song;

    /// <summary>Requested leaderboard metric (effective only with experimental ranks).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(MetricIndex))]
    private RankingMetric metric = RankingMetricInfo.Default;

    /// <summary>Overall state.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowEmpty), nameof(ShowNoPlayer), nameof(IsLoading))]
    private RivalsHubState state = RivalsHubState.NoPlayer;

    /// <summary>Page heading (web header shows the active tab name).</summary>
    public string Title => Tab == RivalsTab.Song ? "Song Rivals" : "Leaderboard Rivals";

    /// <summary>Whether the Leaderboard tab is selected.</summary>
    public bool IsLeaderboardTab
    {
        get => Tab == RivalsTab.Leaderboard;
        set => Tab = value ? RivalsTab.Leaderboard : RivalsTab.Song;
    }

    /// <summary>Label of the other tab (keyboard toggle).</summary>
    public string ToggleTabLabel => Tab == RivalsTab.Song ? "Leaderboard Rivals" : "Song Rivals";

    /// <summary>Whether the rank-by picker is shown.</summary>
    public bool ShowMetricPicker => Tab == RivalsTab.Leaderboard && session.Settings.ExperimentalRanks;

    /// <summary>Metric labels in picker order.</summary>
    public List<string> MetricLabels { get; } = [.. RankingMetricInfo.All.Select(m => m.Label())];

    /// <summary>Picker index of <see cref="Metric"/>.</summary>
    public int MetricIndex
    {
        get => RankingMetricInfo.All.ToList().IndexOf(Metric);
        set
        {
            if (value >= 0 && value < RankingMetricInfo.All.Count) Metric = RankingMetricInfo.All[value];
        }
    }

    /// <summary>Whether the empty state is shown.</summary>
    public bool ShowEmpty => State == RivalsHubState.Empty;

    /// <summary>Quick Links: one per visible section (web <c>common</c>, <c>combo</c>, instrument keys); two or more to show.</summary>
    public QuickLinksViewModel QuickLinks { get; } = new("Quick Links");

    /// <summary>Whether the no-player state is shown.</summary>
    public bool ShowNoPlayer => State == RivalsHubState.NoPlayer;

    /// <summary>Whether the page-level loading indicator is shown.</summary>
    public bool IsLoading => State == RivalsHubState.Loading;

    /// <summary>Empty-state title (web <c>rivals.noRivals</c>).</summary>
    public string EmptyTitle => "Not enough data to identify rivals yet.";

    /// <summary>Empty-state subtitle (web singular/plural variants).</summary>
    public string EmptySubtitle => session.Settings.VisibleInstruments.Count == 1
        ? "Play more songs on your selected instrument to generate a roster of Rivals."
        : "Play more songs on your selected instruments to generate a roster of Rivals.";

    /// <summary>Starts observing settings and (re)builds when anything relevant changed while away.</summary>
    public void Activate()
    {
        if (!active) session.PropertyChanged += OnSessionChanged;
        active = true;
        Rebuild(force: false);
    }

    /// <summary>Stops observing settings and cancels loads.</summary>
    public void Deactivate()
    {
        if (active) session.PropertyChanged -= OnSessionChanged;
        active = false;
    }

    /// <summary>Clears the shared cache and reloads every section (F5).</summary>
    [RelayCommand]
    private void Refresh()
    {
        session.RivalsCache.Clear();
        Rebuild(force: true);
    }

    /// <summary>Switches between Song and Leaderboard rivals.</summary>
    [RelayCommand]
    private void ToggleTab() => Tab = Tab == RivalsTab.Song ? RivalsTab.Leaderboard : RivalsTab.Song;

    /// <summary>Rebuilds on tab change.</summary>
    /// <param name="value">New tab.</param>
    partial void OnTabChanged(RivalsTab value) => Rebuild(force: false);

    /// <summary>Rebuilds on metric change.</summary>
    /// <param name="value">New metric.</param>
    partial void OnMetricChanged(RankingMetric value) => Rebuild(force: false);

    /// <summary>Rebuilds when the player, visible charts or experimental ranks change.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(FestivalSession.Settings)) return;
        OnPropertyChanged(nameof(ShowMetricPicker));
        OnPropertyChanged(nameof(EmptySubtitle));
        Rebuild(force: false);
    }

    /// <summary>Everything that determines the section set.</summary>
    /// <returns>Key.</returns>
    private string BuildKey()
    {
        var s = session.Settings;
        return $"{s.SelectedPlayer?.AccountId}|{string.Join(',', s.VisibleInstruments)}|{Tab}|{session.EffectiveRivalMetric(Metric)}";
    }

    /// <summary>Creates and starts the sections for the current tab and settings.</summary>
    /// <param name="force">Rebuild even when nothing changed.</param>
    private void Rebuild(bool force)
    {
        var key = BuildKey();
        if (!force && key == builtKey) return;
        builtKey = key;
        build?.Cancel();
        foreach (var section in all)
        {
            section.Cancel();
            section.PropertyChanged -= OnSectionChanged;
        }
        all.Clear();
        Sections.Clear();
        if (!session.HasPlayer)
        {
            State = RivalsHubState.NoPlayer;
            return;
        }
        build = new CancellationTokenSource();
        all.AddRange(Tab == RivalsTab.Song ? SongSections() : LeaderboardSections());
        foreach (var section in all)
        {
            section.PropertyChanged += OnSectionChanged;
            Sections.Add(section);
        }
        UpdateState();
        foreach (var section in all) _ = section.LoadAsync(build.Token);
    }

    /// <summary>Song-tab sections in web order.</summary>
    /// <returns>Sections.</returns>
    private IEnumerable<RivalSectionViewModel> SongSections()
    {
        var visible = session.Settings.VisibleInstruments;
        if (visible.Count >= 2)
        {
            var scope = new RivalScope.Song(visible);
            yield return new RivalSectionViewModel("common", "Common Rivals", null, scope, async ct =>
            {
                var (above, below) = await session.GetCommonRivalsAsync(visible, ct);
                return (Rows(above, RivalDirection.Above, scope), Rows(below, RivalDirection.Below, scope));
            }, session.Time);
        }
        if (RivalCombo.DeriveToken(visible) is { } token)
        {
            var scope = new RivalScope.Combo(token);
            yield return new RivalSectionViewModel("combo", scope.ListTitle, null, scope, ct => ListRows(token, scope, ct), session.Time);
        }
        foreach (var instrument in visible)
        {
            var scope = new RivalScope.Song([instrument]);
            yield return new RivalSectionViewModel(instrument.ServiceId(), scope.ListTitle, instrument, scope,
                ct => ListRows(instrument.ServiceId(), scope, ct), session.Time);
        }
    }

    /// <summary>Leaderboard-tab sections, one per visible chart.</summary>
    /// <returns>Sections.</returns>
    private IEnumerable<RivalSectionViewModel> LeaderboardSections()
    {
        var metric = session.EffectiveRivalMetric(Metric);
        foreach (var instrument in session.Settings.VisibleInstruments)
        {
            var scope = new RivalScope.Leaderboard(instrument, metric);
            yield return new RivalSectionViewModel(instrument.ServiceId(), scope.ListTitle, instrument, scope, async ct =>
            {
                var list = await session.GetLeaderboardRivalsAsync(instrument, metric, ct);
                return ([.. list.Above.Select(r => RivalRowItem.From(r, RivalDirection.Above, scope))],
                        [.. list.Below.Select(r => RivalRowItem.From(r, RivalDirection.Below, scope))]);
            }, session.Time);
        }
    }

    /// <summary>Reads a shared-song list as rows.</summary>
    /// <param name="token">Chart or combo token.</param>
    /// <param name="scope">Row scope.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Rows.</returns>
    private async Task<(List<RivalRowItem> Above, List<RivalRowItem> Below)> ListRows(string token, RivalScope scope, CancellationToken cancellationToken)
    {
        var list = await session.GetRivalsListAsync(token, cancellationToken);
        return (Rows(list.Above, RivalDirection.Above, scope), Rows(list.Below, RivalDirection.Below, scope));
    }

    /// <summary>Maps summaries to rows.</summary>
    /// <param name="rivals">Summaries.</param>
    /// <param name="direction">Half.</param>
    /// <param name="scope">Scope.</param>
    /// <returns>Rows.</returns>
    internal static List<RivalRowItem> Rows(IEnumerable<RivalSummary> rivals, RivalDirection direction, RivalScope? scope) =>
        [.. rivals.Select(r => RivalRowItem.From(r, direction, scope))];

    /// <summary>Removes sections that settle empty and recomputes the overall state.</summary>
    /// <param name="sender">Section.</param>
    /// <param name="e">Changed property.</param>
    private void OnSectionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(RivalSectionViewModel.State) || sender is not RivalSectionViewModel section) return;
        if (section.State == LoadState.Empty) Sections.Remove(section);
        UpdateState();
    }

    /// <summary>People glyph for Common Rivals (web <c>IoPeople</c>).</summary>
    public const string CommonGlyph = "\uE716";

    /// <summary>Music glyph for the combo section (web <c>IoMusicalNotes</c>).</summary>
    public const string ComboGlyph = "\uE8D6";

    /// <summary>Loading while anything loads and nothing shows; Empty once every section settled empty.</summary>
    private void UpdateState()
    {
        QuickLinks.SetSections(Sections.Select(s => new QuickLinkSection(s.Id, s.Title,
            s.Icon is null ? s.Id == "common" ? CommonGlyph : ComboGlyph : null, s.Icon)));
        if (all.Count > 0 && all.All(s => s.State == LoadState.Empty)) State = RivalsHubState.Empty;
        else if (all.Count == 0) State = RivalsHubState.Empty;
        else State = all.Any(s => s.State is LoadState.Loaded or LoadState.Failed) ? RivalsHubState.Loaded : RivalsHubState.Loading;
    }
}
#endregion

