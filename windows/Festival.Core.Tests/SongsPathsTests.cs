using System.Net;
using System.Text;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

public class PathModelTests
{
    private static SongPathData Decode(string json) => FestivalApiClient.Decode(Encoding.UTF8.GetBytes(json), SongsJsonContext.Default.SongPathData);

    [Fact]
    public void Endpoint_BuildsImageAndTextUrls()
    {
        var root = new Uri(Wire.BaseUrl);
        Assert.Equal("https://festivalscoretracker.com/api/paths/s1/Solo_Guitar/expert",
            ServiceEndpoints.Path(root, "s1", Instrument.Lead, PathDifficulty.Expert, text: false).AbsoluteUri);
        Assert.Equal("https://festivalscoretracker.com/api/paths/s1/Solo_PeripheralDrums/easy/data?generationId=g%201",
            ServiceEndpoints.Path(root, "s1", Instrument.ProDrums, PathDifficulty.Easy, text: true, "g 1").AbsoluteUri);
        Assert.Throws<FestivalApiException>(() => ServiceEndpoints.Path(root, "s1", Instrument.Karaoke, PathDifficulty.Easy, true));
        Assert.Throws<FestivalApiException>(() => ServiceEndpoints.Path(root, "s1", Instrument.Lead, (PathDifficulty)9, true));
        Assert.Throws<FestivalApiException>(() => ServiceEndpoints.Path(root, "s1", Instrument.Lead, PathDifficulty.Easy, true, ""));
        Assert.Throws<FestivalApiException>(() => ServiceEndpoints.Path(root, "../x", Instrument.Lead, PathDifficulty.Easy, true));
        Assert.Equal("https://festivalscoretracker.com/api/shop", ServiceEndpoints.Shop(root).AbsoluteUri);
        Assert.Equal(["Easy", "Medium", "Hard", "Expert"], PathDifficultyInfo.All.Select(d => d.Label()));
        Assert.False(Instrument.Karaoke.HasPaths());
        Assert.True(Instrument.ProLead.HasPaths());
    }

    [Fact]
    public void Validate_RejectsInconsistentData()
    {
        Decode(SongsWire.PathData()).Validate(PathDifficulty.Expert);
        Assert.Throws<FestivalApiException>(() => Decode(SongsWire.PathData("hard")).Validate(PathDifficulty.Expert));
        Assert.Throws<FestivalApiException>(() => Decode(SongsWire.PathData().Replace("123456", "0")).Validate(PathDifficulty.Expert));
        Assert.Throws<FestivalApiException>(() => Decode(SongsWire.PathData().Replace("\"schemaVersion\":2", "\"schemaVersion\":3")).Validate(PathDifficulty.Expert));
        Assert.Throws<FestivalApiException>(() => Decode(SongsWire.PathData(activations: """{"startBeat":5,"endBeat":4}""")).Validate(PathDifficulty.Expert));
        Assert.Throws<FestivalApiException>(() => Decode(SongsWire.PathData(activations: """{"startBeat":1,"endBeat":4,"odAtActivation":1.5}""")).Validate(PathDifficulty.Expert));
        Assert.Throws<FestivalApiException>(() => Decode(SongsWire.PathData(activations: """{"startBeat":1,"endBeat":4,"activationSeconds":-1}""")).Validate(PathDifficulty.Expert));
        Assert.Throws<FestivalApiException>(() => Decode(SongsWire.PathData(notes: """{"beat":1,"isSpNote":false,"frets":{"purple":0}}""")).Validate(PathDifficulty.Expert));
        Assert.Throws<FestivalApiException>(() => Decode(SongsWire.PathData(activations:
            """{"startBeat":1,"endBeat":4,"startNotes":[{"beat":1,"cumulativeScore":-1,"noteValue":1,"odPercent":0.5,"isSpGranting":false}]}""")).Validate(PathDifficulty.Expert));
    }

