using System.Net;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>
/// Issue #554: a 503 during the scrape → publish lifecycle keeps showing the publication's already-verified data
/// (band best/worst songs, rank history, band row, player rankings), while cold reads, outages and other freeze
/// reasons still fail as before.
/// </summary>
public class ScrapeFreezeReadTests
{
    private static HttpResponseMessage Frozen(string reason = "publication-commit") =>
        Wire.Response(HttpStatusCode.ServiceUnavailable, """{"title":"Published data unavailable"}""",
            ("Retry-After", "30"), (ServiceFreezeReason.Header, reason));

    private static bool IsBandRead(string path) => path.StartsWith("/api/rankings/bands/", StringComparison.Ordinal);

    private static async Task<FestivalApiException> Fails(Func<Task> action) =>
        await Assert.ThrowsAsync<FestivalApiException>(action);

    [Theory]
    [InlineData("scrape")]
    [InlineData("post-process")]
    [InlineData("publish")]
    [InlineData("publication-commit")]
    [InlineData("Publication-Commit-Deferred")]
    public async Task ScoreUpdateFreeze_ServesSamePublicationBody(string reason)
    {
        var bands = new BandService();
        var client = bands.Service.Client();
        var before = await client.GetBandSongExtremesAsync(BandType.Duets, BandWire.Team);
        bands.Band = (p, _) => IsBandRead(p) ? Frozen(reason) : null;

        var during = await client.GetBandSongExtremesAsync(BandType.Duets, BandWire.Team);

        Assert.Equal(before.Best.Select(s => s.SongId), during.Best.Select(s => s.SongId));
        Assert.Equal(before.Worst.Select(s => s.SongId), during.Worst.Select(s => s.SongId));
        Assert.Equal(2, bands.Service.Handler.Requests.Count(r => r.Uri.AbsolutePath.EndsWith("/songs", StringComparison.Ordinal) && IsBandRead(r.Uri.AbsolutePath)));
    }

    [Fact]
    public async Task ScoreUpdateFreeze_WithoutVerifiedBodyStillFailsAsScoresUpdating()
    {
        var bands = new BandService();
        bands.Band = (p, _) => IsBandRead(p) ? Frozen("scrape") : null;

        var error = await Fails(() => bands.Service.Client().GetBandSongExtremesAsync(BandType.Duets, BandWire.Team));

        Assert.Equal(FestivalApiErrorKind.PublicReadFrozen, error.Kind);
        Assert.Equal(ServiceIssueKind.ScrapeInProgress, ServiceIssue.From(error).Kind);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("max-score-maintenance:v1:x")]
    [InlineData("publication-isolation-pending")]
    public async Task OutagesAndOtherFreezes_DoNotReuseTheBody(string? reason)
    {
        var bands = new BandService();
        var client = bands.Service.Client();
        await client.GetBandRankHistoryAsync(BandType.Duets, BandWire.Team);
        bands.Band = (p, _) => !IsBandRead(p) ? null
            : reason is null ? BandService.Unavailable() : Frozen(reason);

        var error = await Fails(() => client.GetBandRankHistoryAsync(BandType.Duets, BandWire.Team));

        Assert.Equal(ServiceIssueKind.Unavailable, ServiceIssue.From(error).Kind);
    }

    [Fact]
    public async Task ScoreUpdateFreeze_NeverServesABodyFromAnEarlierPublication()
    {
        var bands = new BandService();
        var client = bands.Service.Client();
        await client.GetBandProfileAsync(BandType.Duets, BandWire.Team);
        bands.Service.PublicationId = 8;
        await client.GetPublicationAsync(force: true);
        bands.Band = (p, _) => IsBandRead(p) ? Frozen() : null;

        var error = await Fails(() => client.GetBandProfileAsync(BandType.Duets, BandWire.Team));

        Assert.Equal(FestivalApiErrorKind.PublicReadFrozen, error.Kind);
    }

    [Fact]
    public async Task ScoreUpdateFreeze_StampedWithANewerPublicationDoesNotReuseTheBody()
    {
        var bands = new BandService();
        var client = bands.Service.Client();
        await client.GetBandProfileAsync(BandType.Duets, BandWire.Team);
        bands.Band = (p, _) =>
        {
            if (!IsBandRead(p))
                return null;
            var frozen = Frozen("publish");
            frozen.Headers.Add(FestivalApiClient.PublicationHeader, "8");
            return frozen;
        };

        await Fails(() => client.GetBandProfileAsync(BandType.Duets, BandWire.Team));
    }

    [Fact]
    public async Task ScoreUpdateFreeze_ServesPinnedBodyAfterConditionalRead()
    {
        var bands = new BandService();
        var inner = bands.Service.Override!;
        bands.Service.Override = r => r.RequestUri!.AbsolutePath == "/api/publication" ? Wire.Ok(Wire.Publication(7, pinning: true)) : inner(r);
        var client = bands.Service.Client();
        await client.GetBandSongExtremesAsync(BandType.Duets, BandWire.Team);
        bands.Band = (p, _) => IsBandRead(p) ? Frozen("publish") : null;

        var during = await client.GetBandSongExtremesAsync(BandType.Duets, BandWire.Team);

        Assert.Equal("fixture-pulse", during.Best.Single().SongId);
        var last = bands.Service.Handler.Requests.Last(r => IsBandRead(r.Uri.AbsolutePath));
        Assert.Equal("7", last.Headers[FestivalApiClient.PublicationHeader]);
        Assert.DoesNotContain(last.Headers.Keys, k => k.StartsWith("x-fst-selected-", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task BandPage_RevisitDuringScrapeKeepsEverySection()
    {
        var bands = new BandService();
        var session = bands.Service.Session();
        var first = new BandDetailViewModel(session, new AppRoute.Band("fixture-band-1", "Band_Duets", BandWire.Team));
        await first.LoadAsync();
        Assert.True(first.ShowSongs);
        bands.Band = (p, _) => IsBandRead(p) ? Frozen() : null;

        var revisit = new BandDetailViewModel(session, new AppRoute.Band("fixture-band-1", "Band_Duets", BandWire.Team));
        await revisit.LoadAsync();

        Assert.True(revisit.ShowContent);
        Assert.True(revisit.ShowHistory);
        Assert.True(revisit.ShowSongs);
        Assert.False(revisit.SongsFailed);
        Assert.Equal(first.Best.Select(r => r.Title), revisit.Best.Select(r => r.Title));
        Assert.Equal(first.Worst.Select(r => r.Title), revisit.Worst.Select(r => r.Title));
        Assert.False(revisit.SongsStatus.HasIssue);
    }

    [Fact]
    public async Task BandPage_ColdReadDuringScrapeShowsScoresUpdatingNotEmpty()
    {
        var bands = new BandService();
        var vm = new BandDetailViewModel(bands.Service.Session(), new AppRoute.Band("fixture-band-1", "Band_Duets", BandWire.Team));
        await vm.LoadAsync();
        bands.Band = (p, _) => p.EndsWith("/songs", StringComparison.Ordinal) && IsBandRead(p) ? Frozen("scrape") : null;
        var cold = new BandDetailViewModel(bands.Service.Session(), new AppRoute.Band("fixture-band-1", "Band_Duets", BandWire.Team));

        await cold.LoadAsync();

        Assert.True(cold.ShowContent);
        Assert.True(cold.SongsFailed);
        Assert.False(cold.ShowSongs);
        Assert.Equal("Scores are updating", cold.SongsStatus.Title);
    }
}
