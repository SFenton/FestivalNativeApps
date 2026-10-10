using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Profile button
/// <summary>What the title-bar profile button does (web <c>getProfileClickDestination</c>, issue #290).</summary>
public enum ProfileButtonAction
{
    /// <summary>No selected player: open the profile picker flyout.</summary>
    OpenPicker,

    /// <summary>A selected player: show their Statistics (their own profile), never the picker.</summary>
    ShowStatistics,
}
#endregion

#region Shell
/// <summary>Navigation sections, the title-bar profile avatar and the profile selection flyout.</summary>
public sealed partial class ShellViewModel : ObservableObject
{
    /// <summary>Profile search debounce (web <c>useUnifiedSearch</c>: 250 ms; the global-search engine's).</summary>
    public static readonly TimeSpan SearchDebounce = GlobalSearchViewModel.Debounce;

    private readonly FestivalSession session;
    private string? selectedAccount;

    /// <summary>Creates the shell model and starts loading a restored player's scores.</summary>
    /// <param name="session">Shared session.</param>
    public ShellViewModel(FestivalSession session)
    {
        this.session = session;
        ProfileSearch = GlobalSearchViewModel.ForProfiles(session);
        ProfileSearch.PropertyChanged += OnProfileSearchChanged;
        foreach (var section in AppSections.Visible(session.HasPlayer, session.Settings.HideShop)) Sections.Add(section);
        selectedAccount = session.SelectedPlayer?.AccountId;
        session.PropertyChanged += OnSessionChanged;
        if (session.HasPlayer) _ = session.LoadSelectedProfileAsync();
    }

    /// <summary>Raised when the flyout opens a route (a search result or the selected profile).</summary>
    public event EventHandler<AppRoute>? RouteRequested;

    /// <summary>Visible sections in pane order (Settings is the footer item).</summary>
    public ObservableCollection<AppSection> Sections { get; } = [];

    /// <summary>Whether a player is selected.</summary>
    public bool HasPlayer => session.HasPlayer;

    /// <summary>Selected player's name, or the prompt.</summary>
    public string ProfileName => session.SelectedPlayer?.DisplayName ?? "Select Player";

    /// <summary>Selected player's name for <c>PersonPicture.DisplayName</c> (empty shows the generic glyph).</summary>
    public string ProfileDisplayName => session.SelectedPlayer?.DisplayName ?? "";

    /// <summary>Avatar initials (empty shows the generic glyph).</summary>
    public string ProfileInitials => session.SelectedPlayer?.Initials ?? "";

    /// <summary>Accessible name of the avatar button.</summary>
    public string ProfileButtonName => session.SelectedPlayer is { } p ? $"Profile: {p.DisplayName}" : "Select a player profile";

    /// <summary>
    /// The avatar button's click: the selected player's Statistics, or the picker when anonymous. The picker stays
    /// reachable with a player through the button's context menu (right-click, Shift+F10) and Ctrl+Shift+P.
    /// </summary>
    public ProfileButtonAction ProfileButtonAction =>
        session.HasPlayer ? ProfileButtonAction.ShowStatistics : ProfileButtonAction.OpenPicker;

    /// <summary>Avatar button tooltip: what a click does, and the picker shortcut.</summary>
    public string ProfileButtonToolTip => session.SelectedPlayer is { } p
        ? $"Show Statistics for {p.DisplayName}\nSwitch profile: Ctrl+Shift+P"
        : "Select Player (Ctrl+Shift+P)";

    /// <summary>Avatar button UIA help text (Narrator reads it after the name).</summary>
    public string ProfileButtonHelp => session.HasPlayer
        ? "Opens your statistics. Press Control+Shift+P or open the context menu to switch profile."
        : "Opens profile selection.";

    /// <summary>The flyout's profile search: the global-search engine over players and bands, without songs (issue #600).</summary>
    public GlobalSearchViewModel ProfileSearch { get; }

    /// <summary>Profile search text (forwards to <see cref="ProfileSearch"/>).</summary>
    public string ProfileQuery
    {
        get => ProfileSearch.Query;
        set => ProfileSearch.Query = value;
    }

    /// <summary>
    /// The flyout's All · Players · Bands scope (forwards to <see cref="ProfileSearch"/>; starts on All). Songs is not a
    /// profile scope and maps to All.
    /// </summary>
    public SearchScope ProfileScope
    {
        get => ProfileSearch.Scope;
        set => ProfileSearch.Scope = value == SearchScope.Songs ? SearchScope.All : value;
    }

    /// <summary>Player rows shown for the scope (All and Players; none on Bands).</summary>
    public List<GlobalPlayerResult> ProfileResults => ProfileScope == SearchScope.Bands ? [] : ProfileSearch.Players;

    /// <summary>Band cards shown for the scope (All and Bands; none on Players).</summary>
    public List<PlayerBandCardViewModel> ProfileBands => ProfileScope == SearchScope.Players ? [] : ProfileSearch.Bands;

    /// <summary>Whether player rows are shown.</summary>
    public bool HasProfileResults => ProfileResults.Count > 0;

    /// <summary>Whether band cards are shown.</summary>
    public bool HasProfileBands => ProfileBands.Count > 0;

    /// <summary>Whether any result is shown (the results region collapses otherwise).</summary>
    public bool HasAnyProfileResult => HasProfileResults || HasProfileBands;

    /// <summary>Whether the Players section title shows (All only, like global search's sections; issue #348).</summary>
    public bool ShowPlayersTitle => ProfileScope == SearchScope.All && HasProfileResults;

    /// <summary>Whether the Bands section title shows (All only).</summary>
    public bool ShowBandsTitle => ProfileScope == SearchScope.All && HasProfileBands;

