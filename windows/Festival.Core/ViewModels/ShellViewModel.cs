using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Shell
/// <summary>Navigation sections, the title-bar profile avatar and the profile selection flyout.</summary>
public sealed partial class ShellViewModel : ObservableObject
{
    /// <summary>Profile search debounce.</summary>
    public static readonly TimeSpan SearchDebounce = TimeSpan.FromMilliseconds(300);

    private readonly FestivalSession session;
    private CancellationTokenSource? search;

    /// <summary>Creates the shell model.</summary>
    /// <param name="session">Shared session.</param>
    public ShellViewModel(FestivalSession session)
    {
        this.session = session;
        foreach (var section in AppSections.Visible(session.HasPlayer)) Sections.Add(section);
        session.PropertyChanged += OnSessionChanged;
    }

    /// <summary>Visible sections in pane order (Settings is the footer item).</summary>
    public ObservableCollection<AppSection> Sections { get; } = [];

    /// <summary>Whether a player is selected.</summary>
    public bool HasPlayer => session.HasPlayer;

    /// <summary>Selected player's name, or the prompt.</summary>
    public string ProfileName => session.SelectedPlayer?.DisplayName ?? "Select Player";

    /// <summary>Avatar initials (empty shows the generic glyph).</summary>
    public string ProfileInitials => session.SelectedPlayer?.Initials ?? "";

    /// <summary>Accessible name of the avatar button.</summary>
    public string ProfileButtonName => session.SelectedPlayer is { } p ? $"Profile: {p.DisplayName}" : "Select a player profile";

    /// <summary>Profile search text.</summary>
    [ObservableProperty]
    private string profileQuery = "";

    /// <summary>Search results.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ProfileHint))]
    private IReadOnlyList<PlayerSearchResult> profileResults = [];

    /// <summary>Whether a search is in flight.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ProfileHint))]
    private bool isSearching;

    /// <summary>Search failure text.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ProfileHint))]
    private string? profileError;

    /// <summary>Centered hint under the search box.</summary>
    public string ProfileHint =>
        ProfileError ?? (IsSearching ? "Searching…" :
            ProfileQuery.Trim().Length < 2 ? "Enter at least 2 characters to search." :
            ProfileResults.Count == 0 ? "No players found." : "");

    /// <summary>Selects a search result.</summary>
    /// <param name="result">Chosen account.</param>
    [RelayCommand]
    private void SelectProfile(PlayerSearchResult? result)
    {
        if (result is null) return;
        session.SelectPlayer(result);
        ProfileQuery = "";
        ProfileResults = [];
    }

    /// <summary>Deselects the current player.</summary>
    [RelayCommand]
    private void DeselectProfile() => session.DeselectPlayer();

    /// <summary>Debounces profile search.</summary>
    /// <param name="value">Query.</param>
    partial void OnProfileQueryChanged(string value)
    {
        search?.Cancel();
        search = new CancellationTokenSource();
        ProfileError = null;
        OnPropertyChanged(nameof(ProfileHint));
        _ = SearchAsync(value.Trim(), search.Token);
    }

    /// <summary>Runs one debounced account search.</summary>
    /// <param name="query">Trimmed query.</param>
    /// <param name="token">Cancelled by newer input.</param>
    /// <returns>Search task.</returns>
    private async Task SearchAsync(string query, CancellationToken token)
    {
        if (query.Length < 2)
        {
            ProfileResults = [];
            IsSearching = false;
            return;
        }
        try
        {
            await Task.Delay(SearchDebounce, session.Time, token);
            IsSearching = true;
            var response = await session.Api.SearchPlayersAsync(query, 10, token);
            token.ThrowIfCancellationRequested();
            ProfileResults = response.Results;
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
            Sections.Clear();
            foreach (var section in wanted) Sections.Add(section);
        }
        OnPropertyChanged(nameof(HasPlayer));
        OnPropertyChanged(nameof(ProfileName));
        OnPropertyChanged(nameof(ProfileInitials));
        OnPropertyChanged(nameof(ProfileButtonName));
    }
}
#endregion
