using System.Net;
using System.Text;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

public class SettingsPageTests
{
    private static (SettingsViewModel Vm, InMemorySettingsStore Store, FestivalSession Session) Create(
        AppSettings? settings = null, bool debug = true, FakeService? service = null)
    {
        var store = new InMemorySettingsStore(settings);
        var session = new FestivalSession((service ?? new FakeService()).Client(), store);
        return (new SettingsViewModel(session, "0.1.0", debug), store, session);
    }

    private static readonly SelectedPlayer Player = new("acc", "Jane");

    [Fact]
    public void AppSettings_PersistAndDescribe()
    {
        var (vm, store, _) = Create();
        vm.ShowInstrumentIcons = false;
        vm.EnableVisualOrder = true;
        vm.FilterInvalidScores = true;
        vm.Leeway = 2.345;
        vm.PathDefaultViewIndex = 1;
        vm.PathDefaultViewIndex = 7;
        Assert.False(store.Current.ShowInstrumentIcons);
        Assert.True(store.Current.EnableVisualOrder && store.Current.FilterInvalidScores);
        Assert.Equal(2.3, store.Current.Leeway);
        Assert.Equal(PathDisplayMode.Text, store.Current.PathDefaultView);
        Assert.Equal(1, vm.PathDefaultViewIndex);
        Assert.Equal("Maximum Score Leeway: +2.3%", vm.LeewayText);
        Assert.Equal("+2.3%", vm.LeewayValue);
        Assert.Contains("+2.3% leeway will allow the app to accept scores up to 102,300 as “valid”.", vm.LeewayDescription);
        vm.Leeway = -9;
        Assert.Equal(-5, vm.Leeway);
        Assert.False(vm.ExperimentalRanks);
        Assert.False(vm.ShowInstrumentIcons);
        Assert.True(vm.EnableVisualOrder && vm.FilterInvalidScores);
    }

    [Fact]
    public void Orders_ReorderAndSummarize()
    {
        var (vm, store, _) = Create();
        Assert.Equal(8, vm.SongRowOrder.Count);
        Assert.Equal("Score · Percentage · Percentile · Season Achieved · Intensity · Game Difficulty · Stars · Last Played", vm.VisualOrderSummary);
        Assert.Equal("Note · Beat · Time · OD · Score", vm.PathColumnSummary);
        var first = vm.SongRowOrder[0];
        Assert.Equal(("Score", "1", "Score, position 1 of 8", "fst.settings.song-row-order.score"), (first.Label, first.Position, first.AccessibleName, first.AutomationId));
        Assert.Equal(("Move Score up", "Move Score down"), (first.MoveUpName, first.MoveDownName));
        Assert.False(first.MoveUpCommand.CanExecute(null));
        Assert.True(first.MoveDownCommand.CanExecute(null));
        first.MoveDownCommand.Execute(null);
        Assert.Equal(MetadataField.Percentage, store.Current.SongRowVisualOrder[0]);
        Assert.Equal("Percentage", vm.SongRowOrder[0].Label);
        vm.SongRowOrder[7].MoveUpCommand.Execute(null);
        Assert.Equal(MetadataField.LastPlayed, store.Current.SongRowVisualOrder[6]);
        Assert.False(vm.SongRowOrder[7].MoveDownCommand.CanExecute(null));

        vm.PathColumnOrder[4].MoveUpCommand.Execute(null);
        Assert.Equal("Note · Beat · Time · Score · OD", vm.PathColumnSummary);
        Assert.Equal("fst.settings.path-column-order.od", vm.PathColumnOrder[4].AutomationId);
        Assert.Equal(5, vm.PathColumnOrder[4].Count);
        Assert.Equal(4, vm.PathColumnOrder[4].Index);

        foreach (var toggle in vm.Metadata) toggle.IsOn = false;
        Assert.Equal("No metadata fields are currently visible.", vm.VisualOrderSummary);
    }

    [Fact]
    public void Diagnostics_TelemetryRequiresDiagnostics()
    {
        var (vm, store, _) = Create();
        Assert.True(vm.IsDebugBuild);
        Assert.Equal("Debug", vm.BuildConfiguration);
        Assert.StartsWith("Enable Tap Diagnostics first", vm.TapTelemetryDescription);
        vm.TapTelemetry = true;
        Assert.False(store.Current.TapTelemetry);
        vm.TapDiagnostics = true;
        vm.TapTelemetry = true;
        Assert.True(vm.TapDiagnostics && vm.TapTelemetry);
        Assert.StartsWith("Send sanitized", vm.TapTelemetryDescription);
        vm.TapDiagnostics = false;
        Assert.False(store.Current.TapTelemetry);
        Assert.Contains(vm.QuickLinks.Items, i => i.Section.Id == "diagnostics");

        var (release, _, _) = Create(debug: false);
        Assert.Equal("Release", release.BuildConfiguration);
        Assert.DoesNotContain(release.QuickLinks.Items, i => i.Section.Id == "diagnostics");
        Assert.Equal(["app-settings", "item-shop", "show-instruments", "show-metadata", "accessibility", "version", "service-info", "first-run", "licenses", "reset"],
            release.QuickLinks.Items.Select(i => i.Section.Id));
    }

