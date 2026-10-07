using System.Text;

namespace Festival.Core.Tests;

public class RoutingTests
{
    public static TheoryData<AppRoute, string, AppSection> Routes => new()
    {
        { new AppRoute.SongDetail("s1"), "/songs/s1", AppSection.Songs },
        { new AppRoute.SongDetail("s1", Instrument.Bass), "/songs/s1?instrument=Solo_Bass", AppSection.Songs },
        { new AppRoute.SongLeaderboard("s1", Instrument.Lead), "/songs/s1/Solo_Guitar", AppSection.Songs },
        { new AppRoute.SongLeaderboard("s1", Instrument.Lead, 3), "/songs/s1/Solo_Guitar?page=3", AppSection.Songs },
        { new AppRoute.SongLeaderboard("s1", Instrument.Lead, RevealSelected: true), "/songs/s1/Solo_Guitar?page=1&navToPlayer=true", AppSection.Songs },
        { new AppRoute.SongBandLeaderboard("s1", "Band_Duets"), "/songs/s1/bands/Band_Duets", AppSection.Songs },
        // Pattern leaderboard-row R7 (#307): the selected row's jump reveals it, as web navToPlayer / navToBand.
        { new AppRoute.SongLeaderboard("s1", Instrument.Lead, 3, RevealSelected: true), "/songs/s1/Solo_Guitar?page=3&navToPlayer=true", AppSection.Songs },
        { new AppRoute.SongBandLeaderboard("s1", "Band_Duets", 2), "/songs/s1/bands/Band_Duets?page=2", AppSection.Songs },
        { new AppRoute.SongBandLeaderboard("s1", "Band_Duets", 1, RevealSelected: true), "/songs/s1/bands/Band_Duets?page=1&navToBand=true", AppSection.Songs },
        { new AppRoute.PlayerHistory("s1", Instrument.Karaoke), "/songs/s1/Solo_PeripheralVocals/history", AppSection.Songs },
        { new AppRoute.Player("acc1"), "/player/acc1", AppSection.Leaderboards },
        { new AppRoute.PlayerBands("acc1"), "/bands/player/acc1", AppSection.Leaderboards },
        { new AppRoute.PlayerBands("acc1", PlayerBandGroup.Quads), "/bands/player/acc1?group=quads", AppSection.Leaderboards },
        { new AppRoute.Bands(), "/bands", AppSection.Leaderboards },
        { new AppRoute.Band("b1"), "/bands/b1", AppSection.Leaderboards },
        { new AppRoute.Band("b1", "Band_Duets", "k"), "/bands/b1?bandType=Band_Duets&teamKey=k", AppSection.Leaderboards },
        { new AppRoute.Leaderboards(), "/leaderboards", AppSection.Leaderboards },
        { new AppRoute.FullRankings(Instrument.Drums, "adjusted"), "/leaderboards/all?instrument=Solo_Drums&rankBy=adjusted", AppSection.Leaderboards },
        { new AppRoute.FullRankings(Instrument.Drums, "adjusted", 37), "/leaderboards/all?instrument=Solo_Drums&rankBy=adjusted&page=37", AppSection.Leaderboards },
        { new AppRoute.BandRankings("Band_Trios"), "/leaderboards/bands/Band_Trios", AppSection.Leaderboards },
        { new AppRoute.Rivals(), "/rivals", AppSection.Rivals },
        { new AppRoute.AllRivals(new RivalScope.FromSettings(RivalSettingsScope.Common)), "/rivals/all?category=common", AppSection.Rivals },
        { new AppRoute.AllRivals(new RivalScope.Leaderboard(Instrument.Bass, RankingMetric.FcRate)), "/rivals/all?category=Solo_Bass&mode=leaderboard&rankBy=fcrate", AppSection.Rivals },
        { new AppRoute.AllRivals(new RivalScope.Song([Instrument.Lead, Instrument.Bass])), "/rivals/all?category=common&instruments=Solo_Guitar%2CSolo_Bass", AppSection.Rivals },
        { new AppRoute.RivalDetail("r1"), "/rivals/r1", AppSection.Rivals },
        { new AppRoute.RivalDetail("r1", "A B", new RivalScope.Combo("03")), "/rivals/r1?name=A%20B&scope=combo%3A03", AppSection.Rivals },
        { new AppRoute.Rivalry("r1", "almost_passed"), "/rivals/r1/rivalry?mode=almost_passed", AppSection.Rivals },
        { new AppRoute.Rivalry("r1", "slipping_away", "N", new RivalScope.Song([Instrument.Drums])), "/rivals/r1/rivalry?mode=slipping_away&name=N&scope=song%3ASolo_Drums", AppSection.Rivals },
        { new AppRoute.Statistics(), "/statistics", AppSection.Statistics },
        { new AppRoute.Suggestions(), "/suggestions", AppSection.Suggestions },
        { new AppRoute.Compete(), "/compete", AppSection.Rivals },
        { new AppRoute.Shop(), "/shop", AppSection.Shop },
        { new AppRoute.Licenses(), "/settings/licenses", AppSection.Settings },
    };

