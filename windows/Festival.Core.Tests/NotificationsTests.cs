using System.Net;
using System.Text;
using System.Text.Json;
using Festival.Core.ViewModels;
using Microsoft.Extensions.Time.Testing;

namespace Festival.Core.Tests;

public class NotificationsTests
{
    private const string Account = "acct_1";
    private static readonly DateTimeOffset Now = new(2026, 9, 28, 12, 0, 0, TimeSpan.Zero);

    private static ImprovementNotification Item(string kind, string? song = "s1", string? instrument = "Solo_Guitar",
        double? oldN = null, double? newN = null, int? oldRank = null, int? newRank = null, string guid = "g1", string? metric = null,
        NotificationPayload? payload = null, DateTimeOffset? at = null) => new()
        {
            EventId = 1, NotificationGuid = guid, AccountId = Account, EventKind = kind, SongId = song, Instrument = instrument,
            OldNumeric = oldN, NewNumeric = newN, OldRank = oldRank, NewRank = newRank, Metric = metric, Payload = payload,
            DetectedAt = at ?? Now, ExpiresAt = Now.AddDays(3),
        };

    private static string ItemJson(string guid, string kind, string detected = "2026-09-28T11:00:00Z", string extra = "") =>
        $$"""{"eventId":1,"notificationGuid":"{{guid}}","accountId":"{{Account}}","eventKind":"{{kind}}","songId":"s1","instrument":"Solo_Guitar","oldRank":9,"newRank":4,"newNumeric":123456,"payload":{},"detectedAt":"{{detected}}","expiresAt":"2026-10-01T00:00:00Z"{{extra}}}""";

    private static string Envelope(string items, string source = "\"sourceRunId\":5,\"sourceCompletedAt\":\"2026-09-28T00:00:00Z\"") =>
        $$"""{"generatedAt":"2026-09-28T12:00:00Z","expiresAfterHours":72,{{source}},"items":[{{items}}]}""";

    #region Text
    public static TheoryData<string, string, string> Copy => new()
    {
        { "player_first_score", "Song · Lead", "Your first Lead play on Song scored 123,456 points and started at #4." },
        { "player_score_pb", "Song · Lead", "You set a new personal best on Lead for Song with 123,456 points." },
        { "player_song_rank_improved", "Song · Lead", "You climbed from #1,009 to #4 on Lead for Song." },
        { "player_stars_improved", "Song · Lead", "You improved from 5 to 123,456 stars on Lead for Song." },
        { "player_gold_stars_achieved", "Song · Lead", "You earned gold stars on Lead for Song." },
        { "player_fc_achieved", "Song · Lead", "You got a Full Combo on Lead for Song." },
        { "player_difficulty_bumped", "Song · Lead", "You improved your difficulty on Lead for Song from 5 to 123,456." },
        { "player_weighted_rank_improved", "Weighted Percentile Rank Improved", "You moved up from #1,009 to #4 in Lead percentile rankings, weighted by number of entries." },
        { "player_skill_rank_improved", "Adjusted Percentile Rank Improved", "You moved up from #1,009 to #4 in Lead adjusted percentile rankings." },
        { "player_total_score_rank_improved", "Total Score Rank Improved", "You moved up from #1,009 to #4 in Lead total score rankings." },
        { "player_fc_rate_rank_improved", "Full Combo Rank Improved", "You moved up from #1,009 to #4 in Lead Full Combo rankings." },
        { "player_max_score_rank_improved", "Max Score % Rank Improved", "You moved up from #1,009 to #4 in Lead max score rankings." },
        { "player_total_score_improved", "Total Score Improved", "Your Lead total score increased to 123,456 points." },
        { "player_fc_count_improved", "Full Combo Count Improved", "Your Lead Full Combo count increased to 123,456." },
        { "something_new", "Song", "New improvement detected." },
    };

    [Theory]
    [MemberData(nameof(Copy))]
    public void Text_PortsWebCopy(string kind, string title, string message)
    {
        var p = NotificationText.Format(Item(kind, oldN: 5, newN: 123456, oldRank: 1009, newRank: 4), "Song");
        Assert.Equal(title, p.Title);
        Assert.Equal(message, p.Message);
    }

