using System.Globalization;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>
/// Operator batch 6.12: Filter Invalid Scores sends the Settings leeway to the leaderboard read, and the service then
/// drops scores above the CHOpt maximum. The fixture mirrors the live Winterfest Wish (Lead) shape measured read-only
/// on 2026-09-28 (max 81,996; 10,009 local entries unfiltered, 7 at +1.0% leeway; see
/// <c>tools/windows/tests/live_filter_invalid_scores.py</c>) with synthetic players.
/// </summary>
public class FilterInvalidScoresTests
{
    private const string SongId = "winterfest";
    private const int MaxScore = 81_996;

    /// <summary>Unfiltered page one: every row is above the maximum.</summary>
    private static string Unfiltered() => Board(25, 12_438, 10_009, i => 100_955 - i * 97, i => i);

    /// <summary>Filtered at +1.0%: only seven rows survive, ranked by their original Epic rank.</summary>
    private static string Filtered() => Board(7, 12_438, 7, i => 79_243 - i * 1_000, i => 55_941 + i * 1_000);

    private static string Board(int count, int total, int local, Func<int, int> score, Func<int, int> rank)
    {
        var entries = string.Join(",", Enumerable.Range(1, count).Select(i =>
            $$"""{"accountId":"p{{i}}","displayName":"Player {{i}}","score":{{score(i)}},"rank":{{rank(i)}},"accuracy":980000,"isFullCombo":false,"stars":6,"season":1}"""));
        return $$"""{"songId":"{{SongId}}","instrument":"Solo_Guitar","count":{{count}},"totalEntries":{{total}},"localEntries":{{local}},"entries":[{{entries}}]}""";
    }

    private static FakeService Service() => new()
    {
        SongsBody = Wire.Songs(Wire.SongJson(SongId, "Winterfest Wish", "Synthetic Artist").Replace(
            "\"Solo_Guitar\":1000", "\"Solo_Guitar\":" + MaxScore.ToString(CultureInfo.InvariantCulture), StringComparison.Ordinal)),
        Override = r => r.RequestUri!.AbsolutePath == $"/api/leaderboard/{SongId}/Solo_Guitar"
            ? Wire.Ok(r.RequestUri.Query.Contains("leeway=", StringComparison.Ordinal) ? Filtered() : Unfiltered(), ("X-FST-Publication-Id", "7"))
            : null,
    };

    [Fact]
    public async Task Toggle_ReloadsWithLeeway_AndDropsInvalidScores()
    {
        var service = Service();
        var session = service.Session();
        var vm = new SongLeaderboardViewModel(session, new AppRoute.SongLeaderboard(SongId, Instrument.Lead, 1));
        await vm.ActivateAsync();
        Assert.Equal(25, vm.Rows.Count);
        Assert.All(vm.Rows, r => Assert.True(r.Entry.Score > MaxScore * 1.01));
        Assert.DoesNotContain(service.Handler.Requests, r => r.Uri.Query.Contains("leeway", StringComparison.Ordinal));

        session.UpdateSettings(s => s with { FilterInvalidScores = true, Leeway = 1 });
        await Async.Until(() => vm.Rows.Count == 7);
        Assert.All(vm.Rows, r => Assert.True(r.Entry.Score <= MaxScore * 1.01));
        Assert.Contains(service.Handler.Requests, r => r.Uri.Query.Contains("leeway=1", StringComparison.Ordinal));
        Assert.Equal(1, vm.Pager.TotalPages);

        session.UpdateSettings(s => s with { FilterInvalidScores = false });
        await Async.Until(() => vm.Rows.Count == 25);
        vm.Deactivate();
    }

    [Fact]
    public async Task ChangedWhileAway_ReloadsOnReturn()
    {
        var service = Service();
        var session = service.Session();
        var vm = new SongLeaderboardViewModel(session, new AppRoute.SongLeaderboard(SongId, Instrument.Lead, 1));
        await vm.ActivateAsync();
        vm.Deactivate();
        var before = service.Handler.Requests.Count;

        session.UpdateSettings(s => s with { FilterInvalidScores = true, Leeway = 1.04 });
        Assert.Equal(before, service.Handler.Requests.Count);
        await vm.ActivateAsync();
        Assert.Equal(7, vm.Rows.Count);
        Assert.Contains(service.Handler.Requests, r => r.Uri.Query.Contains("leeway=1", StringComparison.Ordinal));

        // Same effective leeway (0.1 steps) and unrelated settings: no extra read.
        var count = service.Handler.Requests.Count;
        session.UpdateSettings(s => s with { Leeway = 1.01, HideShop = true });
        await Async.Settle();
        await vm.ActivateAsync();
        Assert.Equal(count, service.Handler.Requests.Count);
        vm.Deactivate();
    }
}