    [Fact]
    public void Shop_HidingKeepsHighlightPreference()
    {
        var (vm, store, _) = Create();
        Assert.True(vm.HighlightShopItems && vm.CanToggleShopHighlight);
        vm.HighlightShopItems = false;
        Assert.True(store.Current.DisableShopHighlighting);
        vm.HideShop = true;
        Assert.False(vm.CanToggleShopHighlight);
        Assert.True(vm.HideShop);
        Assert.False(vm.HighlightShopItems);
        vm.HideShop = false;
        Assert.False(vm.HighlightShopItems);
    }

    [Fact]
    public void Metadata_AnonymousOnlyIntensity()
    {
        var (vm, store, session) = Create();
        Assert.StartsWith("Select a player", vm.MetadataDescription);
        var score = vm.Metadata[0];
        var intensity = vm.Metadata.Single(m => m.Field == MetadataField.Intensity);
        Assert.Equal(("Score", "fst.settings.metadata.score"), (score.Label, score.AutomationId));
        Assert.False(score.IsEnabled);
        Assert.Equal("Select a player to use score metadata.", score.Description);
        Assert.True(intensity.IsEnabled);
        Assert.Equal("", intensity.Description);
        intensity.IsOn = false;
        Assert.False(store.Current.MetadataIntensity);
        var saves = store.SaveCount;
        intensity.IsOn = false;
        Assert.Equal(saves, store.SaveCount);
        session.SelectPlayer(new PlayerSearchResult("acc", "Jane"));
        Assert.True(score.IsEnabled);
        Assert.StartsWith("When filtering songs", vm.MetadataDescription);
        Assert.Equal("fst.settings.metadata.last-played", vm.Metadata[^1].AutomationId);
    }

    [Fact]
    public void Accessibility_AdditiveOverrides()
    {
        var (vm, store, _) = Create();
        vm.MoreContrast = true;
        vm.LessTransparency = true;
        Assert.True(vm.MoreContrast && vm.LessTransparency);
        Assert.True(store.Current.MoreContrast && store.Current.LessTransparency);
    }

    [Fact]
    public void Version_AndReplayAndReset()
    {
        var (vm, store, _) = Create(new AppSettings { SelectedPlayer = Player, SongSort = SongSortMode.Artist, HideShop = true, Leeway = 3 });
        Assert.Equal(("0.1.0", "Not yet available"), (vm.AppVersion, vm.ServiceVersion));
        Assert.Equal("Unknown", new SettingsViewModel(new FakeService().Session(), "").AppVersion);

        Assert.Equal(9, vm.FirstRunPages.Count);
        var songs = vm.FirstRunPages[0];
        Assert.Equal(("Songs", "9 slides", "fst.settings.first-run.songs", "Show Songs guide"), (songs.Label, songs.Detail, songs.AutomationId, songs.ButtonName));
        FirstRunPageKey? requested = null;
        vm.ReplayRequested += (_, page) => requested = page;
        vm.ReplayFirstRunCommand.Execute(FirstRunPageKey.Shop);
        Assert.Equal(FirstRunPageKey.Shop, requested);

        vm.ResetAppSettingsCommand.Execute(null);
        Assert.Equal(Player, store.Current.SelectedPlayer);
        Assert.Equal(SongSortMode.Artist, store.Current.SongSort);
        Assert.False(store.Current.HideShop);
        Assert.Equal(1, store.Current.Leeway);
    }

    [Fact]
    public async Task CheckPublication_ReportsSuccessAndFailures()
    {
        var (vm, _, _) = Create();
        await vm.CheckPublicationCommand.ExecuteAsync(null);
        Assert.Equal("Publication 7; 3 songs", vm.PublicationStatus);
        Assert.False(vm.IsCheckingPublication);

        var songsDown = new FakeService();
        songsDown.Override = r => r.RequestUri!.AbsolutePath == "/api/songs" ? Wire.Response(HttpStatusCode.ServiceUnavailable) : null;
        var (failing, _, _) = Create(service: songsDown);
        await failing.CheckPublicationCommand.ExecuteAsync(null);
        Assert.StartsWith("Publication 7; songs update failed: ", failing.PublicationStatus);

        var down = new FakeService { Override = _ => Wire.Response(HttpStatusCode.ServiceUnavailable) };
        var (offline, _, _) = Create(service: down);
        await offline.CheckPublicationCommand.ExecuteAsync(null);
        Assert.StartsWith("Publication unavailable: ", offline.PublicationStatus);
    }