    [Theory]
    [MemberData(nameof(Routes))]
    public void Routes_RoundTripThroughPaths(AppRoute route, string path, AppSection section)
    {
        Assert.Equal(path, route.ToPath());
        Assert.Equal(section, route.Section);
        Assert.True(AppRouteParser.TryParse(path, out var parsed, out var parsedSection));
        Assert.Equal(route, parsed);
        Assert.Equal(section, parsedSection);
    }

    [Theory]
    [InlineData("/bands/player/acc1?group=Duos&name=Player%20One", PlayerBandGroup.Duos, "Player One")]
    [InlineData("/bands/player/acc1?group=all&name=Player%20One", PlayerBandGroup.All, "Player One")]
    [InlineData("/bands/player/acc1?group=bogus", PlayerBandGroup.All, null)]
    public void Parser_PlayerBandsGroupAndName(string path, PlayerBandGroup group, string? name)
    {
        Assert.True(AppRouteParser.TryParse(path, out var route, out _));
        Assert.Equal(new AppRoute.PlayerBands("acc1", group, name), route);
    }

    [Theory]
    [InlineData("/songs/s1/Solo_Guitar?navToPlayer=false", false)]
    [InlineData("/songs/s1/Solo_Guitar?navToPlayer=1", false)]
    [InlineData("/songs/s1/Solo_Guitar?page=2&navToPlayer=true", true)]
    public void Parser_SongLeaderboardRevealsOnlyWhenNavToPlayerIsTrue(string path, bool navToPlayer)
    {
        Assert.True(AppRouteParser.TryParse(path, out var route, out _));
        Assert.Equal(navToPlayer, Assert.IsType<AppRoute.SongLeaderboard>(route).RevealSelected);
    }

    [Fact]
    public void PlayerBandsPath_NeverSerializesTheName()
    {
        Assert.Equal("/bands/player/acc1?group=trios", new AppRoute.PlayerBands("acc1", PlayerBandGroup.Trios, "Player One").ToPath());
        Assert.Equal("/bands/player/acc1", new AppRoute.PlayerBands("acc1", PlayerBandGroup.All, "Player One").ToPath());
    }

    [Theory]
    [InlineData("/", AppSection.Songs)]
    [InlineData("/songs", AppSection.Songs)]
    [InlineData("/settings", AppSection.Settings)]
    [InlineData("https://festivalscoretracker.com/settings", AppSection.Settings)]
    public void Parser_SectionRoots(string path, AppSection section)
    {
        Assert.True(AppRouteParser.TryParse(path, out var route, out var parsed));
        Assert.Null(route);
        Assert.Equal(section, parsed);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("  ")]
    [InlineData("/manual")]
    [InlineData("/songs/s1/NotAnInstrument")]
    [InlineData("/songs/%2E%2E")]
    [InlineData("/player/bad%20id")]
    [InlineData("/songs//x")]
    [InlineData("/rivals/bad%20id/rivalry")]
    [InlineData("/rivals/all?category=nonsense")]
    public void Parser_RejectsUnknownOrUnsafePaths(string? path) => Assert.False(AppRouteParser.TryParse(path, out _, out _));

