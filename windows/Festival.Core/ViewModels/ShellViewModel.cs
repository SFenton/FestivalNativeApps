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

    /// <summary>Profile flyout Bands target: a band can't be the selected profile yet, so it points to global search,
    /// which finds and opens bands (issue #320; same copy as Android).</summary>
    public const string BandSearchExplanation =
        "Choosing a band as your profile isn't available in the app yet. " +
        "To find a band, use Search; you can also open one from a player's Bands list or Band Rankings.";

    private readonly FestivalSession session;
    private string? selectedAccount;

    /// <summary>Creates the shell model and starts loading a restored player's scores.</summary>
    /// <param name="session">Shared session.</param>
    public ShellViewModel(FestivalSession session)
    {
        this.session = session;
        ProfileSearch = GlobalSearchViewModel.ForPlayers(session);
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

    /// <summary>The flyout's player search: the global-search engine limited to players.</summary>
    public GlobalSearchViewModel ProfileSearch { get; }

    /// <summary>Profile search text (forwards to <see cref="ProfileSearch"/>).</summary>
    public string ProfileQuery
    {
        get => ProfileSearch.Query;
        set => ProfileSearch.Query = value;
    }

    /// <summary>Whether the Bands target is chosen (choosing a band as the profile isn't built; no band request here).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ProfileHint), nameof(SearchPlaceholder), nameof(IsPlayerScope), nameof(CanRetrySearch), nameof(ProfileResults))]
    private bool isBandScope;

    /// <summary>Player rows (none on the Bands target).</summary>
    public List<GlobalPlayerResult> ProfileResults => IsBandScope ? [] : ProfileSearch.Players;

    /// <summary>Whether the Players target is chosen.</summary>
    public bool IsPlayerScope => !IsBandScope;

    /// <summary>Search box placeholder.</summary>
    public string SearchPlaceholder => IsBandScope ? "Find Band" : "Find Player";

    /// <summary>Centered hint under the search box.</summary>
    public string ProfileHint => IsBandScope ? BandSearchExplanation : ProfileSearch.PlayersHint;

    /// <summary>Whether Retry is offered (after an error or an empty envelope, which is never proof of no match).</summary>
    public bool CanRetrySearch => IsPlayerScope && ProfileSearch.CanRetryPlayers;

    /// <summary>Runs the current query again immediately.</summary>
    public IAsyncRelayCommand RetrySearchCommand => ProfileSearch.RetryCommand;

    /// <summary>Opens a search result's player page (viewing; selecting is a separate action there).</summary>
    /// <param name="result">Chosen account.</param>
    [RelayCommand]
    private void ViewProfile(GlobalPlayerResult? result)
    {
        if (result is null || !ProfileText.IsValidAccountId(result.AccountId)) return;
        ProfileSearch.Reset();
        RouteRequested?.Invoke(this, new AppRoute.Player(result.AccountId, result.DisplayName));
    }

    /// <summary>Opens the selected player's page.</summary>
    [RelayCommand]
    private void ViewSelectedProfile()
    {
        if (session.SelectedPlayer is { } p) RouteRequested?.Invoke(this, new AppRoute.Player(p.AccountId, p.DisplayName));
    }

    /// <summary>Deselects the current player (the caller confirms first).</summary>
    [RelayCommand]
    private void DeselectProfile() => session.DeselectPlayer();

    /// <summary>Stops player search on the (disabled) Bands target; returning to Players searches the text again.</summary>
    /// <param name="value">Band scope.</param>
    partial void OnIsBandScopeChanged(bool value)
    {
        if (value) ProfileSearch.Deactivate();
        else if (ProfileSearch.RetryCommand.CanExecute(null)) ProfileSearch.RetryCommand.Execute(null);
    }

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
            case nameof(GlobalSearchViewModel.Players):
                OnPropertyChanged(nameof(ProfileResults));
                break;
            case nameof(GlobalSearchViewModel.PlayersHint):
                OnPropertyChanged(nameof(ProfileHint));
                break;
            case nameof(GlobalSearchViewModel.CanRetryPlayers):
                OnPropertyChanged(nameof(CanRetrySearch));
                break;
        }
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
