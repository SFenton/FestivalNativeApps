using System.Net;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>Song Detail band previews: the <c>/bands/all</c> read, its validation and each size's section.</summary>
public class SongBandPreviewTests
{
    private const string Pub = "X-FST-Publication-Id";

    /// <summary>A band row as the service's <c>SongBandLeaderboardEntry</c>.</summary>
    private static string Entry(string type, int rank, string bandId = "", string? team = null) =>
        $$"""{"bandId":"{{bandId}}","bandType":"{{type}}","teamKey":"{{team ?? $"r{rank}a:r{rank}b"}}","members":[{"accountId":"r{{rank}}a","displayName":"Lead {{rank}}","instruments":["Solo_Guitar"]},{"accountId":"r{{rank}}b","displayName":"Bass {{rank}}","instruments":["Solo_Bass"]}],"score":{{100000 - rank}},"rank":{{rank}},"accuracy":{{(rank == 1 ? "965000" : "null")}},"isFullCombo":{{(rank == 1 ? "true" : "false")}},"stars":{{(rank == 1 ? "5" : "null")}},"season":9}""";

    /// <summary>One size block; <paramref name="count"/> overrides the honest row count.</summary>
    private static string Band(string type, string[] entries, int total, string? player = null, string? band = null, int? count = null) =>
        $$"""{"bandType":"{{type}}","count":{{count ?? entries.Length}},"totalEntries":{{total}},"localEntries":{{total}},"entries":[{{string.Join(",", entries)}}]{{(player is null ? "" : ",\"selectedPlayerEntry\":" + player)}}{{(band is null ? "" : ",\"selectedBandEntry\":" + band)}}}""";

    private static string All(string songId, bool? totals, params string[] bands) =>
        $$"""{"songId":"{{songId}}",{{(totals is null ? "" : $"\"showLeaderboardEntryTotals\":{(totals.Value ? "true" : "false")},")}}"bands":[{{string.Join(",", bands)}}]}""";

    private static SongBandLeaderboardsResponse Decode(string json) =>
        FestivalApiClient.Decode(System.Text.Encoding.UTF8.GetBytes(json), BandsJsonContext.Default.SongBandLeaderboardsResponse);

    /// <summary>Opens Song Detail with <paramref name="bands"/> answering every <c>/bands/all</c> read.</summary>
    private static async Task<(FakeService Service, FestivalSession Session, SongDetailViewModel Vm)> Open(
        Func<HttpRequestMessage, HttpResponseMessage> bands, bool player = false, string songId = "s1")
    {
        var service = new FakeService();
        SongsWire.Install(service, player: true);
        var inner = service.Override!;
        service.Override = r => r.RequestUri!.AbsolutePath.EndsWith("/bands/all", StringComparison.Ordinal) ? bands(r) : inner(r);
        var settings = player ? new AppSettings { SelectedPlayer = new SelectedPlayer(PlayerWire.Id, "Fixture One") } : new AppSettings();
        var session = service.Session(settings: settings);
        var vm = new SongDetailViewModel(session, new AppRoute.SongDetail(songId));
        await vm.LoadAsync();
        await Async.Until(() => vm.BandPreviews.All(b => !b.IsLoading));
        return (service, session, vm);
    }

    #region Endpoint
    [Fact]
    public void Endpoint_IsTheKeylessAllRead_WithTheAccountOnlyInTheQuery()
    {
        var origin = new Uri(Wire.BaseUrl);
        Assert.Equal("https://festivalscoretracker.com/api/leaderboard/s%201/bands/all?top=10",
            BandEndpoints.SongBandLeaderboards(origin, "s 1", 10, null).AbsoluteUri);
        Assert.Equal($"https://festivalscoretracker.com/api/leaderboard/s1/bands/all?top=10&accountId={PlayerWire.Id}",
            BandEndpoints.SongBandLeaderboards(origin, "s1", 10, PlayerWire.Id).AbsoluteUri);
        Assert.Throws<FestivalApiException>(() => BandEndpoints.SongBandLeaderboards(origin, "s1", 0, null));
        Assert.Throws<FestivalApiException>(() => BandEndpoints.SongBandLeaderboards(origin, "s1", 51, null));
        Assert.Throws<FestivalApiException>(() => BandEndpoints.SongBandLeaderboards(origin, "s1", 10, "not/an id"));
        Assert.Throws<FestivalApiException>(() => BandEndpoints.SongBandLeaderboards(origin, "..", 10, null));
    }