    [Fact]
    public void Parser_DefaultsAndLenientQuery()
    {
        AppRouteParser.TryParse("/songs/s1/Solo_Bass?page=abc&junk&=x&instrument=%01", out var route, out _);
        Assert.Equal(new AppRoute.SongLeaderboard("s1", Instrument.Bass, 1), route);
        AppRouteParser.TryParse("/songs/s1/bands/Band_Trios?page=-4&navToBand=TRUE", out var band, out _);
        Assert.Equal(new AppRoute.SongBandLeaderboard("s1", "Band_Trios", 1, RevealSelected: true), band);
        AppRouteParser.TryParse("/songs/s1/Solo_Bass?navToPlayer=yes", out var unflagged, out _);
        Assert.Equal(new AppRoute.SongLeaderboard("s1", Instrument.Bass), unflagged);
        AppRouteParser.TryParse("/leaderboards/all", out var rankings, out _);
        Assert.Equal(new AppRoute.FullRankings(Instrument.Lead, "totalscore"), rankings); // web DEFAULT_METRIC
        AppRouteParser.TryParse("/rivals/r1/rivalry", out var rivalry, out _);
        Assert.Equal(new AppRoute.Rivalry("r1", "closest_battles"), rivalry);
        AppRouteParser.TryParse("/rivals/r1?scope=bogus", out var unscoped, out _);
        Assert.Equal(new AppRoute.RivalDetail("r1"), unscoped);
        AppRouteParser.TryParse("/rivals/all", out var all, out _);
        Assert.Equal(new AppRoute.AllRivals(new RivalScope.FromSettings(RivalSettingsScope.Common)), all);
        AppRouteParser.TryParse("/songs/s1?instrument=bogus", out var detail, out _);
        Assert.Equal(new AppRoute.SongDetail("s1"), detail);
        AppRouteParser.TryParse("/songs/a%20b", out var escaped, out _);
        Assert.Equal("/songs/a%20b", escaped!.ToPath());
    }

    [Fact]
    public void Sections_DependOnPlayer()
    {
        Assert.Equal([AppSection.Songs, AppSection.Leaderboards, AppSection.Shop, AppSection.Settings], AppSections.Visible(false));
        Assert.Equal([AppSection.Songs, AppSection.Leaderboards, AppSection.Settings], AppSections.Visible(false, hideShop: true));
        Assert.Equal(7, AppSections.Visible(true).Count);
        Assert.Equal("Item Shop", AppSection.Shop.Label());
        Assert.Equal("fst.nav.shop", AppSection.Shop.AutomationId());
        Assert.True(AppSection.Rivals.RequiresPlayer());
        Assert.False(AppSection.Leaderboards.RequiresPlayer());
        Assert.Equal("fst.nav.statistics", AppSection.Statistics.AutomationId());
        Assert.Equal("Suggestions", AppSection.Suggestions.Label());
        Assert.True(AppSections.TryParse("RIVALS", out var s));
        Assert.Equal(AppSection.Rivals, s);
        Assert.False(AppSections.TryParse("7", out _));
        Assert.False(AppSections.TryParse("nope", out _));
    }
}

public class SettingsTests : IDisposable
{
    private readonly string directory = Path.Combine(Path.GetTempPath(), "fst-tests-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(directory)) Directory.Delete(directory, true);
    }

    [Fact]
    public void Sanitize_ClampsEverything()
    {
        var bad = new AppSettings
        {
            Version = 0,
            SelectedPlayer = new SelectedPlayer("bad id", "x"),
            SongSort = (SongSortMode)42,
            SongFilter = new SongFilter((Instrument)77),
            VisibleInstruments = [(Instrument)99],
        };
        var clean = bad.Sanitized();
        Assert.Equal(AppSettings.CurrentVersion, clean.Version);
        Assert.Null(clean.SelectedPlayer);
        Assert.Equal(SongSortMode.Title, clean.SongSort);
        Assert.Equal(SongFilter.None, clean.SongFilter);
        Assert.Equal(InstrumentInfo.All, clean.VisibleInstruments);
        var hiddenFilter = new AppSettings { SongFilter = new SongFilter(Instrument.Bass), VisibleInstruments = [Instrument.Lead, Instrument.Lead] }.Sanitized();
        Assert.Null(hiddenFilter.SongFilter.Instrument);
        Assert.Equal([Instrument.Lead], hiddenFilter.VisibleInstruments);
        Assert.Equal(SongFilter.None, new AppSettings { SongFilter = new SongFilter((Instrument)77) }.Sanitized().SongFilter);
        Assert.Equal(InstrumentInfo.All, new AppSettings { VisibleInstruments = null! }.Sanitized().VisibleInstruments);
    }