    /// <summary>Search box placeholder and accessible name (one for every scope, like global search and the web).</summary>
    public string SearchPlaceholder => GlobalSearchResults.ProfilePlaceholder;

    /// <summary>Centered hint under the results.</summary>
    public string ProfileHint => ProfileSearch.PickerHint;

    /// <summary>Whether Retry is offered (after an error or an empty envelope, which is never proof of no match).</summary>
    public bool CanRetrySearch => ProfileSearch.CanRetryPicker;

    /// <summary>Runs the current query again immediately.</summary>
    public IAsyncRelayCommand RetrySearchCommand => ProfileSearch.RetryCommand;

    /// <summary>
    /// Opens the result Enter submits: the first row shown, players before bands (their order in All).
    /// </summary>
    /// <returns>Whether a result was opened.</returns>
    public bool OpenFirstResult()
    {
        if (ProfileResults.FirstOrDefault() is { } player && ProfileText.IsValidAccountId(player.AccountId)) OpenResult(PlayerRoute(player));
        else if (ProfileBands.FirstOrDefault() is { } band) OpenResult(band.Route);
        else return false;
        return true;
    }

    /// <summary>Opens a search result's player page (viewing; selecting is a separate action there).</summary>
    /// <param name="result">Chosen account.</param>
    [RelayCommand]
    private void ViewProfile(GlobalPlayerResult? result)
    {
        if (result is null || !ProfileText.IsValidAccountId(result.AccountId)) return;
        OpenResult(PlayerRoute(result));
    }

    /// <summary>
    /// Opens a band result's page (the band card's route). Windows can't select a band as the profile yet, so viewing is
    /// the supported action, like global search (issue #600).
    /// </summary>
    /// <param name="route">Band route.</param>
    public void ViewBand(AppRoute route)
    {
        if (route is AppRoute.Band) OpenResult(route);
    }

    /// <summary>Clears the search and raises the result's route.</summary>
    /// <param name="route">Destination.</param>
    private void OpenResult(AppRoute route)
    {
        ProfileSearch.Reset();
        RouteRequested?.Invoke(this, route);
    }

    /// <summary>A player result's page (viewing, never Statistics: the flyout lists the selected player like anyone).</summary>
    /// <param name="result">Account.</param>
    /// <returns>Player route.</returns>
    private static AppRoute PlayerRoute(GlobalPlayerResult result) => new AppRoute.Player(result.AccountId, result.DisplayName);

    /// <summary>Opens the selected player's page.</summary>
    [RelayCommand]
    private void ViewSelectedProfile()
    {
        if (session.SelectedPlayer is { } p) RouteRequested?.Invoke(this, new AppRoute.Player(p.AccountId, p.DisplayName));
    }

    /// <summary>Deselects the current player (the caller confirms first).</summary>
    [RelayCommand]
    private void DeselectProfile() => session.DeselectPlayer();

    /// <summary>Forwards search changes to the flyout bindings.</summary>
    /// <param name="sender">Search model.</param>
    /// <param name="e">Changed property.</param>
    private void OnProfileSearchChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(GlobalSearchViewModel.Query):
                OnPropertyChanged(nameof(ProfileQuery));
                break;
            case nameof(GlobalSearchViewModel.Scope):
                OnPropertyChanged(nameof(ProfileScope));
                OnResultsChanged();
                break;
            case nameof(GlobalSearchViewModel.Players):
            case nameof(GlobalSearchViewModel.Bands):
                OnResultsChanged();
                break;
            case nameof(GlobalSearchViewModel.PickerHint):
                OnPropertyChanged(nameof(ProfileHint));
                break;
            case nameof(GlobalSearchViewModel.CanRetryPicker):
                OnPropertyChanged(nameof(CanRetrySearch));
                break;
        }
    }

    /// <summary>Raises the scope-filtered result properties.</summary>
    private void OnResultsChanged()
    {
        OnPropertyChanged(nameof(ProfileResults));
        OnPropertyChanged(nameof(ProfileBands));
        OnPropertyChanged(nameof(HasProfileResults));
        OnPropertyChanged(nameof(HasProfileBands));
        OnPropertyChanged(nameof(HasAnyProfileResult));
        OnPropertyChanged(nameof(ShowPlayersTitle));
        OnPropertyChanged(nameof(ShowBandsTitle));
    }

    /// <summary>Tracks player selection for sections and the avatar.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(FestivalSession.Settings)) return;
        var wanted = AppSections.Visible(session.HasPlayer, session.Settings.HideShop);
        if (!wanted.SequenceEqual(Sections))
        {
            // Diff in place: a Clear() would briefly empty the set and send the shell back to Songs even when the
            // current section survives (selecting or deselecting must never navigate away).
            for (var i = Sections.Count - 1; i >= 0; i--)
                if (!wanted.Contains(Sections[i])) Sections.RemoveAt(i);
            for (var i = 0; i < wanted.Count; i++)
                if (i >= Sections.Count || Sections[i] != wanted[i]) Sections.Insert(i, wanted[i]);
        }
        if (session.SelectedPlayer?.AccountId != selectedAccount)
        {
            selectedAccount = session.SelectedPlayer?.AccountId;
            if (session.HasPlayer) _ = session.LoadSelectedProfileAsync();
        }
        OnPropertyChanged(nameof(HasPlayer));
        OnPropertyChanged(nameof(ProfileDisplayName));
        OnPropertyChanged(nameof(ProfileName));
        OnPropertyChanged(nameof(ProfileInitials));
        OnPropertyChanged(nameof(ProfileButtonName));
        OnPropertyChanged(nameof(ProfileButtonAction));
        OnPropertyChanged(nameof(ProfileButtonToolTip));
        OnPropertyChanged(nameof(ProfileButtonHelp));
    }
}
#endregion