    [Fact]
    public void ActivationRows_ResolveAnchorsTimesAndColumns()
    {
        var path = Decode(SongsWire.PathData(
            activations: string.Join(",",
                """{"startBeat":10,"endBeat":20,"activationBeat":10,"activationSeconds":61.2345,"anchorBeat":10,"odAtActivation":0.5,"scoreBeforeActivation":12345,"instruction":"Squeeze"}""",
                """{"startBeat":30,"endBeat":40,"startNotes":[{"beat":30.01,"seconds":90,"cumulativeScore":500,"noteValue":50,"odPercent":0.75,"isSpGranting":true}]}""",
                """{"startBeat":50,"endBeat":60,"startSeconds":120}""",
                """{"startBeat":70,"endBeat":80}"""),
            notes: string.Join(",",
                """{"beat":10,"isSpNote":false,"frets":{"green":0,"red":0}}""",
                """{"beat":10.01,"isSpNote":false,"frets":{"open":0}}""",
                """{"beat":30,"isSpNote":false,"frets":{"blue":0}}""",
                """{"beat":49,"isSpNote":true,"frets":{"orange":2}}""",
                """{"beat":69,"isSpNote":false,"frets":{"yellow":0}}""")));
        path.Validate(PathDifficulty.Expert);
        var rows = path.ActivationRows();
        Assert.Equal(4, rows.Count);
        Assert.Equal(["green", "red", "open"], rows[0].Frets);
        Assert.Equal(("10.00", "01:01:235", "50%", 12345L), (rows[0].BeatText, rows[0].TimeText, rows[0].OdText, rows[0].ScoreBeforeActivation));
        Assert.Equal("Squeeze", rows[0].Instruction);
        Assert.True(rows[0].HasFret("red"));
        Assert.Equal(["blue"], rows[1].Frets);
        Assert.Equal((90d, 75d, 500L), (rows[1].Seconds, rows[1].OdPercent!.Value, rows[1].ScoreBeforeActivation!.Value));
        Assert.Equal(["orange"], rows[2].Frets); // sustained through the activation
        Assert.Equal(120, rows[2].Seconds);
        Assert.Empty(rows[3].Frets); // earlier note neither sustained nor coincident
        Assert.Equal(("—", "—", "No anchor", "00:00:000"), (rows[3].OdText, rows[3].ScoreText, rows[3].FretsText, rows[3].TimeText));
        Assert.Null(rows[3].OdFill);
        Assert.Equal("Activation 4: No anchor; beat " + rows[3].BeatText + "; time 00:00:000; Overdrive unavailable; score unavailable", rows[3].AccessibleName);
        Assert.Equal(50, rows[0].OdFill);
        Assert.Equal("Activation 1: green, red, open; beat 10.00; time 01:01:235; Overdrive 50%; score 12,345", rows[0].AccessibleName);
        Assert.Equal(100, (rows[0] with { OdPercent = 140 }).OdFill);
        Assert.Equal(0, (rows[0] with { OdPercent = -3 }).OdFill);
        Assert.Equal("green, red, open", rows[0].FretsText);
    }

    [Fact]
    public void PngDimensions_AreBounded()
    {
        Assert.Equal((100, 400), PathImageValidation.Dimensions(SongsWire.Png()));
        Assert.Throws<FestivalApiException>(() => PathImageValidation.Dimensions(new byte[10]));
        Assert.Throws<FestivalApiException>(() => PathImageValidation.Dimensions(SongsWire.Png(9000, 10)));
        Assert.Throws<FestivalApiException>(() => PathImageValidation.Dimensions(SongsWire.Png(8000, 29_000)));
        Assert.Throws<FestivalApiException>(() => PathImageValidation.Dimensions(SongsWire.Png(0, 10)));
        var notPng = SongsWire.Png();
        notPng[1] = 0;
        Assert.Throws<FestivalApiException>(() => PathImageValidation.Dimensions(notPng));
        var noHeader = SongsWire.Png();
        noHeader[12] = (byte)'X';
        Assert.Throws<FestivalApiException>(() => PathImageValidation.Dimensions(noHeader));
    }

    [Fact]
    public async Task Client_ReadsImageAndText()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var client = service.Client();
        var image = await client.GetPathImageAsync("s1", Instrument.Lead, PathDifficulty.Hard, "gen");
        Assert.Equal((100, 400), (image.Width, image.Height));
        var data = await client.GetPathDataAsync("s1", Instrument.Lead, PathDifficulty.Hard);
        Assert.Equal(123456, data.TotalScore);
        Assert.Contains(service.Handler.Requests, r => r.Uri.Query == "?generationId=gen");
    }
}

public class SongPathsViewModelTests
{
    private static Song Song(string? generation = null) => new() { SongId = "s1", Title = "Alpha", Artist = "Zed", PathArtifactGenerationId = generation };