    [Fact]
    public void InstrumentVisibility_KeepsLastChart()
    {
        var one = new AppSettings { VisibleInstruments = [Instrument.Bass], SongFilter = new SongFilter(Instrument.Bass) };
        Assert.Equal([Instrument.Bass], one.WithInstrumentVisible(Instrument.Bass, false).VisibleInstruments);
        var two = one.WithInstrumentVisible(Instrument.Lead, true);
        Assert.Equal([Instrument.Lead, Instrument.Bass], two.VisibleInstruments);
        var hidden = two.WithInstrumentVisible(Instrument.Bass, false);
        Assert.Equal([Instrument.Lead], hidden.VisibleInstruments);
        Assert.Null(hidden.SongFilter.Instrument);
    }

    [Fact]
    public void SelectedPlayer_ValidationAndInitials()
    {
        Assert.True(new SelectedPlayer("abc", "Jane Q Public").IsValid);
        Assert.Equal("JQ", new SelectedPlayer("abc", "Jane Q Public").Initials);
        Assert.Equal("X", new SelectedPlayer("abc", "x").Initials);
        Assert.False(new SelectedPlayer("abc", " padded").IsValid);
        Assert.False(new SelectedPlayer("abc", "").IsValid);
        Assert.False(new SelectedPlayer("abc", "a\u0007").IsValid);
    }

    [Fact]
    public void FileStore_RoundTripsSelectedPlayerAcrossInstances()
    {
        var path = Path.Combine(directory, "settings.json");
        var store = new JsonFileSettingsStore(path);
        Assert.Equal(new AppSettings().SongSort, store.Load().SongSort);
        Assert.False(store.RecoveredFromCorruption);
        var saved = new AppSettings
        {
            SelectedPlayer = new SelectedPlayer("acc_1", "Player One"),
            SongSort = SongSortMode.Year,
            SongSortAscending = false,
            SongFilter = new SongFilter(Instrument.Drums, [2, 5]),
            VisibleInstruments = [Instrument.Lead, Instrument.Drums],
            ReduceMotion = true,
            DisableAnimatedArtwork = true,
            SaveData = true,
        };
        store.Save(saved);
        var loaded = new JsonFileSettingsStore(path).Load();
        Assert.Equal(saved.SelectedPlayer, loaded.SelectedPlayer);
        Assert.Equal(saved.SongFilter, loaded.SongFilter);
        Assert.Equal(saved.VisibleInstruments, loaded.VisibleInstruments);
        Assert.Equal((SongSortMode.Year, false, true, true, true),
            (loaded.SongSort, loaded.SongSortAscending, loaded.ReduceMotion, loaded.DisableAnimatedArtwork, loaded.SaveData));
        Assert.Contains("\"songSort\": \"Year\"", File.ReadAllText(path));
        Assert.False(File.Exists(path + ".tmp"));
    }

    [Theory]
    [InlineData("{ not json")]
    [InlineData("null")]
    public void FileStore_RecoversFromCorruptData(string content)
    {
        var path = Path.Combine(directory, "settings.json");
        Directory.CreateDirectory(directory);
        File.WriteAllText(path, content);
        var store = new JsonFileSettingsStore(path);
        var settings = store.Load();
        Assert.Equal(SongSortMode.Title, settings.SongSort);
        Assert.Equal(content == "null" ? false : true, store.RecoveredFromCorruption);
    }

    [Fact]
    public void FileStore_RejectsOversizedFile()
    {
        var path = Path.Combine(directory, "settings.json");
        Directory.CreateDirectory(directory);
        File.WriteAllText(path, new string(' ', 300_000), Encoding.UTF8);
        var store = new JsonFileSettingsStore(path);
        store.Load();
        Assert.True(store.RecoveredFromCorruption);
        Assert.EndsWith("settings.json", JsonFileSettingsStore.DefaultPath);
    }

    [Fact]
    public void InMemoryStore_CountsSaves()
    {
        var store = new InMemorySettingsStore();
        store.Save(new AppSettings { SaveData = true });
        Assert.True(store.Load().SaveData);
        Assert.Equal(1, store.SaveCount);
        Assert.False(store.RecoveredFromCorruption);
    }
}