    [Fact]
    public async Task CheckPublication_NewerCheckSupersedesOlder()
    {
        var gate = new TaskCompletionSource();
        var service = new FakeService();
        var calls = 0;
        service.Handler.Responder = async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath == "/api/publication" && Interlocked.Increment(ref calls) == 1)
                await gate.Task.WaitAsync(token);
            return request.RequestUri!.AbsolutePath == "/api/publication"
                ? Wire.Ok(Wire.Publication())
                : Wire.Ok(Wire.DefaultSongs(), ("X-FST-Publication-Id", "7"));
        };
        var (vm, _, _) = Create(service: service);
        var first = vm.CheckPublicationCommand.ExecuteAsync(null);
        Assert.True(vm.IsCheckingPublication);
        Assert.False(vm.CheckPublicationCommand.CanExecute(null));
        Assert.Equal("Checking…", vm.PublicationStatus);
        // CanExecute is false while running, so call the method directly to supersede the first check.
        var method = typeof(SettingsViewModel).GetMethod("CheckPublicationAsync", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!;
        var second = (Task)method.Invoke(vm, null)!;
        await second;
        gate.SetResult();
        await first;
        Assert.Equal("Publication 7; 3 songs", vm.PublicationStatus);
        Assert.False(vm.IsCheckingPublication);
    }

    [Fact]
    public void Licenses_ParseValidateAndPresent()
    {
        var json = """
            {"schemaVersion":1,"packages":[
              {"id":"Zeta.Pkg","name":"Zeta","version":"2.0","ecosystem":"NuGet","license":"MIT","url":"https://example.com/z","textId":"t1"},
              {"id":"Alpha","name":"Alpha","version":"1.0","ecosystem":"NuGet","license":"BSD","url":"http://insecure","textId":"t2"},
              {"id":"Orphan","name":"Orphan","version":"1","ecosystem":"NuGet","license":"X","textId":"missing"},
              {"id":"Blank","name":"","version":"1","ecosystem":"NuGet","license":"X","textId":"t1"}
            ],"texts":{"t1":"MIT text","t2":"BSD text"}}
            """;
        var manifest = LicenseManifest.Parse(Encoding.UTF8.GetBytes(json));
        Assert.Equal(1, manifest.SchemaVersion);
        var vm = new LicensesViewModel(manifest);
        Assert.Equal(["Alpha", "Zeta"], vm.Packages.Select(p => p.Name));
        Assert.False(vm.HasNoPackages);
        Assert.StartsWith("2 open source", vm.Summary);
        var zeta = vm.Packages[1];
        Assert.Equal(("NuGet · 2.0", "MIT", "MIT text", "fst.licenses.row.zeta.pkg", "Zeta, NuGet · 2.0, MIT"),
            (zeta.Subtitle, zeta.License, zeta.Text, zeta.AutomationId, zeta.AccessibleName));
        Assert.True(zeta.HasUrl);
        Assert.Equal(new Uri("https://example.com/z"), zeta.Url);
        Assert.False(vm.Packages[0].HasUrl);
        Assert.Equal("Instrument Iconography", Assert.Single(vm.Assets).Name);

        Assert.Empty(LicenseManifest.Parse(null).Packages);
        Assert.Empty(LicenseManifest.Parse("broken"u8.ToArray()).Packages);
        Assert.Empty(LicenseManifest.Parse("null"u8.ToArray()).Packages);
        Assert.Empty(LicenseManifest.Parse("""{"packages":null,"texts":null}"""u8.ToArray()).Packages);
        var empty = new LicensesViewModel(LicenseManifest.Parse(null));
        Assert.True(empty.HasNoPackages);
        Assert.Equal("No third-party packages are listed for this build.", empty.Summary);
    }

    [Fact]
    public void Licenses_CommittedManifestIsValid()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App", "Assets", "licenses.json");
        var manifest = LicenseManifest.Parse(File.ReadAllBytes(path));
        Assert.Contains(manifest.Packages, p => p.Id == "CommunityToolkit.Mvvm");
        Assert.Contains(manifest.Packages, p => p.Id == "Microsoft.WindowsAppSDK");
        Assert.All(manifest.Packages, p => Assert.NotEmpty(manifest.Texts[p.TextId]));
    }
}
