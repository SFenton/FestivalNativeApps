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
        Assert.Equal(vm.Leaderboards.Select(c => "instrument-" + c.Instrument.ServiceId()), vm.QuickLinkSections.Skip(1).Select(s => s.Id));
        Assert.Equal(vm.Leaderboards[0].Instrument, vm.QuickLinkSections[1].Instrument);
    }

    [Fact]
    public async Task ShopOffer_AddsBadgeAndOfficialLink()
    {
        var (_, session, vm) = await Open("s3");
        Assert.True(vm.HasShopLink);
        Assert.True(vm.HasShopBadge);
        Assert.Equal(ShopHighlight.LeavingTomorrow, vm.ShopHighlight);
        Assert.Equal("Item Shop: Leaving Tomorrow", vm.ShopBadgeText);
        Assert.False(vm.HasShopIssue);
        Assert.Equal(["Duos", "Trios", "Quads"], vm.BandLinks.Select(l => l.Label));
        Assert.Equal(new AppRoute.SongBandLeaderboard("s3", "Band_Duets"), vm.BandLinks[0].Route);
        session.UpdateSettings(s => s with { DisableShopHighlighting = true });
        await vm.LoadShopAsync();
        Assert.False(vm.HasShopBadge);
        Assert.Equal("", vm.ShopBadgeText);
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
    public async Task SelectedPlayer_SummarizesScoresAndLinksHistory()
    {
        var (service, _, vm) = await Open("s1", player: true);
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        Assert.True(lead.HasPlayer);
        Assert.True(lead.HasPlayerSummary);
        Assert.Equal("Your score: 1,000 · 99% · FC · Top 1% · #1", lead.PlayerSummary);
        Assert.Equal(new AppRoute.PlayerHistory("s1", Instrument.Lead), lead.HistoryRoute);
        Assert.Equal("View Lead Score History", lead.HistoryLabel);
        var bass = vm.Leaderboards.Single(b => b.Instrument == Instrument.Bass);
        Assert.Equal("Your score: 800 · 0%", bass.PlayerSummary);
        var vocals = vm.Leaderboards.Single(b => b.Instrument == Instrument.Vocals);
        Assert.Equal("Your score: no score yet", vocals.PlayerSummary);
        await lead.EnsureLoadedAsync();
        Assert.DoesNotContain(lead.Rows, r => r.IsSelectedPlayer);
        Assert.DoesNotContain(service.Handler.Requests, r => r.Uri.Query.Contains("leeway", StringComparison.Ordinal));
    }

    [Fact]
    public async Task NoPlayer_NoSummary_AndLeewayWhenFilteringInvalidScores()
    {
        var (service, _, vm) = await Open("s1", new AppSettings { FilterInvalidScores = true, Leeway = 1.5 });
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        Assert.False(lead.HasPlayer);
        Assert.False(lead.HasPlayerSummary);
        await lead.EnsureLoadedAsync();
        Assert.Contains(service.Handler.Requests, r => r.Uri.Query.Contains("leeway=1.5", StringComparison.Ordinal));
    }

    [Fact]
    public async Task SelectedPlayerRow_IsHighlighted()
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true);
        var inner = service.Override!;
        service.Override = r => r.RequestUri!.AbsolutePath.StartsWith("/api/leaderboard/", StringComparison.Ordinal)
            ? Wire.Ok(Wire.Leaderboard("s1", "Solo_Guitar", 1).Replace("\"a1\"", $"\"{PlayerWire.Id}\""), ("X-FST-Publication-Id", "7"))
            : inner(r);
        var session = service.Session(settings: new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") });
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        await lead.EnsureLoadedAsync();
        var row = Assert.Single(lead.Rows);
        Assert.True(row.IsSelectedPlayer);
        Assert.EndsWith(", you", row.Announcement);
    }

    [Fact]
    public async Task Summary_UpdatesWhenScoresArriveAfterLoad()
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
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        var lead = vm.Leaderboards.Single(b => b.Instrument == Instrument.Lead);
        Assert.Equal("Loading scores", lead.PlayerSummary);
        release.SetResult();
        await profile;
        await Async.Until(() => lead.PlayerSummary?.StartsWith("Your score: 1,000", StringComparison.Ordinal) == true);
        vm.Detach();
        session.DeselectPlayer();
        Assert.StartsWith("Your score", lead.PlayerSummary);
    }

    [Fact]
    public async Task SyncingPlayer_ShowsStateInSummary()
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true, profiles: new() { [PlayerWire.Id] = (HttpStatusCode.Accepted, PlayerWire.Syncing()) });
        var session = service.Session(settings: new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") });
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        Assert.Equal("Scores syncing", vm.Leaderboards[0].PlayerSummary);
    }
}