public class LaunchAndBackgroundTests
{
    private static Func<string, string?> Env(params (string Key, string Value)[] values) =>
        key => values.FirstOrDefault(v => v.Key == key).Value;

    [Fact]
    public void Launch_ParsesFlagsOverEnvironment()
    {
        var options = LaunchOptions.Parse(
            ["--tab", "settings", "--route=/songs/s1/Solo_Bass?page=2", "--width", "1280", "--height", "9999", "--reduce-motion", "--no-art", "--auto-scroll", "--frame-stats", "--drift-fps", "30", "stray", "--perf-log", "C:/x.log"],
            Env(("FST_DEBUG_TAB", "songs"), ("FST_BASE_URL", "http://127.0.0.1:8765/")));
        Assert.Equal(AppSection.Settings, options.Tab);
        Assert.Equal(new AppRoute.SongLeaderboard("s1", Instrument.Bass, 2), options.Route);
        Assert.Equal(8765, options.BaseUri!.Port);
        Assert.Equal((1280, (int?)null), (options.Width!.Value, options.Height));
        Assert.True(options.ReduceMotion);
        Assert.True(options.NoArt);
        Assert.True(options.AutoScroll);
        Assert.True(options.FrameStats);
        Assert.Equal(30, options.DriftFps);
        Assert.Null(LaunchOptions.Parse(["--drift-fps", "999"], Env()).DriftFps);
        Assert.Null(options.AutoScrollSpeed);
        Assert.Null(options.AutoScrollSpan);
        Assert.Equal("C:/x.log", options.PerfLogPath);
        Assert.Single(options.Warnings);
    }

    [Fact]
    public void Launch_ControlLab_AcceptsKnownLabsOnly()
    {
        Assert.Equal("instrument-selector", LaunchOptions.Parse(["--control-lab", "Instrument-Selector"], Env()).ControlLab);
        Assert.Equal("instrument-selector", LaunchOptions.Parse([], Env(("FST_DEBUG_CONTROL_LAB", "instrument-selector"))).ControlLab);
        Assert.Equal("service-status", LaunchOptions.Parse(["--control-lab=Service-Status"], Env()).ControlLab);
        Assert.Null(LaunchOptions.Parse([], Env()).ControlLab);
        var unknown = LaunchOptions.Parse(["--control-lab=nope"], Env());
        Assert.Null(unknown.ControlLab);
        Assert.Contains(unknown.Warnings, w => w.Contains("nope"));
    }

    [Fact]
    public void Launch_AutoScrollSpeedImpliesAutoScrollAndIsBounded()
    {
        var slow = LaunchOptions.Parse(["--auto-scroll-speed", "40", "--auto-scroll-span=1200"], Env());
        Assert.True(slow.AutoScroll);
        Assert.Equal(40, slow.AutoScrollSpeed);
        Assert.Equal(1200, slow.AutoScrollSpan);
        var bad = LaunchOptions.Parse(["--auto-scroll-speed", "0", "--auto-scroll-span", "-5"], Env());
        Assert.False(bad.AutoScroll);
        Assert.Null(bad.AutoScrollSpeed);
        Assert.Null(bad.AutoScrollSpan);
        Assert.Null(LaunchOptions.Parse(["--auto-scroll-speed", "2001"], Env()).AutoScrollSpeed);
    }

    [Fact]
    public void Launch_RouteImpliesTabAndRejectsBadValues()
    {
        var fromEnv = LaunchOptions.Parse([], Env(("FST_DEBUG_ROUTE", "/rivals")));
        Assert.Equal(AppSection.Rivals, fromEnv.Tab);
        var bad = LaunchOptions.Parse(["--tab", "nope", "--route", "/manual", "--base-url", "https://evil.example/", "--width"], Env());
        Assert.Null(bad.Tab);
        Assert.Null(bad.Route);
        Assert.Null(bad.BaseUri);
        Assert.Equal(4, bad.Warnings.Count);
        Assert.Null(LaunchOptions.Parse([], Env()).PerfLogPath);
    }

