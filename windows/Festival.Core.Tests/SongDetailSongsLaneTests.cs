using System.Net;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

public class SongDetailSongsLaneTests
{
    private static async Task<(FakeService Service, FestivalSession Session, SongDetailViewModel Vm)> Open(string songId, AppSettings? settings = null,
        bool player = false, HttpStatusCode shop = HttpStatusCode.OK)
    {
        var service = new FakeService();
        SongsWire.Install(service, shopStatus: shop, player: true);
        var initial = settings ?? new AppSettings();
        if (player) initial = initial with { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") };
        var session = service.Session(settings: initial);
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail(songId));
        await vm.LoadAsync();
        return (service, session, vm);
    }

    [Fact]
    public async Task QuickLinks_IntensityThenOneSectionPerLeaderboardCard()
    {
        var (_, _, vm) = await Open("s3");
        Assert.NotEmpty(vm.Leaderboards);
        Assert.Equal("intensity", vm.QuickLinkSections[0].Id);
        Assert.Equal(vm.Leaderboards.Select(c => "instrument-" + c.Instrument.ServiceId()), vm.QuickLinkSections.Skip(1).Take(vm.Leaderboards.Count).Select(s => s.Id));
        Assert.Equal(vm.Leaderboards[0].Instrument, vm.QuickLinkSections[1].Instrument);
        Assert.Equal(vm.BandPreviews.Select(b => b.QuickLinkId), vm.QuickLinkSections.Skip(1 + vm.Leaderboards.Count).Select(s => s.Id));
    }

    [Fact]
    public async Task ShopOffer_PulsesTheOfficialLinkInItsStatus()
    {
        var (_, session, vm) = await Open("s3");
        Assert.True(vm.HasShopLink);
        Assert.True(vm.ShopPulses);
        Assert.Equal(ShopHighlight.LeavingTomorrow, vm.ShopHighlight);
        Assert.Equal("Open in Item Shop, Leaving Tomorrow", vm.ShopButtonName);
        Assert.False(vm.HasShopIssue);
        Assert.Equal(["Duos", "Trios", "Quads"], vm.BandPreviews.Select(b => b.Title));
        Assert.Equal(new AppRoute.SongBandLeaderboard("s3", "Band_Duets"), vm.BandPreviews[0].FullRoute);
        session.UpdateSettings(s => s with { DisableShopHighlighting = true });
        await vm.LoadShopAsync();
        Assert.False(vm.ShopPulses);
        Assert.Equal("Open in Item Shop", vm.ShopButtonName);
        Assert.True(vm.HasShopLink);
        session.UpdateSettings(s => s with { HideShop = true });
        await vm.LoadShopAsync();
        Assert.False(vm.HasShopLink);
        Assert.Null(vm.ShopOffer);
    }

    [Fact]
    public async Task ShopFailure_IsExplicit()
    {
        var (_, _, vm) = await Open("s1", shop: HttpStatusCode.InternalServerError);
        Assert.True(vm.HasShopIssue);
        Assert.StartsWith("Item Shop status unavailable", vm.ShopIssueText);
        Assert.False(vm.HasShopLink);
    }

    [Fact]
    public async Task Paths_UseVisibleChartedPathInstruments()
    {
        var (_, session, vm) = await Open("s3");
        Assert.Equal([Instrument.Lead], vm.PathInstruments); // Karaoke is charted but has no paths
        Assert.True(vm.HasPaths);
        var paths = vm.CreatePaths();
        Assert.NotNull(paths);
        Assert.Equal([Instrument.Lead], paths!.Instruments);
        session.UpdateSettings(s => s with { VisibleInstruments = [Instrument.Karaoke] });
        var (_, _, karaokeOnly) = await Open("s3", new AppSettings { VisibleInstruments = [Instrument.Karaoke] });
        Assert.False(karaokeOnly.HasPaths);
        Assert.Null(karaokeOnly.CreatePaths());
    }

    [Fact]
    public async Task SelectedPlayer_CardsCarryNoScoreText()
    {
        var (service, _, vm) = await Open("s1", player: true);
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        Assert.True(lead.HasPlayer);
        Assert.True(lead.ShowRows);
        Assert.DoesNotContain(lead.Rows, r => r.IsSelectedPlayer);
        Assert.DoesNotContain(service.Handler.Requests, r => r.Uri.Query.Contains("leeway", StringComparison.Ordinal));
    }

    [Fact]
    public async Task NoPlayer_LeewayWhenFilteringInvalidScores()
    {
        var (service, _, vm) = await Open("s1", new AppSettings { FilterInvalidScores = true, Leeway = 1.5 });
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        Assert.False(lead.HasPlayer);
        Assert.Contains(service.Handler.To("/api/leaderboard/s1/all"), r => r.Uri.Query.Contains("leeway=1.5", StringComparison.Ordinal));
        await lead.LoadAsync();
        Assert.Contains(service.Handler.To("/api/leaderboard/s1/Solo_Guitar"), r => r.Uri.Query.Contains("leeway=1.5", StringComparison.Ordinal));
    }