    [Fact]
    public async Task Page_CallsOnlyTheAllowlistedAllRead_WithoutProfileHeaders()
    {
        var (service, _, vm) = await Open(_ => Wire.Ok(All("s1", true, Band("Band_Duets", [Entry("Band_Duets", 1)], 1)), (Pub, "7")), player: true);
        var band = Assert.Single(service.Handler.Requests, r => r.Uri.AbsolutePath.Contains("/bands", StringComparison.Ordinal));
        Assert.Equal("/api/leaderboard/s1/bands/all", band.Uri.AbsolutePath);
        Assert.Equal($"?top=10&accountId={PlayerWire.Id}", band.Uri.Query);
        Assert.Equal(HttpMethod.Get, band.Method);
        Assert.DoesNotContain(band.Headers.Keys, h => h.StartsWith("X-FST-Selected", StringComparison.OrdinalIgnoreCase) ||
                                                     h.Equals("X-API-Key", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(service.Handler.Requests, r => r.Uri.AbsolutePath.StartsWith("/api/bands/", StringComparison.Ordinal));
        vm.Detach();
    }
    #endregion

    #region Validation
    [Fact]
    public void Validate_AcceptsAKnownShape_AndReadsAMissingSizeAsEmpty()
    {
        var previews = Decode(All("s1", null, Band("Band_Trios", [Entry("Band_Trios", 1)], 4)));
        previews.Validate("s1", 10);
        Assert.Single(previews.For(BandType.Trios).Entries);
        Assert.Equal(4, previews.For(BandType.Trios).TotalEntries);
        var duos = previews.For(BandType.Duets);
        Assert.Equal("Band_Duets", duos.BandType);
        Assert.Empty(duos.Entries);
        Assert.Null(duos.FooterEntry);
    }

    [Theory]
    [InlineData("other-song")]
    [InlineData("unknown-size")]
    [InlineData("repeated-size")]
    [InlineData("count-mismatch")]
    [InlineData("over-top")]
    [InlineData("negative-total")]
    [InlineData("row-in-wrong-size")]
    [InlineData("selected-in-wrong-size")]
    public void Validate_RejectsInconsistentResponses(string problem)
    {
        var duo = Entry("Band_Duets", 1);
        var json = problem switch
        {
            "other-song" => All("s2", null, Band("Band_Duets", [duo], 1)),
            "unknown-size" => All("s1", null, Band("Band_Octets", [], 0)),
            "repeated-size" => All("s1", null, Band("Band_Duets", [duo], 1), Band("Band_Duets", [duo], 1)),
            "count-mismatch" => All("s1", null, Band("Band_Duets", [duo], 1, count: 2)),
            "over-top" => All("s1", null, Band("Band_Duets", [duo, Entry("Band_Duets", 2)], 2)),
            "negative-total" => All("s1", null, Band("Band_Duets", [duo], -1)),
            "row-in-wrong-size" => All("s1", null, Band("Band_Trios", [duo], 1)),
            _ => All("s1", null, Band("Band_Trios", [], 0, player: duo)),
        };
        var top = problem == "over-top" ? 1 : 10;
        var error = Assert.Throws<FestivalApiException>(() => Decode(json).Validate("s1", top));
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, error.Kind);
    }

    [Fact]
    public void SameBand_MatchesByBandIdOrByRoster()
    {
        var byId = Decode(All("s1", null, Band("Band_Duets", [Entry("Band_Duets", 1, "b1", "x:y"), Entry("Band_Duets", 2, "b1", "p:q")], 2))).Bands[0].Entries;
        Assert.True(SongBandPreview.IsSameBand(byId[0], byId[1]));
        var a = Decode(All("s1", null, Band("Band_Duets", [Entry("Band_Duets", 1, "", "m:n")], 1))).Bands[0].Entries[0];
        var b = Decode(All("s1", null, Band("Band_Duets", [Entry("Band_Duets", 5, "", "m:n")], 1))).Bands[0].Entries[0];
        var c = Decode(All("s1", null, Band("Band_Duets", [Entry("Band_Duets", 5, "", "m:o")], 1))).Bands[0].Entries[0];
        Assert.True(SongBandPreview.IsSameBand(a, b));
        Assert.False(SongBandPreview.IsSameBand(a, c));
    }
    #endregion

    #region Sections
    [Fact]
    public async Task Sections_OnePerSizeInOrder_WithRowsEmptyTextAndFullBoardRoutes()
    {
        var (_, _, vm) = await Open(_ => Wire.Ok(All("s1", true,
            Band("Band_Duets", [Entry("Band_Duets", 1, "band-1"), Entry("Band_Duets", 2)], 1234)), (Pub, "7")));
        Assert.Equal(["Duos", "Trios", "Quads"], vm.BandPreviews.Select(b => b.Title));
        var duos = vm.BandPreviews[0];
        Assert.True(duos.ShowRows);
        Assert.False(duos.ShowPlaceholder);
        Assert.Equal("1,234 bands", duos.Subtitle);
        Assert.Equal("Duos, 1,234 bands", duos.HeaderName);
        Assert.Equal(["fst.song-detail.band-row.Band_Duets.0", "fst.song-detail.band-row.Band_Duets.1"], duos.Rows.Select(r => r.AutomationId));
        Assert.Equal(new AppRoute.Band("band-1", "Band_Duets", "r1a:r1b"), duos.Rows[0].Route);
        Assert.Equal(new AppRoute.Band("r2a:r2b", "Band_Duets", "r2a:r2b"), duos.Rows[1].Route);
        var first = duos.Rows[0];
        Assert.Equal(("#1", "99,999", true, true, 5), (first.Rank, first.Score, first.IsFullCombo, first.HasAccuracy, first.StarCount));
        Assert.Equal(2, first.Members.Count);
        Assert.False(first.IsSelected);
        Assert.Equal("Rank 1. Lead 1, Lead. Bass 1, Bass. Team score 99,999 points, full combo, 96.5% accuracy, 5 stars", first.Announcement);
        Assert.Equal("Rank 2. Lead 2, Lead. Bass 2, Bass. Team score 99,998 points", duos.Rows[1].Announcement);
        Assert.Equal(new AppRoute.SongBandLeaderboard("s1", "Band_Duets"), duos.FullRoute);
        Assert.Equal(("fst.song-detail.band-view-all.Band_Duets", "View Full Leaderboard", "View Full Leaderboard, Duos"), (duos.ViewAllAutomationId, duos.ViewAllText, duos.ViewAllName));
        Assert.Equal(("fst.song-detail.band-header.Band_Duets", "band-Band_Duets"), (duos.HeaderAutomationId, duos.QuickLinkId));

        var quads = vm.BandPreviews[2];
        Assert.True(quads.ShowEmpty);
        Assert.False(quads.ShowRows);
        Assert.Equal(SongBandPreviewViewModel.NoScoresText, quads.Subtitle);
        Assert.Equal("When Quads scores are submitted for this song, they will show up here on the next leaderboard update.", quads.EmptyText);
        Assert.Equal("fst.song-detail.band-empty.Band_Quad", quads.EmptyAutomationId);
        Assert.Equal("fst.song-detail.band-loading.Band_Quad", quads.LoadingAutomationId);
        vm.Detach();
    }

    [Fact]
    public async Task Totals_HiddenUnlessTheServiceAllowsThem()
    {
        var (_, _, vm) = await Open(_ => Wire.Ok(All("s1", null, Band("Band_Duets", [Entry("Band_Duets", 1)], 1)), (Pub, "7")));
        Assert.Equal("", vm.BandPreviews[0].Subtitle);
        Assert.Equal("Duos", vm.BandPreviews[0].HeaderName);
        var (_, _, single) = await Open(_ => Wire.Ok(All("s1", true, Band("Band_Duets", [Entry("Band_Duets", 1)], 1)), (Pub, "7")));
        Assert.Equal("1 band", single.BandPreviews[0].Subtitle);
    }

    [Fact]
    public async Task SelectedPlayersBand_IsHighlightedInPlace()
    {
        var (_, _, vm) = await Open(_ => Wire.Ok(All("s1", true,
            Band("Band_Duets", [Entry("Band_Duets", 1), Entry("Band_Duets", 2, "", "me:mate")], 2, player: Entry("Band_Duets", 2, "", "me:mate"))), (Pub, "7")),
            player: true);
        var rows = vm.BandPreviews[0].Rows;
        Assert.Equal(2, rows.Count);
        Assert.Equal([false, true], rows.Select(r => r.IsSelected));
        Assert.Equal("Your band, Rank 2. Lead 2, Lead. Bass 2, Bass. Team score 99,998 points", rows[1].Announcement);
        Assert.DoesNotContain(rows, r => r.IsFooter);
    }

    [Fact]
    public async Task SelectedBandOutsideTheTop_IsAppendedAfterTheRows_AndASelectedBandEntryWins()
    {
        var player = Entry("Band_Trios", 14, "mine", "me:a:b");
        var promoted = Entry("Band_Trios", 22, "chosen", "c:d:e");
        var (_, _, vm) = await Open(_ => Wire.Ok(All("s1", true,
            Band("Band_Duets", [Entry("Band_Duets", 1)], 20, player: Entry("Band_Duets", 14, "", "me:x")),
            Band("Band_Trios", [Entry("Band_Trios", 1)], 30, player: player, band: promoted)), (Pub, "7")), player: true);
        var duos = vm.BandPreviews[0].Rows;
        Assert.Equal(2, duos.Count);
        Assert.True(duos[1].IsFooter);
        Assert.True(duos[1].IsSelected);
        Assert.Equal("fst.song-detail.band-selected.Band_Duets", duos[1].AutomationId);
        Assert.Equal("#14", duos[1].Rank);
        var trios = vm.BandPreviews[1].Rows;
        Assert.Equal("#22", trios[^1].Rank);
        Assert.Equal(new AppRoute.Band("chosen", "Band_Trios", "c:d:e"), trios[^1].Route);
    }

    [Fact]
    public async Task SelectedBandWithNoTopRows_StillShowsAsTheOnlyRow()
    {
        var (_, _, vm) = await Open(_ => Wire.Ok(All("s1", false, Band("Band_Quad", [], 3, player: Entry("Band_Quad", 3, "", "me:a:b:c"))), (Pub, "7")),
            player: true);
        var quads = vm.BandPreviews[2];
        Assert.True(quads.ShowRows);
        Assert.True(Assert.Single(quads.Rows).IsFooter);
        Assert.Equal("", quads.Subtitle);
    }

    [Fact]
    public async Task Failure_FailsEverySectionWithRetry_AndRetryReReads()
    {
        var fail = true;
        var (service, _, vm) = await Open(_ => fail
            ? Wire.Response(HttpStatusCode.InternalServerError)
            : Wire.Ok(All("s1", true, Band("Band_Duets", [Entry("Band_Duets", 1)], 1)), (Pub, "7")));
        Assert.True(vm.ShowContent);
        Assert.All(vm.BandPreviews, b => Assert.True(b.ShowError));
        Assert.All(vm.BandPreviews, b => Assert.True(b.ShowPlaceholder));
        Assert.Equal("fst.song-detail.band-retry.Band_Trios", vm.BandPreviews[1].RetryAutomationId);
        Assert.Equal("Trios scores unavailable", vm.BandPreviews[1].Status.Title);
        fail = false;
        await vm.BandPreviews[1].Status.RetryCommand.ExecuteAsync(null);
        await Async.Until(() => vm.BandPreviews[0].ShowRows);
        Assert.True(vm.BandPreviews[1].ShowEmpty);
        Assert.Equal(2, service.Handler.To("/api/leaderboard/s1/bands/all").Count());
    }

    [Fact]
    public async Task InvalidResponse_IsAFailureNotAnEmptyBoard()
    {
        var (_, _, vm) = await Open(_ => Wire.Ok(All("s2", true), (Pub, "7")));
        Assert.All(vm.BandPreviews, b => Assert.True(b.ShowError));
        Assert.All(vm.BandPreviews, b => Assert.Empty(b.Rows));
    }

    [Fact]
    public async Task BandRead_NeverHoldsThePageSpinner()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var inner = service.Override!;
        service.Override = r => r.RequestUri!.AbsolutePath.EndsWith("/bands/all", StringComparison.Ordinal)
            ? Wire.Response(HttpStatusCode.ServiceUnavailable)
            : inner(r);
        using var held = new SemaphoreSlim(0);
        var responder = service.Handler.Responder;
        service.Handler.Responder = async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/bands/all", StringComparison.Ordinal)) await held.WaitAsync(token);
            return await responder(request, token);
        };
        var vm = new SongDetailViewModel(service.Session(), new AppRoute.SongDetail("s1"));
        await vm.LoadAsync();
        Assert.True(vm.ShowContent);
        Assert.All(vm.BandPreviews, b => Assert.True(b.IsLoading));
        held.Release();
        await Async.Until(() => vm.BandPreviews.All(b => b.ShowError));
    }

    [Fact]
    public async Task AnotherPlayer_ReReadsWithTheirAccount_AndAStaleResponseIsDropped()
    {
        var (service, session, vm) = await Open(r => Wire.Ok(All("s1", true,
            Band("Band_Duets", [Entry("Band_Duets", 1)], 1, player: r.RequestUri!.Query.Contains(PlayerWire.Other, StringComparison.Ordinal)
                ? Entry("Band_Duets", 9, "", "other:x") : null)), (Pub, "7")), player: true);
        Assert.Single(vm.BandPreviews[0].Rows);
        session.SelectPlayer(new PlayerSearchResult(PlayerWire.Other, "Fixture Two"));
        await Async.Until(() => vm.BandPreviews[0].Rows.Count == 2);
        Assert.Contains(service.Handler.Requests, r => r.Uri.Query == $"?top=10&accountId={PlayerWire.Other}");
        session.DeselectPlayer();
        await Async.Until(() => vm.BandPreviews[0].Rows.Count == 1);
        Assert.Contains(service.Handler.Requests, r => r.Uri.AbsolutePath.EndsWith("/bands/all", StringComparison.Ordinal) && r.Uri.Query == "?top=10");
        vm.Detach();
    }

    [Fact]
    public async Task QuickLinks_ListBandSizesAfterTheInstruments()
    {
        var (_, _, vm) = await Open(_ => Wire.Ok(All("s1", true), (Pub, "7")));
        var ids = vm.QuickLinkSections.Select(s => s.Id).ToList();
        Assert.Equal(["band-Band_Duets", "band-Band_Trios", "band-Band_Quad"], ids.TakeLast(3));
        Assert.Equal(vm.Leaderboards.Select(c => c.QuickLinkId), ids.Skip(1).Take(vm.Leaderboards.Count));
        Assert.Equal("Quads", vm.QuickLinkSections[^1].Title);
    }

    [Fact]
    public async Task NoBandSections_SkipTheRead()
    {
        var service = new FakeService();
        var vm = new SongDetailViewModel(service.Session(), new AppRoute.SongDetail("s1"));
        await vm.LoadBandsAsync();
        Assert.Empty(service.Handler.Requests);
    }
    #endregion
}
