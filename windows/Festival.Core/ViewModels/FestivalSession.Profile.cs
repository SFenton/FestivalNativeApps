using CommunityToolkit.Mvvm.ComponentModel;

namespace Festival.Core.ViewModels;

#region Selected profile status
/// <summary>Lifecycle of the selected player's process-only scores.</summary>
public enum SelectedProfileStatus
{
    /// <summary>No player selected, or not loaded yet.</summary>
    None,
    /// <summary>Read in flight (earlier scores already cleared).</summary>
    Loading,
    /// <summary>Scores available for <see cref="FestivalSession.SelectedProfile"/>'s publication.</summary>
    Available,
    /// <summary>HTTP 202: registered, not yet published. Never an empty success.</summary>
    Syncing,
    /// <summary>The read failed; see <see cref="FestivalSession.SelectedProfileIssue"/>.</summary>
    Failed,
}
#endregion

#region Session: player profiles
/// <summary>
/// Viewing and selecting players. Only a validated ID and display name persist; scores are process-only,
/// cleared on switch, deselect, retry and failure, and never shown for another account or a stale generation.
/// </summary>
public sealed partial class FestivalSession
{
    private CancellationTokenSource? selectedProfileLoad;

    /// <summary>Selected player's scores state.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SelectedScoreIndex))]
    private SelectedProfileStatus selectedProfileStatus;

    /// <summary>Selected player's validated read, only while <see cref="SelectedProfileStatus"/> is Available or Syncing.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SelectedScoreIndex))]
    private PlayerProfilePayload? selectedProfile;

    /// <summary>Why the selected player's read failed.</summary>
    [ObservableProperty]
    private ServiceIssue? selectedProfileIssue;

    /// <summary>Song ID → chart → score for the selected player, only when available (build once per read).</summary>
    public IReadOnlyDictionary<string, IReadOnlyDictionary<Instrument, PlayerScore>>? SelectedScoreIndex { get; private set; }

    /// <summary>Publication the selected player's scores were observed under.</summary>
    public long? SelectedProfilePublicationId => SelectedProfile?.ObservedPublicationId;

    /// <summary>Whether the selected scores belong to the client's current publication (compare before projecting onto rows).</summary>
    public bool IsSelectedProfileCurrent =>
        SelectedProfileStatus == SelectedProfileStatus.Available && SelectedProfilePublicationId == Api.CurrentPublication?.PublicationId;

    /// <summary>Reads any player's public profile without selecting or persisting it.</summary>
    /// <param name="accountId">Account to view.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Validated read.</returns>
    public Task<PlayerProfilePayload> ViewPlayerAsync(string accountId, CancellationToken cancellationToken = default) =>
        Api.GetPlayerProfileAsync(accountId, cancellationToken);

    /// <summary>Promotes a viewed, header-verified current read to the selected player (select or switch).</summary>
    /// <param name="payload">Read backing the action.</param>
    /// <param name="displayName">Name to persist (server name, else the route/search name).</param>
    /// <returns><see langword="true"/> when selected; <see langword="false"/> for an unverified, stale or invalid read.</returns>
    public bool SelectPlayer(PlayerProfilePayload payload, string displayName)
    {
        if (!payload.IsSelectable(Api.CurrentPublication?.PublicationId)) return false;
        var player = new SelectedPlayer(payload.Profile.AccountId, displayName.Trim());
        if (!player.IsValid) return false;
        UpdateSettings(s => s with { SelectedPlayer = player });
        ApplySelectedProfile(payload);
        return true;
    }

    /// <summary>Loads (or reuses) the selected player's scores for the current publication. Safe to call repeatedly.</summary>
    /// <param name="force">Clear and re-read (Retry).</param>
    /// <param name="cancellationToken">Cancels this caller's read.</param>
    /// <returns>Load task.</returns>
    public async Task LoadSelectedProfileAsync(bool force = false, CancellationToken cancellationToken = default)
    {
        if (SelectedPlayer is not { } player)
        {
            ClearSelectedProfile(SelectedProfileStatus.None);
            return;
        }
        if (!force && SelectedProfileStatus == SelectedProfileStatus.Loading) return;
        if (!force && SelectedProfileStatus is SelectedProfileStatus.Available or SelectedProfileStatus.Syncing &&
            SelectedProfile is { } loaded && Matches(loaded, player.AccountId))
        {
            var current = await Api.GetPublicationAsync(false, cancellationToken);
            if (loaded.ObservedPublicationId == current.PublicationId) return;
        }

        selectedProfileLoad?.Cancel();
        var load = selectedProfileLoad = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        ClearSelectedProfile(SelectedProfileStatus.Loading);
        try
        {
            var payload = await Api.GetPlayerProfileAsync(player.AccountId, load.Token);
            if (load.IsCancellationRequested || SelectedPlayer?.AccountId != player.AccountId) return;
            ApplySelectedProfile(payload);
        }
        catch (OperationCanceledException)
        {
            // Superseded by a newer load, switch or deselect; a caller-cancelled current load must not stay Loading.
            if (ReferenceEquals(selectedProfileLoad, load) && SelectedProfileStatus == SelectedProfileStatus.Loading)
                ClearSelectedProfile(SelectedProfileStatus.None);
        }
        catch (FestivalApiException error)
        {
            if (load.IsCancellationRequested || SelectedPlayer?.AccountId != player.AccountId) return;
            ClearSelectedProfile(SelectedProfileStatus.Failed);
            SelectedProfileIssue = ServiceIssue.From(error);
        }
    }

    /// <summary>Clears scores for another account when the selected identity changes (switch or deselect).</summary>
    /// <param name="oldValue">Previous settings.</param>
    /// <param name="newValue">New settings.</param>
    partial void OnSettingsChanged(AppSettings? oldValue, AppSettings newValue)
    {
        if (oldValue?.SelectedPlayer?.AccountId == newValue.SelectedPlayer?.AccountId) return;
        selectedProfileLoad?.Cancel();
        if (SelectedProfile is { } held && newValue.SelectedPlayer is { } next && Matches(held, next.AccountId)) return;
        ClearSelectedProfile(SelectedProfileStatus.None);
    }

    /// <summary>Stores a validated read for the selected player.</summary>
    /// <param name="payload">Read.</param>
    private void ApplySelectedProfile(PlayerProfilePayload payload)
    {
        selectedProfileLoad?.Cancel();
        SelectedProfileIssue = null;
        SelectedScoreIndex = payload.State == PlayerProfileState.Available ? payload.Profile.ScoreIndex() : null;
        SelectedProfile = payload;
        SelectedProfileStatus = payload.State == PlayerProfileState.Available ? SelectedProfileStatus.Available : SelectedProfileStatus.Syncing;
    }

    /// <summary>Drops scores and the issue.</summary>
    /// <param name="status">Resulting status.</param>
    private void ClearSelectedProfile(SelectedProfileStatus status)
    {
        SelectedProfileIssue = null;
        SelectedScoreIndex = null;
        SelectedProfile = null;
        SelectedProfileStatus = status;
    }

    /// <summary>Whether a read belongs to an account.</summary>
    /// <param name="payload">Read.</param>
    /// <param name="accountId">Account.</param>
    /// <returns><see langword="true"/> on a case-insensitive match.</returns>
    private static bool Matches(PlayerProfilePayload payload, string accountId) =>
        string.Equals(payload.Profile.AccountId, accountId, StringComparison.OrdinalIgnoreCase);
}
#endregion