    [Theory]
    [InlineData(true, true, false, false, false, false, ArtworkMode.Animated)]
    [InlineData(false, true, false, false, false, false, ArtworkMode.Static)]
    [InlineData(true, true, false, true, false, false, ArtworkMode.Static)]
    [InlineData(true, true, false, false, true, false, ArtworkMode.Static)]
    [InlineData(true, false, false, false, false, false, ArtworkMode.Paused)]
    [InlineData(true, true, true, false, false, false, ArtworkMode.Paused)]
    [InlineData(true, false, false, false, false, true, ArtworkMode.Hidden)]
    public void Policy_Resolves(bool animations, bool visible, bool occluded, bool reduce, bool disable, bool save, ArtworkMode mode) =>
        Assert.Equal(mode, ArtworkPlaybackPolicy.Resolve(new ArtworkPolicyInputs(animations, visible, occluded, reduce, disable, save)));

    [Theory]
    [InlineData(true, false, false, false, ArtworkMode.Paused)]
    [InlineData(false, false, false, false, ArtworkMode.Static)]
    [InlineData(true, true, false, false, ArtworkMode.Static)]
    [InlineData(true, false, true, false, ArtworkMode.Hidden)]
    [InlineData(true, false, false, true, ArtworkMode.Paused)]
    public void Policy_ModalHoldsTheFrameButKeepsStillAndHiddenModes(bool animations, bool reduce, bool save, bool occluded, ArtworkMode mode) =>
        Assert.Equal(mode, ArtworkPlaybackPolicy.Resolve(new ArtworkPolicyInputs(animations, true, occluded, reduce, false, save, ModalOpen: true)));

    [Fact]
    public void Carousel_ShufflesBoundsAndCycles()
    {
        var art = Enumerable.Range(0, 150).Select(i => (string?)$"a{i}.jpg").Append(null).Append(" ").Append("a1.jpg");
        var carousel = new ArtworkCarousel(art, new Random(1));
        Assert.Equal(ArtworkCarousel.MaxCovers, carousel.Covers.Count);
        Assert.Equal(carousel.Covers.Count, carousel.Covers.Distinct().Count());
        var first = carousel.Next()!.Value;
        Assert.Equal(carousel.Covers[0], first.Cover);
        Assert.Contains(first.Preset, ArtworkCarousel.Presets);
        for (var i = 1; i < 100; i++) carousel.Next();
        Assert.Equal(carousel.Covers[0], carousel.Next()!.Value.Cover);
    }

    [Fact]
    public void Carousel_StopsAfterFailureBudgetOrWhenEmpty()
    {
        Assert.True(new ArtworkCarousel([]).IsExhausted);
        Assert.Null(new ArtworkCarousel([]).Next());
        var carousel = new ArtworkCarousel(["a", "b"]);
        for (var i = 0; i < ArtworkCarousel.FailureBudget; i++)
        {
            Assert.NotNull(carousel.Next());
            carousel.ReportFailure();
        }
        Assert.True(carousel.IsExhausted);
    }

    [Fact]
    public void Carousel_PresetsStayWithinSpec()
    {
        Assert.Equal(10, ArtworkCarousel.Presets.Count);
        Assert.All(ArtworkCarousel.Presets, p =>
        {
            Assert.InRange(p.FromScale, 1.0, 1.18);
            Assert.InRange(p.ToScale, 1.0, 1.18);
            Assert.InRange(Math.Max(Math.Max(Math.Abs(p.FromX), Math.Abs(p.ToX)), Math.Max(Math.Abs(p.FromY), Math.Abs(p.ToY))), 0, 18);
        });
        // Web MOTION_PRESETS, drawn like CSS scale() translate(): the pan moves the scaled layer.
        Assert.Equal(new MotionPreset(1.18, 1.18, 18, 0, -18, 0), ArtworkCarousel.Presets[2]);
        Assert.Equal(21.24, ArtworkCarousel.Presets[2].VisualFrom.X, 6);
        Assert.Equal(16.52, ArtworkCarousel.Presets[7].VisualTo.Y, 6);
        Assert.Equal((5.0, 1.0, 6.0, 0.7), (ArtworkCarousel.Dwell.TotalSeconds, ArtworkCarousel.Crossfade.TotalSeconds, ArtworkCarousel.Drift.TotalSeconds, ArtworkCarousel.DimOpacity));
    }
}
