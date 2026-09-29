using System.Text;
using Festival.Core.ViewModels;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

// Ported from apple/Tests/FestivalCoreTests/FirstRunTests.swift, plus Windows center/carousel coverage.
public class FirstRunTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 28, 0, 0, 0, TimeSpan.Zero);

    private static FirstRunSlide Slide(string id = "slide", int version = 1, string title = "Title", string description = "Description",
        string? contentKey = null, FirstRunGate gate = FirstRunGate.Always) => new(id, version, title, description, contentKey, gate);

    private static Dictionary<string, FirstRunSeenRecord> Seen(params FirstRunSlide[] slides) =>
        slides.ToDictionary(s => s.Id, s => FirstRunSlideEvaluator.SeenRecord(s, Now));

    #region Hashing
    [Theory]
    [InlineData("", "1505")]
    [InlineData("a", "2b606")]
    [InlineData("abc", "b885c8b")]
    [InlineData("TD", "59755d")]
    [InlineData("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", "8d8bf385")]
    public void ContentHash_MatchesWebDjb2(string text, string expected) => Assert.Equal(expected, FirstRunHashing.ContentHash(text));

    [Fact]
    public void ContentHash_WrapsLikeJavaScriptAndDistinguishesContent()
    {
        // Long text exercises the 32-bit wraparound (JS `| 0` then `>>> 0`).
        var hash = FirstRunHashing.ContentHash(new string('z', 64));
        Assert.True(hash.Length <= 8);
        Assert.Equal(hash, FirstRunHashing.ContentHash(new string('z', 64)));
        Assert.NotEqual(FirstRunHashing.ContentHash("abc"), FirstRunHashing.ContentHash("abd"));
    }

    [Fact]
    public void ContentHash_UsesUtf16CodeUnitsLikeCharCodeAt()
    {
        // U+1F3B8 is two UTF-16 units in JS: hash of the surrogate pair, not of the scalar.
        var guitar = "\U0001F3B8";
        var manual = 5381u;
        foreach (var unit in new[] { (uint)0xD83C, (uint)0xDFB8 }) manual = unchecked((manual << 5) + manual + unit);
        Assert.Equal(manual.ToString("x"), FirstRunHashing.ContentHash(guitar));
    }
    #endregion

    #region IsUnseen
    [Fact]
    public void IsUnseen_MissingRecord() => Assert.True(FirstRunSlideEvaluator.IsUnseen(Slide(), new Dictionary<string, FirstRunSeenRecord>()));

    [Fact]
    public void IsUnseen_MatchingRecordIsSeen()
    {
        var target = Slide("s", 2, "T", "D");
        Assert.False(FirstRunSlideEvaluator.IsUnseen(target, Seen(target)));
    }

    [Fact]
    public void IsUnseen_VersionBump()
    {
        var old = Slide("s", 1, "T", "D");
        Assert.True(FirstRunSlideEvaluator.IsUnseen(Slide("s", 2, "T", "D"), Seen(old)));
    }

    [Fact]
    public void IsUnseen_LowerStoredVersionIsUnseen()
    {
        var seen = new Dictionary<string, FirstRunSeenRecord> { ["s"] = new(0, FirstRunHashing.ContentHash("TD"), Now) };
        Assert.True(FirstRunSlideEvaluator.IsUnseen(Slide("s", 3, "T", "D"), seen));
    }

    [Fact]
    public void IsUnseen_HigherStoredVersionWithSameHashIsSeen()
    {
        // Strictly `>`: a stored version above the slide's (downgrade) does not replay.
        var seen = new Dictionary<string, FirstRunSeenRecord> { ["s"] = new(9, FirstRunHashing.ContentHash("TD"), Now) };
        Assert.False(FirstRunSlideEvaluator.IsUnseen(Slide("s", 3, "T", "D"), seen));
    }

    [Fact]
    public void IsUnseen_ContentChange()
    {
        var original = Slide("s", 1, "Old Title", "D");
        Assert.True(FirstRunSlideEvaluator.IsUnseen(Slide("s", 1, "New Title", "D"), Seen(original)));
    }

    [Fact]
    public void IsUnseen_ContentKeySharesSeenState()
    {
        var mobile = Slide("s", 1, "Same title", "Mobile copy", "shared-key");
        var desktop = Slide("s", 1, "Same title", "Desktop copy", "shared-key");
        Assert.False(FirstRunSlideEvaluator.IsUnseen(desktop, Seen(mobile)));
    }
    #endregion

    #region Selection
    [Fact]
    public void Gate_HidesFailingSlide() =>
        Assert.Empty(FirstRunSlideEvaluator.UnseenSlides([Slide("g", gate: FirstRunGate.HasPlayer)], new FirstRunGateContext(), Seen()));

    [Theory]
    [InlineData(FirstRunGate.Always, false, false, false, true)]
    [InlineData(FirstRunGate.HasPlayer, true, false, false, true)]
    [InlineData(FirstRunGate.HasPlayer, false, true, true, false)]
    [InlineData(FirstRunGate.ShopHighlightEnabled, false, true, false, true)]
    [InlineData(FirstRunGate.ShopHighlightEnabled, true, false, true, false)]
    [InlineData(FirstRunGate.ExperimentalRanksEnabled, false, false, true, true)]
    [InlineData(FirstRunGate.ExperimentalRanksEnabled, true, true, false, false)]
    public void Gates_Evaluate(FirstRunGate gate, bool player, bool shop, bool experimental, bool expected) =>
        Assert.Equal(expected, gate.Passes(new FirstRunGateContext(player, shop, experimental)));

    [Fact]
    public void Selection_GatePassingUnseenIsReturned() =>
        Assert.Equal(["g"], FirstRunSlideEvaluator.UnseenSlides([Slide("g", gate: FirstRunGate.HasPlayer)],
            new FirstRunGateContext(HasPlayer: true), Seen()).Select(s => s.Id));

    [Fact]
    public void Selection_NotReadySuppressesAll() =>
        Assert.Empty(FirstRunSlideEvaluator.UnseenSlides([Slide("fresh")], new FirstRunGateContext(Ready: false), Seen()));

    [Fact]
    public void Selection_OnlyNewSlideShowsOnDismissedPage()
    {
        var existing = Slide("existing", 1, "Existing", "D");
        var brandNew = Slide("brand-new", 1, "New", "D2");
        Assert.Equal(["brand-new"], FirstRunSlideEvaluator.UnseenSlides([existing, brandNew], new FirstRunGateContext(), Seen(existing)).Select(s => s.Id));
    }

    [Fact]
    public void Selection_AlwaysShowBypassesSeenStateButKeepsGates()
    {
        var seenAlways = Slide("seen-always");
        var gatedOff = Slide("gated-off", gate: FirstRunGate.HasPlayer);
        var result = FirstRunSlideEvaluator.UnseenSlides([seenAlways, gatedOff], new FirstRunGateContext(AlwaysShow: true), Seen(seenAlways));
        Assert.Equal(["seen-always"], result.Select(s => s.Id));
    }

    [Fact]
    public void Selection_GatePassingAndAll()
    {
        Assert.Equal(["seen"], FirstRunSlideEvaluator.GatePassingSlides([Slide("seen")], new FirstRunGateContext()).Select(s => s.Id));
        Assert.Empty(FirstRunSlideEvaluator.GatePassingSlides([Slide("g", gate: FirstRunGate.ShopHighlightEnabled)], new FirstRunGateContext()));
        Assert.Equal(["g"], FirstRunSlideEvaluator.AllSlides([Slide("g", gate: FirstRunGate.HasPlayer)]).Select(s => s.Id));
    }
    #endregion

    #region Store
    private static (FirstRunSeenStore Store, MemoryBlobStore Blob) FreshStore()
    {
        var blob = new MemoryBlobStore();
        return (new FirstRunSeenStore(blob), blob);
    }

    [Fact]
    public void Store_FreshIsEmpty() => Assert.Empty(FreshStore().Store.Load());

    [Fact]
    public void Store_MarkSeenPersists()
    {
        var (store, _) = FreshStore();
        store.MarkSeen([Slide("s", 2, "T", "D")], Now);
        var record = store.Load()["s"];
        Assert.Equal(new FirstRunSeenRecord(2, FirstRunHashing.ContentHash("TD"), Now), record);
    }

    [Fact]
    public void Store_MarkSeenEmptyIsNoOp()
    {
        var (store, blob) = FreshStore();
        store.MarkSeen([], Now);
        Assert.Equal(0, blob.WriteCount);
    }

    [Fact]
    public void Store_SaveLoadRoundTripAndResets()
    {
        var (store, _) = FreshStore();
        store.Save(new Dictionary<string, FirstRunSeenRecord> { ["a"] = new(1, "h1", Now), ["b"] = new(2, "h2", Now) });
        Assert.Equal(2, store.Load().Count);
        store.ResetPage(["b"]);
        Assert.Equal(["a"], store.Load().Keys);
        store.ResetPage([]);
        store.ResetAll();
        Assert.Empty(store.Load());
    }

    [Theory]
    [InlineData("not json at all {{{")]
    [InlineData("[1,2,3]")]
    [InlineData("{\"a\":{\"version\":\"x\"}}")]
    public void Store_CorruptRecoversToEmpty(string json)
    {
        var (store, blob) = FreshStore();
        blob.Bytes = Encoding.UTF8.GetBytes(json);
        Assert.Empty(store.Load());
    }

    [Fact]
    public void Store_OversizedRejected()
    {
        var (store, blob) = FreshStore();
        blob.Bytes = new byte[FirstRunSeenStore.MaxBytes + 1];
        Assert.Empty(store.Load());
    }

    [Fact]
    public void Store_MalformedRecordsDroppedIndividually()
    {
        var (store, blob) = FreshStore();
        var longId = new string('x', 201);
        blob.Bytes = Encoding.UTF8.GetBytes($$"""
            {
              "valid": {"version": 1, "hash": "abc", "seenAt": "2024-01-01T00:00:00Z"},
              "negative-version": {"version": -1, "hash": "abc", "seenAt": "2024-01-01T00:00:00Z"},
              "empty-hash": {"version": 1, "hash": "", "seenAt": "2024-01-01T00:00:00Z"},
              "missing-hash": {"version": 1, "seenAt": "2024-01-01T00:00:00Z"},
              "long-hash": {"version": 1, "hash": "{{new string('a', 33)}}", "seenAt": "2024-01-01T00:00:00Z"},
              "{{longId}}": {"version": 1, "hash": "abc", "seenAt": "2024-01-01T00:00:00Z"},
              "null": null
            }
            """);
        Assert.Equal(["valid"], store.Load().Keys);
    }

    [Fact]
    public void Store_BoundedKeepingMostRecent()
    {
        var (store, _) = FreshStore();
        var storage = Enumerable.Range(0, FirstRunSeenStore.MaxRecords + 5)
            .ToDictionary(i => $"slide-{i}", i => new FirstRunSeenRecord(1, "h", Now.AddSeconds(i)));
        store.Save(storage);
        store.MarkSeen([Slide("newest")], Now.AddDays(1));
        var loaded = store.Load();
        Assert.Equal(FirstRunSeenStore.MaxRecords, loaded.Count);
        Assert.DoesNotContain("slide-0", loaded.Keys);
        Assert.Contains("newest", loaded.Keys);
        Assert.Contains($"slide-{FirstRunSeenStore.MaxRecords + 4}", loaded.Keys);
    }

    [Fact]
    public void FileBlob_RoundTripsDeletesAndIgnoresOversized()
    {
        var folder = Path.Combine(Path.GetTempPath(), "fst-blob-" + Guid.NewGuid().ToString("N"));
        try
        {
            var blob = new FileBlobStore(Path.Combine(folder, "x.json"), maxBytes: 4);
            Assert.Null(blob.Read());
            blob.Write([1, 2, 3]);
            Assert.Equal([1, 2, 3], blob.Read());
            blob.Write([1, 2, 3, 4, 5]);
            Assert.Null(blob.Read());
            blob.Write(null);
            Assert.Null(blob.Read());
            blob.Write(null);
            Assert.EndsWith("FestivalScoreTracker", FileBlobStore.AppDataFolder);
            Assert.EndsWith("first-run.json", FirstRunSeenStore.DefaultPath);
        }
        finally
        {
            if (Directory.Exists(folder)) Directory.Delete(folder, true);
        }
    }

    [Fact]
    public void FileBlob_WriteFailureIsSwallowed()
    {
        var folder = Path.Combine(Path.GetTempPath(), "fst-blob-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(folder, "dir.json"));
        try
        {
            // The target is a directory: the replace fails and the write is dropped.
            var blob = new FileBlobStore(Path.Combine(folder, "dir.json"));
            blob.Write([1]);
            Assert.Null(blob.Read());
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }
    #endregion

    #region Catalog and routing
    [Fact]
    public void Catalog_EveryPageHasUniqueSlides()
    {
        var all = Enum.GetValues<FirstRunPageKey>().SelectMany(FirstRunCatalog.Slides).ToList();
        Assert.All(Enum.GetValues<FirstRunPageKey>(), p => Assert.NotEmpty(FirstRunCatalog.Slides(p)));
        Assert.Equal(all.Count, all.Select(s => s.Id).Distinct().Count());
        Assert.Equal(42, all.Count);
        Assert.Equal(9, FirstRunCatalog.Songs.Length);
    }

    [Fact]
    public void Catalog_GatesMatchWeb()
    {
        string[] shop = ["songs-shop-highlight", "songs-new-in-shop", "songs-leaving-tomorrow", "shop-highlighting", "shop-new-items", "shop-leaving-tomorrow"];
        string[] player = ["songs-filter", "songs-icons", "songs-metadata", "songinfo-chart", "songinfo-bar-select", "songinfo-view-all", "leaderboards-your-rank", "compete-rivals"];
        var all = Enum.GetValues<FirstRunPageKey>().SelectMany(FirstRunCatalog.Slides).ToDictionary(s => s.Id);
        Assert.All(shop, id => Assert.Equal(FirstRunGate.ShopHighlightEnabled, all[id].Gate));
        Assert.All(player, id => Assert.Equal(FirstRunGate.HasPlayer, all[id].Gate));
        Assert.Equal(FirstRunGate.ExperimentalRanksEnabled, all["leaderboards-experimental-metrics"].Gate);
        Assert.Equal(15, all.Values.Count(s => s.Gate != FirstRunGate.Always));
    }

    [Fact]
    public void Catalog_DesktopVariantsKeepWebContentKeys()
    {
        string[] keyed = ["songs-navigation", "songinfo-paths", "songinfo-shop-button", "songinfo-new-in-shop", "songinfo-leaving-tomorrow", "playerhistory-sort", "statistics-select-profile"];
        var all = Enum.GetValues<FirstRunPageKey>().SelectMany(FirstRunCatalog.Slides).ToDictionary(s => s.Id);
        Assert.All(keyed, id => Assert.Equal(id, all[id].ContentKey));
        Assert.Contains("sidebar", all["songs-navigation"].Description, StringComparison.Ordinal);
    }

    [Fact]
    public void PageKeys_MatchWebStringsAndLabels()
    {
        Assert.Equal(["songs", "songinfo", "playerhistory", "statistics", "suggestions", "leaderboards", "compete", "rivals", "shop"],
            Enum.GetValues<FirstRunPageKey>().Select(p => p.Key()));
        Assert.Equal(["Songs", "Song Info", "Player History", "Statistics", "Suggestions", "Leaderboards", "Compete", "Rivals", "Item Shop"],
            Enum.GetValues<FirstRunPageKey>().Select(p => p.Label()));
    }

    public static TheoryData<AppSection, AppRoute?, FirstRunPageKey?> RouteCases => new()
    {
        { AppSection.Songs, null, FirstRunPageKey.Songs },
        { AppSection.Suggestions, null, FirstRunPageKey.Suggestions },
        { AppSection.Leaderboards, null, FirstRunPageKey.Leaderboards },
        { AppSection.Rivals, null, FirstRunPageKey.Rivals },
        { AppSection.Statistics, null, FirstRunPageKey.Statistics },
        { AppSection.Shop, null, FirstRunPageKey.Shop },
        { AppSection.Settings, null, null },
        { AppSection.Songs, new AppRoute.SongDetail("s"), FirstRunPageKey.SongInfo },
        { AppSection.Songs, new AppRoute.PlayerHistory("s", Instrument.Lead), FirstRunPageKey.PlayerHistory },
        { AppSection.Statistics, new AppRoute.Statistics(), FirstRunPageKey.Statistics },
        { AppSection.Suggestions, new AppRoute.Suggestions(), FirstRunPageKey.Suggestions },
        { AppSection.Leaderboards, new AppRoute.Leaderboards(), FirstRunPageKey.Leaderboards },
        { AppSection.Rivals, new AppRoute.Compete(), FirstRunPageKey.Compete },
        { AppSection.Rivals, new AppRoute.Rivals(), FirstRunPageKey.Rivals },
        { AppSection.Songs, new AppRoute.Shop(), FirstRunPageKey.Shop },
        { AppSection.Songs, new AppRoute.SongLeaderboard("s", Instrument.Lead), null },
        { AppSection.Settings, new AppRoute.Licenses(), null },
    };

    [Theory]
    [MemberData(nameof(RouteCases))]
    public void Pages_MapRoutes(AppSection section, AppRoute? route, FirstRunPageKey? expected) =>
        Assert.Equal(expected, FirstRunPages.For(section, route));
    #endregion

    #region Mode
    [Theory]
    [InlineData(new string[0], null, true, FirstRunMode.Off)]
    [InlineData(new string[0], null, false, FirstRunMode.Normal)]
    [InlineData(new string[0], "FORCE", true, FirstRunMode.Force)]
    [InlineData(new string[0], "on", true, FirstRunMode.Normal)]
    [InlineData(new[] { "--first-run", "off" }, "force", false, FirstRunMode.Off)]
    [InlineData(new[] { "--first-run=force" }, null, false, FirstRunMode.Force)]
    [InlineData(new[] { "--first-run" }, null, false, FirstRunMode.Normal)]
    [InlineData(new[] { "--first-run", "bogus" }, null, true, FirstRunMode.Off)]
    public void Mode_Parses(string[] args, string? env, bool debug, FirstRunMode expected) =>
        Assert.Equal(expected, FirstRunModeParser.Parse(args, _ => env, debug));
    #endregion

    #region Center and carousel
    private static FirstRunCenter Center(FirstRunMode mode = FirstRunMode.Normal, FakeTimeProvider? time = null) =>
        new(new FirstRunSeenStore(new MemoryBlobStore()), mode, time);

    [Fact]
    public void Center_ShowsUnseenOnceThenNothing()
    {
        var time = new FakeTimeProvider(Now);
        var center = Center(time: time);
        var carousel = center.TryBegin(FirstRunPageKey.Songs, new AppSettings());
        Assert.NotNull(carousel);
        Assert.Equal(["songs-song-list", "songs-sort", "songs-navigation", "songs-shop-highlight", "songs-new-in-shop", "songs-leaving-tomorrow"],
            carousel.Slides.Select(s => s.Id));
        Assert.Null(center.TryBegin(FirstRunPageKey.SongInfo, new AppSettings()));
        carousel.GoTo(carousel.Slides.Count - 1);
        carousel.Complete();
        carousel.Complete();
        Assert.Null(center.Active);
        Assert.Equal(Now, center.Store.Load()["songs-song-list"].SeenAt);
        Assert.Equal(Now, center.Store.Load()["songs-leaving-tomorrow"].SeenAt);
        // Jumping straight to the last slide skipped the middle ones: they stay unseen and come back.
        Assert.False(center.Store.Load().ContainsKey("songs-sort"));
        Assert.Equal(["songs-sort", "songs-navigation", "songs-shop-highlight", "songs-new-in-shop"],
            center.TryBegin(FirstRunPageKey.Songs, new AppSettings())!.Slides.Select(s => s.Id));
        center.Active!.GoTo(3);
        center.Active.GoTo(0);
        center.Active.GoTo(1);
        center.Active.GoTo(2);
        center.Active.Complete();
        Assert.Null(center.TryBegin(FirstRunPageKey.Songs, new AppSettings()));

        // Selecting a player later reveals only the newly eligible player slides.
        var player = new AppSettings { SelectedPlayer = new SelectedPlayer("abc", "P") };
        Assert.Equal(["songs-filter", "songs-icons", "songs-metadata"], center.TryBegin(FirstRunPageKey.Songs, player)!.Slides.Select(s => s.Id));
    }

    [Fact]
    public void Center_ContextFollowsSettingsAndShopOverride()
    {
        var center = Center(FirstRunMode.Force);
        var settings = new AppSettings { HideShop = true, SelectedPlayer = new SelectedPlayer("abc", "P") };
        Assert.Equal(new FirstRunGateContext(true, false, false, true, true), center.Context(FirstRunPageKey.Songs, settings));
        Assert.Equal(new FirstRunGateContext(false, true, false, true, true), center.Context(FirstRunPageKey.Shop, settings));
        Assert.Equal(4, center.PendingSlides(FirstRunPageKey.Shop, settings).Count);
    }

    [Fact]
    public void Center_ForceIgnoresSeenAndOffShowsNothing()
    {
        var force = Center(FirstRunMode.Force);
        force.TryBegin(FirstRunPageKey.Rivals, new AppSettings())!.Complete();
        Assert.NotNull(force.TryBegin(FirstRunPageKey.Rivals, new AppSettings()));

        var off = Center(FirstRunMode.Off);
        Assert.Empty(off.PendingSlides(FirstRunPageKey.Songs, new AppSettings()));
        Assert.Null(off.TryBegin(FirstRunPageKey.Songs, new AppSettings()));
        Assert.Equal(FirstRunMode.Off, off.Mode);
    }

    [Fact]
    public void Center_ReplayShowsEverySlideAndRemarksSeen()
    {
        var center = Center(FirstRunMode.Off);
        center.Store.MarkSeen(FirstRunCatalog.Leaderboards, Now);
        var replay = center.BeginReplay(FirstRunPageKey.Leaderboards);
        Assert.NotNull(replay);
        Assert.True(replay.IsReplay);
        Assert.Equal(3, replay.Slides.Count);
        Assert.Empty(center.Store.Load());
        Assert.Null(center.BeginReplay(FirstRunPageKey.Songs));
        replay.Next();
        replay.Complete();
        // Only the two slides reached before closing count as seen.
        Assert.Equal(2, center.Store.Load().Count);
    }

    [Fact]
    public void Carousel_PagesAndCompletesOnDone()
    {
        var center = Center();
        var carousel = center.BeginReplay(FirstRunPageKey.PlayerHistory)!;
        var changes = new List<string?>();
        carousel.PropertyChanged += (_, e) => changes.Add(e.PropertyName);
        Assert.Equal("Player History", carousel.Title);
        Assert.False(carousel.IsSingle);
        Assert.Equal(["playerhistory-score-list"], carousel.ViewedSlides.Select(s => s.Id));
        Assert.Equal(FirstRunPageKey.PlayerHistory, carousel.Page);
        Assert.True(carousel.IsFirst);
        Assert.False(carousel.PreviousCommand.CanExecute(null));
        Assert.Equal("Slide 1 of 2", carousel.PositionText);
        Assert.Equal("Next", carousel.NextLabel);
        Assert.Equal("playerhistory-score-list", carousel.Current.Id);

        Assert.False(carousel.Next());
        Assert.True(carousel.IsLast);
        Assert.Equal("Done", carousel.NextLabel);
        Assert.Equal("Slide 2 of 2", carousel.PositionText);
        Assert.True(carousel.PreviousCommand.CanExecute(null));
        Assert.Contains(nameof(FirstRunCarouselViewModel.PositionText), changes);
        Assert.Contains(nameof(FirstRunCarouselViewModel.PositionAnnouncement), changes);
        Assert.Equal($"{carousel.Current.Title}, slide 2 of 2", carousel.PositionAnnouncement);

        carousel.PreviousCommand.Execute(null);
        Assert.Equal(0, carousel.Index);
        carousel.GoTo(99);
        Assert.Equal(1, carousel.Index);
        carousel.GoTo(-5);
        Assert.Equal(0, carousel.Index);
        carousel.GoTo(1);

        Assert.True(carousel.Next());
        Assert.True(carousel.IsCompleted);
        Assert.Null(center.Active);
        Assert.Equal(2, center.Store.Load().Count);
    }
    [Fact]
    public void Carousel_SingleSlideAndClosingOnFirstSlide()
    {
        var center = Center();
        // Anonymous Leaderboards has one gate-passing slide: the dialog offers only Done.
        var single = center.TryBegin(FirstRunPageKey.Leaderboards, new AppSettings())!;
        Assert.True(single.IsSingle);
        Assert.True(single.IsLast);
        Assert.True(single.Next());
        Assert.Single(center.Store.Load());

        // Closing (Esc or a click outside) on the first of two slides marks only that slide.
        var replay = center.BeginReplay(FirstRunPageKey.PlayerHistory)!;
        replay.Complete();
        Assert.True(center.Store.Load().ContainsKey("playerhistory-score-list"));
        Assert.False(center.Store.Load().ContainsKey(replay.Slides[1].Id));
    }

    #endregion
}
