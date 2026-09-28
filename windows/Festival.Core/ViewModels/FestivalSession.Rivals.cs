namespace Festival.Core.ViewModels;

#region Session: rivals
/// <summary>
/// Rivals reads for the selected player through a shared <see cref="RivalsReadCache"/>. Rivals are not part of the
/// catalogue/score publication contract, so these reads never pause Songs and vice versa.
/// </summary>
public sealed partial class FestivalSession
{
    private RivalsReadCache? rivalsCache;

    /// <summary>Shared, bounded Rivals read cache.</summary>
    public RivalsReadCache RivalsCache => rivalsCache ??= new RivalsReadCache(Time);

    /// <summary>The leaderboard-rivals metric actually used: the web only honours non-default metrics with experimental ranks.</summary>
    /// <param name="requested">Metric chosen in the picker.</param>
    /// <returns>Requested metric, or Total Score when experimental ranks are off.</returns>
    public RankingMetric EffectiveRivalMetric(RankingMetric requested) =>
        Settings.ExperimentalRanks ? requested : RankingMetricInfo.Default;

    /// <summary>Shared-song rivals for a chart or combo token.</summary>
    /// <param name="scope">Instrument service ID or combo token.</param>
    /// <param name="cancellationToken">Cancels this caller's wait.</param>
    /// <returns>Rivals above and below the selected player.</returns>
    /// <exception cref="FestivalApiException">No selected player (<see cref="FestivalApiErrorKind.InvalidResource"/>) or a failed read.</exception>
    public Task<RivalsListResponse> GetRivalsListAsync(string scope, CancellationToken cancellationToken = default)
    {
        var account = RequireAccount();
        return RivalsCache.GetAsync($"list|{account}|{scope}", () => Api.GetRivalsListAsync(account, scope), cancellationToken);
    }

    /// <summary>Global-leaderboard neighbours on one chart.</summary>
    /// <param name="instrument">Chart.</param>
    /// <param name="rankBy">Metric.</param>
    /// <param name="cancellationToken">Cancels this caller's wait.</param>
    /// <returns>Neighbours above and below.</returns>
    /// <exception cref="FestivalApiException">No selected player or a failed read.</exception>
    public Task<LeaderboardRivalsListResponse> GetLeaderboardRivalsAsync(Instrument instrument, RankingMetric rankBy, CancellationToken cancellationToken = default)
    {
        var account = RequireAccount();
        return RivalsCache.GetAsync($"lb|{account}|{instrument.ServiceId()}|{rankBy.ServiceId()}",
            () => Api.GetLeaderboardRivalsAsync(account, instrument, rankBy), cancellationToken);
    }

    /// <summary>Loads the lists behind Common Rivals and intersects them.</summary>
    /// <param name="instruments">Two or more charts.</param>
    /// <param name="cancellationToken">Cancels this caller's wait.</param>
    /// <returns>Common rivals above and below.</returns>
    /// <exception cref="FestivalApiException">When fewer than two lists loaded and at least one read failed.</exception>
    public async Task<(List<RivalSummary> Above, List<RivalSummary> Below)> GetCommonRivalsAsync(
        IReadOnlyList<Instrument> instruments, CancellationToken cancellationToken = default)
    {
        var reads = instruments.Select(i => GetRivalsListAsync(i.ServiceId(), cancellationToken)).ToList();
        try
        {
            await Task.WhenAll(reads);
        }
        catch (FestivalApiException)
        {
            // Inspected per read below.
        }
        cancellationToken.ThrowIfCancellationRequested();
        var loaded = reads.Where(r => r.IsCompletedSuccessfully).Select(r => r.Result).ToList();
        if (loaded.Count < 2 && reads.FirstOrDefault(r => r.IsFaulted) is { } failed)
            throw failed.Exception!.InnerException!;
        return RivalCommonRivals.Intersect(loaded);
    }

    /// <summary>
    /// Resolves a rival's shared songs for a typed scope: leaderboard and combo scopes read one endpoint; a song scope
    /// merges each chart's detail (de-duplicated); no scope merges every Settings-visible chart (deep link, Find Rival).
    /// </summary>
    /// <param name="scope">Route scope.</param>
    /// <param name="rivalId">Rival account.</param>
    /// <param name="cancellationToken">Cancels this caller's wait.</param>
    /// <returns>Compared songs.</returns>
    /// <exception cref="FestivalApiException">No player, or every underlying read failed.</exception>
    public Task<RivalDetailResponse> GetRivalDetailAsync(RivalScope? scope, string rivalId, CancellationToken cancellationToken = default)
    {
        var account = RequireAccount();
        return scope?.Resolve(Settings.VisibleInstruments) switch
        {
            RivalScope.Leaderboard l => RivalsCache.GetAsync($"lbd|{account}|{l.Instrument.ServiceId()}|{rivalId}|{l.RankBy.ServiceId()}",
                () => Api.GetLeaderboardRivalDetailAsync(account, l.Instrument, rivalId, l.RankBy), cancellationToken),
            RivalScope.Combo c => Detail(account, c.Token, rivalId, cancellationToken),
            RivalScope.Song s => MergedDetailAsync(account, s.Instruments, rivalId, cancellationToken),
            _ => MergedDetailAsync(account, Settings.VisibleInstruments, rivalId, cancellationToken),
        };
    }

    /// <summary>One cached detail read.</summary>
    /// <param name="account">Selected player.</param>
    /// <param name="scope">Chart or combo token.</param>
    /// <param name="rivalId">Rival.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Detail.</returns>
    private Task<RivalDetailResponse> Detail(string account, string scope, string rivalId, CancellationToken cancellationToken) =>
        RivalsCache.GetAsync($"detail|{account}|{scope}|{rivalId}", () => Api.GetRivalDetailAsync(account, scope, rivalId), cancellationToken);

    /// <summary>Merges per-chart details like the web's <c>fetchCombinedRivalDetail</c>.</summary>
    /// <param name="account">Selected player.</param>
    /// <param name="instruments">Charts.</param>
    /// <param name="rivalId">Rival.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Union of songs.</returns>
    private async Task<RivalDetailResponse> MergedDetailAsync(string account, IReadOnlyList<Instrument> instruments, string rivalId, CancellationToken cancellationToken)
    {
        if (instruments.Count == 1) return await Detail(account, instruments[0].ServiceId(), rivalId, cancellationToken);
        var reads = instruments.Select(i => Detail(account, i.ServiceId(), rivalId, cancellationToken)).ToList();
        try
        {
            await Task.WhenAll(reads);
        }
        catch (FestivalApiException)
        {
            // Inspected per read below.
        }
        cancellationToken.ThrowIfCancellationRequested();
        var loaded = reads.Where(r => r.IsCompletedSuccessfully).Select(r => r.Result).ToList();
        if (loaded.Count == 0) throw reads.First(r => r.IsFaulted).Exception!.InnerException!;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var songs = loaded.SelectMany(d => d.Songs).Where(s => seen.Add(s.Key)).ToList();
        var name = loaded.Select(d => d.Rival.DisplayName).FirstOrDefault(n => n is not null);
        return loaded[0] with
        {
            Rival = loaded[0].Rival with { DisplayName = name },
            Combo = string.Join(',', instruments.Select(i => i.ServiceId())),
            TotalSongs = songs.Count,
            Songs = songs,
        };
    }

    /// <summary>The selected account, or a typed failure.</summary>
    /// <returns>Account ID.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/> when no player is selected.</exception>
    private string RequireAccount() =>
        SelectedPlayer?.AccountId ?? throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
}
#endregion