    [Fact]
    public void Text_FallbacksWithoutValuesTitleOrInstrument()
    {
        var p = NotificationText.Format(Item("player_score_pb", instrument: "bogus"), null);
        Assert.Equal("Notification", p.Title);
        Assert.Equal("You set a new personal best on this instrument for this song with a new score points.", p.Message);
        Assert.Equal("You climbed from your new rank to your new rank on Lead for this song.",
            NotificationText.Format(Item("player_song_rank_improved"), " ").Message);
        Assert.Equal("You improved from more to more stars on Lead for this song.", NotificationText.Format(Item("player_stars_improved"), null).Message);
        Assert.Equal("1.5", NotificationText.Number(1.5, "x"));
        Assert.Equal("x", NotificationText.Number(double.NaN, "x"));
    }

    [Fact]
    public void Text_ShopSongUsesPayload()
    {
        var shop = Item("service_new_shop_song", instrument: null, payload: new NotificationPayload { SongTitle = " Hit ", Artist = "Band" });
        var p = NotificationText.Format(shop, "Catalogue");
        Assert.Equal("New Song · Hit - Band", p.Title);
        Assert.Equal("Hit by Band has been added to the Item Shop.", p.Message);
        Assert.Null(p.Flag);
        var bare = NotificationText.Format(shop with { Payload = null }, null);
        Assert.Equal("New Song · New Song - Unknown Artist", bare.Title);
        Assert.Equal(new NotificationDestination.Song("s1", null), bare.Destination);
    }

    [Theory]
    [InlineData("player_first_score", "First Play")]
    [InlineData("player_score_pb", "New High Score")]
    [InlineData("player_fc_achieved", "Full Combo")]
    [InlineData("player_song_rank_improved", "Rank Up")]
    [InlineData("player_gold_stars_achieved", "Gold Stars")]
    [InlineData("player_stars_improved", "Stars Up")]
    [InlineData("player_difficulty_bumped", "Difficulty Up")]
    [InlineData("player_fc_count_improved", "Progress")]
    [InlineData("player_total_score_improved", "Progress")]
    [InlineData("mystery", "Improvement")]
    public void Flags_MatchWeb(string kind, string flag) => Assert.Equal(flag, NotificationText.Flag(kind));
    #endregion

    #region Destination
    [Fact]
    public void Destination_SongRankingsOrNone()
    {
        Assert.Equal(new NotificationDestination.Song("s1", Instrument.Lead), NotificationRouting.Destination(Item("player_score_pb")));
        Assert.Equal(new NotificationDestination.Rankings("weighted"), NotificationRouting.Destination(Item("player_weighted_rank_improved", song: null)));
        Assert.Equal(new NotificationDestination.Rankings("maxscore"), NotificationRouting.Destination(Item("x", song: null, metric: "max_score_percent_rank")));
        Assert.Null(NotificationRouting.Destination(Item("player_total_score_improved", song: null)));
        Assert.Null(NotificationRouting.Destination(Item("player_score_pb", song: null)));
        var coalesced = Item("player_score_pb", payload: new NotificationPayload
        {
            CoalescedEvents = [new() { EventKind = "player_score_pb", Instrument = "Solo_Guitar" }, new() { EventKind = "player_fc_achieved", Instrument = "Solo_Bass" }, new()],
        });
        Assert.Equal(new NotificationDestination.Song("s1", null), NotificationRouting.Destination(coalesced));
    }

    [Theory]
    [InlineData("player_skill_rank_improved", null, "adjusted")]
    [InlineData("player_total_score_rank_improved", null, "totalscore")]
    [InlineData("player_fc_rate_rank_improved", null, "fcrate")]
    [InlineData(" ", "composite_rank", "adjusted")]
    [InlineData(null, "composite_rank_weighted", "weighted")]
    [InlineData(null, "composite_rank_total_score", "totalscore")]
    [InlineData(null, "composite_rank_fc_rate", "fcrate")]
    [InlineData(null, "composite_rank_max_score", "maxscore")]
    [InlineData(null, "skill_rank", "adjusted")]
    [InlineData(null, "adjusted_skill_rank", "adjusted")]
    [InlineData(null, "weighted_rank", "weighted")]
    [InlineData(null, "total_score_rank", "totalscore")]
    [InlineData(null, "fc_rate_rank", "fcrate")]
    [InlineData(null, "max_score_rank", "maxscore")]
    [InlineData("player_fc_achieved", "unknown", null)]
    [InlineData(null, null, null)]
    public void RankingMetric_Maps(string? kind, string? metric, string? expected) => Assert.Equal(expected, NotificationRouting.RankingMetric(kind, metric));
    #endregion