    [Fact]
    public async Task Opens_ImageByDefault_ThenSwitchesToText()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var session = service.Session();
        var vm = new SongPathsViewModel(session, Song("g"), [Instrument.Lead, Instrument.Bass]);
        Assert.Equal(["Lead", "Bass"], vm.InstrumentLabels);
        Assert.Equal(PathDifficulty.Expert, vm.Difficulty);
        Assert.True(vm.IsLoading);
        Assert.True(vm.ShowWarning); // Karaoke visible by default
        await vm.LoadAsync();
        Assert.True(vm.ShowImage);
        Assert.Equal("Lead Expert CHOpt path", vm.ImageDescription);
        vm.DisplayIndex = 1;
        await Async.Until(() => vm.ShowTable);
        Assert.Equal(1, vm.DisplayIndex);
        Assert.True(vm.HasNoActivations);
        Assert.Equal(SettingsOrder.Normalize<PathColumnKey>(null), vm.Columns);
        var changed = new List<string?>();
        vm.PropertyChanged += (_, e) => changed.Add(e.PropertyName);
        vm.SelectInstrument(Instrument.Karaoke); // not offered: ignored
        Assert.Equal(Instrument.Lead, vm.Instrument);
        vm.SelectInstrument(Instrument.Bass);
        Assert.Contains(nameof(SongPathsViewModel.Instrument), changed);
        Assert.Equal("Instrument: Bass", vm.InstrumentButtonName);
        vm.DifficultyIndex = 0;
        await Async.Until(() => vm.ShowTable && vm.Instrument == Instrument.Bass && vm.Difficulty == PathDifficulty.Easy);
        Assert.Contains(service.Handler.Requests, r => r.Uri.AbsolutePath == "/api/paths/s1/Solo_Bass/easy/data");
        vm.Close();
    }

    [Fact]
    public async Task TextDefault_ZoomAndWarningDismissal()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var session = service.Session(settings: new AppSettings { PathDefaultView = PathDisplayMode.Text });
        var vm = new SongPathsViewModel(session, Song(), [Instrument.Lead]);
        Assert.True(vm.ShowText);
        await vm.LoadAsync();
        Assert.True(vm.ShowTable);
        Assert.Equal(("100%", false, true), (vm.ZoomText, vm.CanZoomOut, vm.CanZoomIn));
        vm.ZoomInCommand.Execute(null);
        vm.ZoomInCommand.Execute(null);
        vm.ZoomInCommand.Execute(null);
        Assert.Equal((3d, false), (vm.Zoom, vm.CanZoomIn));
        vm.ZoomOutCommand.Execute(null);
        Assert.Equal("200%", vm.ZoomText);
        vm.DismissWarning(false);
        Assert.False(vm.ShowWarning);
        Assert.False(session.Settings.PathUnavailableWarningDismissed);
        // Once per app session: the next opening doesn't repeat it; a new session does.
        Assert.False(new SongPathsViewModel(session, Song(), [Instrument.Lead]).ShowWarning);
        session.PathNoticeShown = false;
        Assert.True(new SongPathsViewModel(session, Song(), [Instrument.Lead]).ShowWarning);
        vm.DismissWarning(true);
        Assert.True(session.Settings.PathUnavailableWarningDismissed);
        session.PathNoticeShown = false;
        Assert.False(new SongPathsViewModel(session, Song(), [Instrument.Lead]).ShowWarning);
    }

    [Fact]
    public async Task Failure_ShowsStatusAndRetryRecovers()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var inner = service.Override!;
        var fail = true;
        service.Override = r => fail && r.RequestUri!.AbsolutePath.StartsWith("/api/paths/", StringComparison.Ordinal)
            ? Wire.Response(HttpStatusCode.InternalServerError) : inner(r);
        var vm = new SongPathsViewModel(service.Session(), Song(), [Instrument.Lead]);
        await vm.LoadAsync();
        Assert.True(vm.ShowError);
        Assert.False(vm.ShowNotGenerated);
        fail = false;
        await vm.Status.RetryCommand.ExecuteAsync(null);
        await Async.Until(() => vm.ShowImage);
    }

    [Fact]
    public async Task NotFound_IsNotGeneratedRatherThanAnError()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var inner = service.Override!;
        service.Override = r => r.RequestUri!.AbsolutePath.StartsWith("/api/paths/", StringComparison.Ordinal)
            ? Wire.Response(HttpStatusCode.NotFound, "{}", ("X-FST-Publication-Id", "7")) : inner(r);
        var vm = new SongPathsViewModel(service.Session(), Song(), [Instrument.Lead]);
        await vm.LoadAsync();
        Assert.True(vm.ShowNotGenerated);
        Assert.False(vm.ShowError);
        Assert.False(vm.IsLoading);
    }

    [Fact]
    public async Task StaleResponse_NeverPaintsOverNewerChoice()
    {
        var service = new FakeService();
        SongsWire.Install(service);
        var inner = service.Override!;
        var gate = new TaskCompletionSource();
        service.Handler.Responder = async (request, _) =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/expert", StringComparison.Ordinal)) await gate.Task;
            return inner(request) ?? Wire.Ok(Wire.Publication(7));
        };
        var vm = new SongPathsViewModel(service.Session(), Song(), [Instrument.Lead]);
        var first = vm.LoadAsync();
        await Async.Until(() => service.Handler.Requests.Any(r => r.Uri.AbsolutePath.EndsWith("/expert", StringComparison.Ordinal)));
        vm.DifficultyIndex = 2; // hard
        await Async.Until(() => vm.ShowImage);
        gate.SetResult();
        await first;
        Assert.Equal(PathDifficulty.Hard, vm.Difficulty);
        Assert.True(vm.ShowImage);
    }
}