    [Fact]
    public async Task SelectedPlayerRow_IsHighlighted()
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true);
        var inner = service.Override!;
        service.Override = r => r.RequestUri!.AbsolutePath.StartsWith("/api/leaderboard/", StringComparison.Ordinal) && !r.RequestUri.AbsolutePath.EndsWith("/all", StringComparison.Ordinal)
            ? Wire.Ok(Wire.Leaderboard("s1", "Solo_Guitar", 1).Replace("\"a1\"", $"\"{PlayerWire.Id}\""), ("X-FST-Publication-Id", "7"))
            : inner(r);
        var session = service.Session(settings: new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") });
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        await lead.LoadAsync();
        var row = Assert.Single(lead.Rows);
        Assert.True(row.IsSelectedPlayer);
        Assert.EndsWith(", you", row.Announcement);
    }

    [Fact]
    public async Task PlayerOutsideTopTen_IsRowElevenAndReplacesTheSummary()
    {
        var (_, _, vm) = await Open("s2", player: true);
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        Assert.Equal(11, lead.Rows.Count);
        var mine = lead.Rows[10];
        Assert.True(mine.IsSelectedPlayer);
        Assert.Equal("#30", mine.Rank);
        Assert.Equal(new AppRoute.SongLeaderboard("s2", Instrument.Lead, 2), mine.Route); // the player's page of the full board
        Assert.Equal(new AppRoute.Player("a1", "Player 1"), lead.Rows[0].Route);
        Assert.Equal("Fixture One", mine.Name);
        // One leaderboard row design (operator batch 7.7): the card shares one rank and score width with row eleven.
        Assert.True(mine.IsSelected);
        Assert.Equal("#30", mine.RankText);
        Assert.All(lead.Rows, r => Assert.Equal(3, r.Section!.RankChars));
        Assert.All(lead.Rows, r => Assert.Equal(lead.Rows.Max(x => x.Score.Length), r.Section!.ValueChars));
        Assert.All(lead.Rows, r => Assert.Same(lead.Rows[0].Section, r.Section));
        Assert.Equal("fst.song-detail.preview-row.Solo_Guitar.a1", lead.Rows[0].AutomationId);
        Assert.Equal(0, mine.StarCount);
        Assert.False(lead.ShowPlaceholder);
        Assert.True(lead.HasPlayerRow);
        Assert.Equal("fst.song-detail.view-all.Solo_Guitar", lead.ViewAllAutomationId);
        Assert.Equal("View Full Leaderboard, Lead", lead.ViewAllName);
        lead.UpdatePlayer(null);
        Assert.Equal(10, lead.Rows.Count);
        Assert.False(lead.HasPlayerRow);
    }

    [Fact]
    public async Task TotalEntries_SubtitleOnlyWhenTheServiceAllowsTotals()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var inner = service.Override!;
        var allow = true;
        service.Override = r => r.RequestUri!.AbsolutePath.StartsWith("/api/leaderboard/", StringComparison.Ordinal) && !r.RequestUri.AbsolutePath.EndsWith("/all", StringComparison.Ordinal)
            ? Wire.Ok(Wire.Leaderboard("s1", "Solo_Guitar", 2, total: 12345)
                .Replace("{\"songId\"", $"{{\"showLeaderboardEntryTotals\":{(allow ? "true" : "false")},\"songId\""), ("X-FST-Publication-Id", "7"))
            : inner(r);
        var session = service.Session();
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        Assert.Equal("Lead", lead.HeaderName);
        await lead.LoadAsync();
        Assert.Equal(12345.ToString("N0", System.Globalization.CultureInfo.CurrentCulture) + " total entries", lead.TotalEntriesText);
        Assert.True(lead.HasTotalEntries);
        Assert.Equal("Lead, " + lead.TotalEntriesText, lead.HeaderName);
        allow = false;
        await lead.LoadAsync();
        Assert.False(lead.HasTotalEntries);
    }

    [Fact]
    public async Task EmptyChart_SaysNoScoresRecordedAndHidesViewAll()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var inner = service.Override!;
        service.Override = r => r.RequestUri!.AbsolutePath.StartsWith("/api/leaderboard/", StringComparison.Ordinal) && !r.RequestUri.AbsolutePath.EndsWith("/all", StringComparison.Ordinal)
            ? Wire.Ok(Wire.Leaderboard("s1", "Solo_Guitar", 0, total: 0), ("X-FST-Publication-Id", "7"))
            : inner(r);
        var vm = new SongDetailViewModel(service.Session(), new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        await lead.LoadAsync();
        Assert.True(lead.ShowEmpty);
        Assert.False(lead.ShowRows); // View Full Leaderboard is bound to ShowRows
        Assert.Equal(LeaderboardPreviewViewModel.NoScoresText, lead.TotalEntriesText);
        Assert.Equal("Lead, No scores recorded yet", lead.HeaderName);
        Assert.StartsWith("When scores are submitted for Lead", lead.EmptyText, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RowEleven_FollowsScoresThatArriveAfterLoad()
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true);
        var original = service.Handler.Responder;
        var release = new TaskCompletionSource();
        service.Handler.Responder = async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.StartsWith("/api/player/", StringComparison.Ordinal)) await release.Task;
            return await original(request, token);
        };
        var session = service.Session(settings: new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") });
        var profile = session.LoadSelectedProfileAsync();
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s2"));
        var load = vm.LoadAsync();
        release.SetResult();
        await profile;
        await load;
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        await Async.Until(() => lead.Rows.Count == 11);
        vm.Detach();
        session.DeselectPlayer();
        Assert.Equal(11, lead.Rows.Count);
    }
}