    #region Wire
    [Fact]
    public async Task Client_ReadsPinnedFeedWithoutProfileHeaders()
    {
        var service = new FakeService { Override = r => r.RequestUri!.AbsolutePath.EndsWith("/notifications", StringComparison.Ordinal)
            ? Wire.Ok(Envelope(ItemJson("g1", "player_score_pb")), ("X-FST-Publication-Id", "7")) : null };
        var feed = await service.Client().GetPlayerNotificationsAsync(Account, 20);
        Assert.True(feed.IsGenerated);
        Assert.Single(feed.Items!);
        Assert.Equal(Instrument.Lead, feed.Items![0].ParsedInstrument);
        var sent = service.Handler.To($"/api/player/{Account}/notifications").Single();
        Assert.Equal("?limit=20", sent.Uri.Query);
        Assert.DoesNotContain(sent.Headers.Keys, k => k.StartsWith("x-fst-selected", StringComparison.OrdinalIgnoreCase) || k.Equals("x-api-key", StringComparison.OrdinalIgnoreCase));
    }

    [Theory]
    [InlineData("bad id", 10)]
    [InlineData(Account, 0)]
    [InlineData(Account, 201)]
    public async Task Client_RejectsBadParameters(string account, int limit)
    {
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => new FakeService().Client().GetPlayerNotificationsAsync(account, limit));
        Assert.Equal(FestivalApiErrorKind.InvalidResource, error.Kind);
    }

    [Theory]
    [InlineData("{\"items\":null}")]
    [InlineData("not json")]
    [InlineData("null")]
    public async Task Client_RejectsMalformedEnvelope(string body)
    {
        var service = new FakeService { Override = r => r.RequestUri!.AbsolutePath.EndsWith("/notifications", StringComparison.Ordinal) ? Wire.Ok(body) : null };
        var error = await Assert.ThrowsAsync<FestivalApiException>(() => service.Client().GetPlayerNotificationsAsync(Account));
        Assert.Equal(FestivalApiErrorKind.InvalidResponse, error.Kind);
    }

    [Fact]
    public void Envelope_ValidatesRows()
    {
        ImprovementNotificationsEnvelope Env(params ImprovementNotification[] items) => new() { Items = items };
        Env(Item("k")).Validate(1);
        Assert.Throws<FestivalApiException>(() => Env(Item("k"), Item("k", guid: "g2")).Validate(1));
        Assert.Throws<FestivalApiException>(() => Env(Item("k"), Item("k")).Validate(5));
        Assert.Throws<FestivalApiException>(() => Env(Item("")).Validate(5));
        Assert.Throws<FestivalApiException>(() => Env(Item("k", guid: "")).Validate(5));
        Assert.Throws<FestivalApiException>(() => Env(Item("k", guid: "a‮b")).Validate(5));
        Assert.Throws<FestivalApiException>(() => Env(Item("k", song: "")).Validate(5));
        Assert.Throws<FestivalApiException>(() => Env(null!).Validate(5));
        Assert.False(new ImprovementNotificationsEnvelope { Items = [] }.IsGenerated);
        Assert.True(new ImprovementNotificationsEnvelope { Items = [], SourceCompletedAt = Now }.IsGenerated);
        Assert.True(new ImprovementNotificationsEnvelope { Items = [Item("k")] }.IsGenerated);
        Assert.False(new ImprovementNotificationsEnvelope { Items = [Item("k")], NotificationsGenerated = false }.IsGenerated);
    }
    #endregion

    #region Seen store
    [Fact]
    public void SeenStore_PerAccountIdempotentPrunedAndBounded()
    {
        var blob = new MemoryBlobStore();
        var store = new NotificationSeenStore(blob);
        Assert.Empty(store.Seen(Account));
        store.MarkSeen(Account, ["a", "b"]);
        store.MarkSeen(Account, ["a"]);
        Assert.Equal(1, blob.WriteCount);
        Assert.Equal(["a", "b"], store.Seen(Account).Order());
        Assert.Empty(store.Seen("other"));
        store.MarkSeen(Account, ["c"], currentFeed: ["b", "c"]);
        Assert.Equal(["b", "c"], store.Seen(Account).Order());
        store.MarkSeen(Account, Enumerable.Range(0, NotificationSeenStore.MaxPerAccount + 10).Select(i => $"id{i}"));
        Assert.Equal(NotificationSeenStore.MaxPerAccount, store.Seen(Account).Count);
        for (var i = 0; i < NotificationSeenStore.MaxAccounts + 2; i++) store.MarkSeen($"acct{i}", ["x"]);
        Assert.Empty(store.Seen(Account));
        Assert.Single(store.Seen($"acct{NotificationSeenStore.MaxAccounts + 1}"));
        Assert.EndsWith("notifications-seen.json", NotificationSeenStore.DefaultPath);
    }

    [Theory]
    [InlineData("garbage")]
    [InlineData("{\"acct_1\":[\"ok\",\"\"],\"bad id\":[\"x\"],\"n\":null}")]
    public void SeenStore_RecoversFromCorruptData(string json)
    {
        var blob = new MemoryBlobStore { Bytes = Encoding.UTF8.GetBytes(json) };
        var store = new NotificationSeenStore(blob);
        Assert.True(store.Seen(Account).Count <= 1);
        Assert.Empty(store.Seen("bad id"));
        blob.Bytes = new byte[600 * 1024];
        Assert.Empty(store.Seen(Account));
    }
    #endregion

    #region View model
    private sealed class Harness
    {
        public FakeService Service { get; } = new();
        public string Body { get; set; } = Envelope(ItemJson("g1", "player_score_pb", "2026-09-28T11:59:30Z") + "," +
            ItemJson("g2", "player_weighted_rank_improved", "2026-09-28T10:00:00Z") + "," + ItemJson("g3", "player_fc_count_improved", "2026-09-20T12:00:00Z"));
        public HttpStatusCode Status { get; set; } = HttpStatusCode.OK;
        public int Requests { get; private set; }
        public FakeTimeProvider Time { get; } = new(Now);
        public MemoryBlobStore Seen { get; } = new();

        public Harness()
        {
            Service.Override = r =>
            {
                if (!r.RequestUri!.AbsolutePath.EndsWith("/notifications", StringComparison.Ordinal)) return null;
                Requests++;
                return Wire.Response(Status, Body, ("X-FST-Publication-Id", "7"));
            };
        }

        public (FestivalSession Session, NotificationsViewModel Model) Create(bool player = true)
        {
            var settings = player ? new AppSettings { SelectedPlayer = new SelectedPlayer(Account, "Tester") } : null;
            var session = Service.Session(Time, settings);
            return (session, new NotificationsViewModel(session, new NotificationSeenStore(Seen)));
        }
    }

    [Fact]
    public async Task ViewModel_NoPlayerMakesNoRequest()
    {
        var h = new Harness();
        var (_, vm) = h.Create(player: false);
        Assert.True(vm.IsNoPlayer);
        await vm.RefreshAsync();
        Assert.Equal(NotificationsState.NoPlayer, vm.State);
        Assert.Equal(0, h.Requests);
        Assert.Equal("Notifications", vm.BellName);
        Assert.False(vm.HasUnread);
    }

    [Fact]
    public async Task ViewModel_LoadsUnreadThenMarksSeen()
    {
        var h = new Harness();
        var (session, vm) = h.Create();
        Assert.True(vm.IsLoading);
        await vm.RefreshAsync();
        Assert.True(vm.IsLoaded);
        Assert.Equal(3, vm.UnreadCount);
        Assert.Equal("3", vm.BadgeText);
        Assert.Equal("Notifications, 3 unread", vm.BellName);
        Assert.True(vm.HasNew);
        Assert.False(vm.HasOlder);
        Assert.Equal(["g1", "g2", "g3"], vm.NewItems.Select(r => r.Id));
        var first = vm.NewItems[0];
        Assert.Equal("Just now", first.TimeText);
        Assert.Equal("2h ago", vm.NewItems[1].TimeText);
        Assert.Equal("Sep 20", vm.NewItems[2].TimeText);
        Assert.Equal("Notification", first.Title);
        Assert.StartsWith("Unread. Notification.", first.AccessibleName);
        Assert.Equal("fst.notifications.row.g1", first.AutomationId);
        Assert.True(first.HasDestination && first.HasFlag);
        Assert.Equal("New High Score", first.Flag);

        Assert.Equal(new NotificationDestination.Song("s1", Instrument.Lead), vm.Activate(first));
        Assert.False(first.IsUnread);
        Assert.Equal(2, vm.UnreadCount);
        Assert.Equal("Notifications, 2 unread", vm.BellName);
        vm.Activate(first);
        Assert.Equal(2, vm.UnreadCount);

        Assert.Equal(new NotificationDestination.Rankings("weighted"), vm.Activate(vm.NewItems[1]));
        Assert.Equal("weighted", session.Settings.LeaderboardRankBy);
        Assert.Null(vm.Activate(vm.NewItems[2]));

        vm.MarkAllSeen();
        Assert.Equal(0, vm.UnreadCount);
        Assert.False(vm.HasNew);
        Assert.Equal(3, vm.OlderItems.Count);

        // A relaunch restores seen state.
        var (_, again) = h.Create();
        await again.RefreshAsync();
        Assert.Equal(0, again.UnreadCount);
    }

    [Fact]
    public async Task ViewModel_TitlesFromCatalogueAndRelativeTimes()
    {
        var h = new Harness();
        var (session, vm) = h.Create();
        await vm.RefreshAsync();
        await session.LoadCatalogAsync();
        await Async.Until(() => vm.NewItems[0].Title == "Alpha · Lead");
        Assert.Equal("1m ago", vm.RelativeTime(Now.AddMinutes(-1)));
        Assert.Equal("6d ago", vm.RelativeTime(Now.AddDays(-6)));
    }

    [Fact]
    public async Task ViewModel_EmptyVariants()
    {
        var h = new Harness { Body = Envelope("") };
        var (_, vm) = h.Create();
        await vm.RefreshAsync();
        Assert.True(vm.IsEmpty);
        Assert.StartsWith("Notifications will appear here when new high scores", vm.EmptyBody);
        Assert.Equal("No notifications available", vm.EmptyTitle);
        h.Body = Envelope("", "\"sourceRunId\":null");
        await vm.RefreshAsync();
        Assert.StartsWith("Notifications may appear here after the next leaderboard update", vm.EmptyBody);
        vm.MarkAllSeen();
    }

    [Fact]
    public async Task ViewModel_FailureRetryAndFailedRefreshKeepsFeed()
    {
        var h = new Harness { Status = HttpStatusCode.ServiceUnavailable };
        var (_, vm) = h.Create();
        await vm.RefreshAsync();
        Assert.True(vm.IsFailed);
        Assert.NotEmpty(vm.ErrorText);
        h.Status = HttpStatusCode.OK;
        await vm.RefreshCommand.ExecuteAsync(null);
        Assert.True(vm.IsLoaded);
        h.Status = HttpStatusCode.ServiceUnavailable;
        await vm.RefreshAsync();
        Assert.True(vm.IsLoaded);
        Assert.Equal(3, vm.UnreadCount);
    }

    [Fact]
    public async Task ViewModel_FollowsPlayerSelection()
    {
        var h = new Harness();
        var (session, vm) = h.Create(player: false);
        session.SelectPlayer(new PlayerSearchResult(Account, "Tester"));
        await Async.Until(() => vm.IsLoaded);
        Assert.Equal(1, h.Requests);
        session.UpdateSettings(s => s with { ReduceMotion = true });
        await Async.Settle();
        Assert.Equal(1, h.Requests);
        session.DeselectPlayer();
        await Async.Until(() => vm.IsNoPlayer);
        Assert.Equal(0, vm.UnreadCount);
        Assert.Empty(vm.NewItems);
    }

    [Fact]
    public async Task ViewModel_SwitchingPlayersClearsOldFeedAndBadgeCapsAt99()
    {
        var items = string.Join(",", Enumerable.Range(0, 50).Select(i => ItemJson($"g{i}", "player_fc_achieved")));
        var h = new Harness { Body = Envelope(items) };
        var (session, vm) = h.Create();
        await vm.RefreshAsync();
        Assert.Equal("50", vm.BadgeText);
        vm.UnreadCount = 120;
        Assert.Equal("99+", vm.BadgeText);
        session.SelectPlayer(new PlayerSearchResult("acct_2", "Other"));
        await Async.Until(() => vm.IsLoaded && h.Requests == 2);
        Assert.Equal(50, vm.UnreadCount);
    }

    [Fact]
    public void Row_NameWithoutUnread()
    {
        var row = new NotificationRowViewModel(new NotificationPresentation("x", "T", "M.", null, Now, null), false, "1h ago");
        Assert.Equal("T. M. 1h ago", row.AccessibleName);
        Assert.False(row.HasFlag);
        Assert.Equal("", row.Flag);
        Assert.False(row.HasDestination);
        Assert.Equal("x", row.Id);
        Assert.Equal("M.", row.Message);
        Assert.Null(row.Destination);
    }
    #endregion
}
