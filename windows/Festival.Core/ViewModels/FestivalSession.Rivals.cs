namespace Festival.Core.ViewModels;

#region Session: rivals
/// <summary>
/// Rivals reads for the selected player through a shared <see cref="RivalsReadCache"/>. Rivals are not part of the
/// catalogue/score publication contract, so these reads never pause Songs and vice versa.
/// </summary>
public sealed partial class FestivalSession
{
    /// <summary>Concurrent Rivals requests allowed (the hub starts up to eleven sections at once).</summary>
    public const int RivalsConcurrency = 4;

    private readonly SemaphoreSlim rivalsThrottle = new(RivalsConcurrency);
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
        return RivalsCache.GetAsync($"list|{account}|{scope}", () => Throttled(() => Api.GetRivalsListAsync(account, scope)), cancellationToken);
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
            () => Throttled(() => Api.GetLeaderboardRivalsAsync(account, instrument, rankBy)), cancellationToken);
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
    /// <param name="allowLiveFallback">Chart/combo reads may be computed live (routes opened from Find Rival); leaderboard
    /// detail never is.</param>
    /// <param name="cancellationToken">Cancels this caller's wait.</param>
    /// <returns>Compared songs.</returns>
    /// <exception cref="FestivalApiException">No player, or every underlying read failed.</exception>
    public Task<RivalDetailResponse> GetRivalDetailAsync(
        RivalScope? scope, string rivalId, bool allowLiveFallback = false, CancellationToken cancellationToken = default)
    {
        var account = RequireAccount();
        return scope?.Resolve(Settings.VisibleInstruments) switch
        {
            RivalScope.Leaderboard l => RivalsCache.GetAsync($"lbd|{account}|{l.Instrument.ServiceId()}|{rivalId}|{l.RankBy.ServiceId()}",
                () => Throttled(() => Api.GetLeaderboardRivalDetailAsync(account, l.Instrument, rivalId, l.RankBy)), cancellationToken),
            RivalScope.Combo c => ComboDetailAsync(account, c.Token, rivalId, allowLiveFallback, cancellationToken),
            RivalScope.Song s => MergedDetailAsync(account, s.Instruments, rivalId, allowLiveFallback, cancellationToken),
            _ => MergedDetailAsync(account, Settings.VisibleInstruments, rivalId, allowLiveFallback, cancellationToken),
        };
    }

    /// <summary>One combo read, rebuilt from <c>rivals/all</c> when the service holds it during a freeze.</summary>
    /// <param name="account">Selected player.</param>
    /// <param name="token">Combo token.</param>
    /// <param name="rivalId">Rival.</param>
    /// <param name="allowLiveFallback">Whether the service may compute the detail live.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Detail.</returns>
    private async Task<RivalDetailResponse> ComboDetailAsync(
        string account, string token, string rivalId, bool allowLiveFallback, CancellationToken cancellationToken)
    {
        try
        {
            return await Detail(account, token, rivalId, allowLiveFallback, cancellationToken);
        }
        catch (FestivalApiException error) when (RivalsReadCache.IsFrozen(error) && token != RivalCombo.ProDrumsToken &&
                                                 RivalCombo.InstrumentsFor(token) is { } instruments)
        {
            if (await AllRivalsDetailAsync(account, rivalId, instruments, token, cancellationToken) is { } rebuilt) return rebuilt;
            throw;
        }
    }

    /// <summary>
    /// Freeze fallback (issue #95): while publishing, the service answers 503 for any rival detail it has not cached,
    /// but <c>rivals/all</c> is precomputed and stays readable, and carries the same stored samples.
    /// </summary>
    /// <param name="account">Selected player.</param>
    /// <param name="rivalId">Rival.</param>
    /// <param name="instruments">Charts to rebuild.</param>
    /// <param name="combo">Scope echo.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Rebuilt detail, or <see langword="null"/> when unavailable (the caller keeps the original failure).</returns>
    private async Task<RivalDetailResponse?> AllRivalsDetailAsync(
        string account, string rivalId, IReadOnlyCollection<Instrument> instruments, string combo, CancellationToken cancellationToken)
    {
        try
        {
            var all = await RivalsCache.GetAsync($"all|{account}", () => Throttled(() => Api.GetRivalsAllAsync(account)), cancellationToken);
            return all.DetailFor(rivalId, instruments, combo) is { } detail ? await WithCatalogTitlesAsync(detail, cancellationToken) : null;
        }
        catch (FestivalApiException)
        {
            return null;
        }
    }

    /// <summary>Adds catalogue titles/artists to rebuilt rows (samples carry none) so Title sort and labels match.</summary>
    /// <param name="detail">Rebuilt detail.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Detail with titles where the catalogue knows the song; unchanged when the catalogue is unavailable.</returns>
    private async Task<RivalDetailResponse> WithCatalogTitlesAsync(RivalDetailResponse detail, CancellationToken cancellationToken)
    {
        SongsResponse catalog;
        try
        {
            catalog = await LoadCatalogAsync(cancellationToken: cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return detail;
        }
        var songs = catalog.Songs.GroupBy(s => s.SongId, StringComparer.Ordinal).ToDictionary(g => g.Key, g => g.First(), StringComparer.Ordinal);
        return detail with
        {
            Songs = [.. detail.Songs.Select(s => songs.TryGetValue(s.SongId, out var song) ? s with { Title = song.Title, Artist = song.Artist } : s)],
        };
    }

    /// <summary>One cached detail read.</summary>
    /// <param name="account">Selected player.</param>
    /// <param name="scope">Chart or combo token.</param>
    /// <param name="rivalId">Rival.</param>
    /// <param name="allowLiveFallback">Whether the service may compute the detail live.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Detail.</returns>
    private Task<RivalDetailResponse> Detail(string account, string scope, string rivalId, bool allowLiveFallback, CancellationToken cancellationToken) =>
        RivalsCache.GetAsync($"detail|{account}|{scope}|{rivalId}" + (allowLiveFallback ? "|live" : ""),
            () => Throttled(() => Api.GetRivalDetailAsync(account, scope, rivalId, allowLiveFallback: allowLiveFallback)), cancellationToken);

    /// <summary>
    /// Merges per-chart details like the web's <c>fetchCombinedRivalDetail</c>; charts the service holds during a freeze
    /// are rebuilt from <c>rivals/all</c>.
    /// </summary>
    /// <param name="account">Selected player.</param>
    /// <param name="instruments">Charts.</param>
    /// <param name="rivalId">Rival.</param>
    /// <param name="allowLiveFallback">Whether the service may compute each chart live.</param>
    /// <param name="cancellationToken">Cancellation.</param>
    /// <returns>Union of songs.</returns>
    private async Task<RivalDetailResponse> MergedDetailAsync(
        string account, IReadOnlyList<Instrument> instruments, string rivalId, bool allowLiveFallback, CancellationToken cancellationToken)
    {
        var reads = instruments.Select(i => Detail(account, i.ServiceId(), rivalId, allowLiveFallback, cancellationToken)).ToList();
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
        var frozen = instruments.Where((_, index) => reads[index].Exception?.InnerException is FestivalApiException e && RivalsReadCache.IsFrozen(e)).ToList();
        var combo = string.Join(',', instruments.Select(i => i.ServiceId()));
        if (frozen.Count > 0 && await AllRivalsDetailAsync(account, rivalId, frozen, combo, cancellationToken) is { } rebuilt)
            loaded.Add(rebuilt);
        if (loaded.Count == 0) throw reads.First(r => r.IsFaulted).Exception!.InnerException!;
        if (instruments.Count == 1) return loaded[0];
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var songs = loaded.SelectMany(d => d.Songs).Where(s => seen.Add(s.Key)).ToList();
        var name = loaded.Select(d => d.Rival.DisplayName).FirstOrDefault(n => n is not null);
        return loaded[0] with
        {
            Rival = loaded[0].Rival with { DisplayName = name },
            Combo = combo,
            TotalSongs = songs.Count,
            Songs = songs,
        };
    }

    /// <summary>Runs a read under the Rivals concurrency limit (polite to the public rate limit).</summary>
    /// <typeparam name="T">Result.</typeparam>
    /// <param name="read">Read to start once a slot is free.</param>
    /// <returns>Result.</returns>
    private async Task<T> Throttled<T>(Func<Task<T>> read)
    {
        await rivalsThrottle.WaitAsync().ConfigureAwait(false);
        try
        {
            return await read().ConfigureAwait(false);
        }
        finally
        {
            rivalsThrottle.Release();
        }
    }

    /// <summary>The selected account, or a typed failure.</summary>
    /// <returns>Account ID.</returns>
    /// <exception cref="FestivalApiException">With <see cref="FestivalApiErrorKind.InvalidResource"/> when no player is selected.</exception>
    private string RequireAccount() =>
        SelectedPlayer?.AccountId ?? throw new FestivalApiException(FestivalApiErrorKind.InvalidResource);
}
#endregion
