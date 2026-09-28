using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Shell
/// <summary>Navigation sections, the title-bar profile avatar and the profile selection flyout.</summary>
public sealed partial class ShellViewModel : ObservableObject
{
    /// <summary>Profile search debounce (web <c>useUnifiedSearch</c>: 250 ms).</summary>
    public static readonly TimeSpan SearchDebounce = TimeSpan.FromMilliseconds(250);

    /// <summary>Band-search explanation.</summary>
    public const string BandSearchExplanation =
        "Band search isn't available: the service's band search can change stored data, so this app doesn't call it. " +
        "Open a band from a player's Bands list or from Band Rankings.";

    private readonly FestivalSession session;
    private CancellationTokenSource? search;
    private string? selectedAccount;

    /// <summary>Creates the shell model and starts loading a restored player's scores.</summary>
    /// <param name="session">Shared session.</param>
    public ShellViewModel(FestivalSession session)
    {
        this.session = session;
        foreach (var section in AppSections.Visible(session.HasPlayer)) Sections.Add(section);
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

    /// <summary>Profile search text.</summary>
    [ObservableProperty]
    private string profileQuery = "";

    /// <summary>Whether the Bands target is chosen (band search is blocked: its GET can write).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ProfileHint), nameof(SearchPlaceholder), nameof(IsPlayerScope), nameof(CanRetrySearch))]
    private bool isBandScope;

    /// <summary>Search results.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ProfileHint), nameof(CanRetrySearch))]
    private List<PlayerSearchResult> profileResults = [];

    /// <summary>Whether a search is in flight.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ProfileHint), nameof(CanRetrySearch))]
    private bool isSearching;

    /// <summary>Search failure text.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ProfileHint), nameof(CanRetrySearch))]
    private string? profileError;

    /// <summary>Whether the Players target is chosen.</summary>
    public bool IsPlayerScope => !IsBandScope;

    /// <summary>Search box placeholder.</summary>
    public string SearchPlaceholder => IsBandScope ? "Find Band" : "Find Player";

    /// <summary>Centered hint under the search box.</summary>
    public string ProfileHint =>
        IsBandScope ? BandSearchExplanation :
        ProfileError ?? (IsSearching ? "Searching…" :
            ProfileQuery.Trim().Length < 2 ? "Enter at least 2 characters to search." :
            ProfileResults.Count == 0 ? "No players found." : "");

    /// <summary>Whether Retry is offered (after an error or an empty envelope, which is never proof of no match).</summary>
    public bool CanRetrySearch => IsPlayerScope && !IsSearching && ProfileQuery.Trim().Length >= 2 &&
                                  (ProfileError is not null || ProfileResults.Count == 0);

    /// <summary>Opens a search result's player page (viewing; selecting is a separate action there).</summary>
    /// <param name="result">Chosen account.</param>
    [RelayCommand]
    private void ViewProfile(PlayerSearchResult? result)
    {
        if (result is null || !ProfileText.IsValidAccountId(result.AccountId)) return;
        ProfileQuery = "";
        ProfileResults = [];
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

    /// <summary>Runs the current query again immediately.</summary>
    [RelayCommand]
    private void RetrySearch()
    {
        search?.Cancel();
        search = new CancellationTokenSource();
        ProfileError = null;
        _ = SearchAsync(ProfileQuery.Trim(), search.Token, debounce: false);
    }

    /// <summary>Debounces profile search.</summary>
    /// <param name="value">Query.</param>
    partial void OnProfileQueryChanged(string value)
    {
        search?.Cancel();
        search = new CancellationTokenSource();
        ProfileError = null;
        OnPropertyChanged(nameof(ProfileHint));
        OnPropertyChanged(nameof(CanRetrySearch));
        _ = SearchAsync(value.Trim(), search.Token, debounce: true);
    }

    /// <summary>Stops player search when switching to the (disabled) Bands target.</summary>
    /// <param name="value">Band scope.</param>
    partial void OnIsBandScopeChanged(bool value)
    {
        if (!value) return;
        search?.Cancel();
        IsSearching = false;
        ProfileError = null;
        ProfileResults = [];
    }

    /// <summary>Runs one account search.</summary>
    /// <param name="query">Trimmed query.</param>
    /// <param name="token">Cancelled by newer input.</param>
    /// <param name="debounce">Whether to wait for the debounce first.</param>
    /// <returns>Search task.</returns>
    private async Task SearchAsync(string query, CancellationToken token, bool debounce)
    {
        if (query.Length < 2 || IsBandScope)
        {
            ProfileResults = [];
            IsSearching = false;
            return;
        }
        try
        {
            if (debounce) await Task.Delay(SearchDebounce, session.Time, token);
            IsSearching = true;
            var response = await session.Api.SearchPlayersAsync(query, 10, token);
            token.ThrowIfCancellationRequested();
            ProfileResults = [.. response.Results];
            IsSearching = false;
        }
        catch (OperationCanceledException)
        {
            // Superseded by newer input.
        }
        catch (FestivalApiException error)
        {
            if (token.IsCancellationRequested) return;
            ProfileResults = [];
            IsSearching = false;
            ProfileError = ServiceIssue.From(error).Message;
        }
    }

    /// <summary>Tracks player selection for sections and the avatar.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(FestivalSession.Settings)) return;
        var wanted = AppSections.Visible(session.HasPlayer);
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
    }
}
#endregion
