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
    public void Format_LeadingMediaIsSongArtElseTheInstrument()
    {
        var song = NotificationText.Format(Item("player_score_pb"), "Song", "art.jpg");
        Assert.Equal(("art.jpg", (Instrument?)null), (song.AlbumArt, song.MediaInstrument));
        var rank = NotificationText.Format(Item("player_total_score_rank_improved"), null);
        Assert.Null(rank.AlbumArt);
        Assert.NotNull(rank.MediaInstrument);
        var row = new NotificationRowViewModel(rank, true, "1h ago");
        Assert.False(row.HasArt);
        Assert.True(row.HasMediaIcon);
        Assert.EndsWith(".png", row.MediaIconFile, StringComparison.Ordinal);
        var songRow = new NotificationRowViewModel(song, false, "1h ago");
        Assert.True(songRow.HasArt);
        Assert.False(songRow.HasMediaIcon);
        Assert.Equal("art.jpg", songRow.Art);
        Assert.Null(NotificationText.Format(Item("player_score_pb"), "Song", " ").AlbumArt);
    }

    [Fact]
    public void Media_MultiChartRowsShowArtAboveAnInstrumentGrid()
    {
        var coalesced = Item("player_score_pb", payload: new NotificationPayload
        {
            CoalescedEvents = [new() { EventKind = "player_score_pb", Instrument = "Solo_Drums" }, new() { EventKind = "player_fc_achieved", Instrument = "Solo_Bass" }],
            CoalescedInstruments = ["Solo_PeripheralGuitar", "bogus", "Solo_Bass"],
        });
        Assert.Equal([Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.ProLead], NotificationMediaRules.SurfaceInstruments(coalesced));
        var grid = NotificationText.Format(coalesced, "Song", "art.jpg");
        Assert.Equal(NotificationMediaKind.SongInstrumentGrid, grid.MediaKind);
        var row = new NotificationRowViewModel(grid, false, "1h ago");
        Assert.True(row.HasGrid);
        Assert.Equal(44, row.ArtSize);
        Assert.Equal(["instrument_guitar.png", "instrument_bass.png", "instrument_drums.png", "instrument_pro_guitar.png"], row.GridIconFiles);
        // Narrator hears the grid's charts (web aria-label "Affected instruments: …"); the dot/chevron column shows for links.
        Assert.Contains($". Affected instruments: {Instrument.Lead.Label()}, {Instrument.Bass.Label()}, {Instrument.Drums.Label()}, {Instrument.ProLead.Label()}. ", row.AccessibleName);
        Assert.EndsWith("1h ago", row.AccessibleName);
        Assert.Equal(row.HasDestination, row.HasTrailing);
        row.IsUnread = true;
        Assert.True(row.HasTrailing);

        var single = new NotificationRowViewModel(NotificationText.Format(Item("player_score_pb"), "Song", "art.jpg"), false, "1h ago");
        Assert.Equal((NotificationMediaKind.Song, 54d, false), (single.MediaKind, single.ArtSize, single.HasGrid));
        Assert.Empty(single.GridIconFiles);
        Assert.Equal("", single.AffectedInstrumentsText);

        // Without art the rail shows the row's instrument (Lead when it names none), never a grid.
        var noArt = NotificationText.Format(coalesced, "Song");
        Assert.Equal((NotificationMediaKind.SoloInstrument, (Instrument?)Instrument.Lead), (noArt.MediaKind, noArt.MediaInstrument));
        Assert.Empty(noArt.GridInstruments);
        Assert.Equal(Instrument.Lead, NotificationText.Format(Item("player_total_score_improved", instrument: null), null).MediaInstrument);
        Assert.Equal(Instrument.Bass, NotificationText.Format(Item("player_total_score_improved", instrument: "Solo_Bass"), null).MediaInstrument);
    }

    [Fact]
    public void Media_ShopSongPrefersCatalogueArtThenPayloadArtElseLead()
    {
        var shop = Item("service_new_shop_song", instrument: null, payload: new NotificationPayload { SongTitle = "Hit", Artist = "Band", AlbumArt = "shop.jpg" });
        Assert.Equal("cat.jpg", NotificationText.Format(shop, null, "cat.jpg").AlbumArt);
        var payloadArt = NotificationText.Format(shop, null);
        Assert.Equal((NotificationMediaKind.Song, "shop.jpg"), (payloadArt.MediaKind, payloadArt.AlbumArt));
        var bare = NotificationText.Format(shop with { Payload = null }, null);
        Assert.Equal((NotificationMediaKind.SoloInstrument, (Instrument?)Instrument.Lead), (bare.MediaKind, bare.MediaInstrument));
        Assert.Equal([new("Hit", true), new(" by "), new("Band", true), new(" has been added to the Item Shop.")], payloadArt.Parts);
        Assert.Empty(payloadArt.Flags);
    }

    public static TheoryData<string, string[]> Emphasis => new()
    {
        { "player_first_score", ["Lead", "Song", "123,456", "#4"] },
        { "player_score_pb", ["Lead", "Song", "123,456"] },
        { "player_song_rank_improved", ["#1,009", "#4", "Lead", "Song"] },
        { "player_stars_improved", ["5 to 123,456 stars", "Lead", "Song"] },
        { "player_gold_stars_achieved", ["gold stars", "Lead", "Song"] },
        { "player_fc_achieved", ["Full Combo", "Lead", "Song"] },
        { "player_difficulty_bumped", ["Lead", "Song", "5", "123,456"] },
        { "player_weighted_rank_improved", ["#1,009", "#4", "Lead"] },
        { "player_total_score_improved", ["Lead", "123,456"] },
        { "player_fc_count_improved", ["Lead", "123,456"] },
        { "something_new", [] },
    };

    [Theory]
    [MemberData(nameof(Emphasis))]
    public void Text_BoldsTheWebsValues(string kind, string[] bold)
    {
        var p = NotificationText.Format(Item(kind, oldN: 5, newN: 123456, oldRank: 1009, newRank: 4), "Song");
        Assert.Equal(p.Message, string.Concat(p.Parts.Select(x => x.Text)));
        Assert.Equal(bold, p.Parts.Where(x => x.Emphasis).Select(x => x.Text));
        Assert.Equal(p.Parts, new NotificationRowViewModel(p, true, "now").MessageParts);
    }

    [Fact]
    public void Text_NeverBoldsFallbackWording()
    {
        var p = NotificationText.Format(Item("player_song_rank_improved", instrument: null), null);
        Assert.Equal("You climbed from your new rank to your new rank on this instrument for this song.", p.Message);
        Assert.DoesNotContain(p.Parts, x => x.Emphasis);
        Assert.Equal([new("plain")], NotificationText.Emphasize("plain", ["", "  ", "absent"]));
        Assert.Equal([new("a "), new("bc", true), new(" "), new("b", true)], NotificationText.Emphasize("a bc b", ["b", "bc"]));
        Assert.Equal([new("ab", true)], NotificationText.Emphasize("ab", ["a", "b"]));
        Assert.Equal("x", new NotificationPresentation("i", "t", "x", Now, null).Parts.Single().Text);
    }

    [Fact]
    public void Flags_UseTheWebsColours()
    {
        var kinds = Enum.GetValues<NotificationFlagKind>();
        Assert.Equal(kinds.Length, kinds.Select(k => k.Argb()).Distinct().Count());
        Assert.All(kinds, k => Assert.Equal(0xFFu, k.Argb() >> 24));
        Assert.Equal(0xFF0F766Eu, NotificationFlagKind.NewHighScore.Argb());
        Assert.Equal(0xFF4B5563u, NotificationFlagKind.Improvement.Argb());
        var pb = NotificationText.Format(Item("player_score_pb"), "Song");
        Assert.Equal([NotificationFlagKind.NewHighScore], pb.Flags);
        Assert.Empty(pb.FlagGroups);
        var row = new NotificationRowViewModel(pb, true, "1h ago");
        Assert.Equal("New High Score", row.FlagsText);
        Assert.Equal("Unread. Song · Lead. You set a new personal best on Lead for Song with a new score points. New High Score. 1h ago", row.AccessibleName);
    }

    #region Coalesced events (web notificationText.test.ts)
    private static NotificationEventPayload Ev(string kind, string? instrument = null, double? oldN = null, double? newN = null,
        double? oldRank = null, double? newRank = null, string? metric = null) =>
        new() { EventKind = kind, Instrument = instrument, OldNumeric = oldN, NewNumeric = newN, OldRank = oldRank, NewRank = newRank, Metric = metric };

    private static string[] Bold(NotificationPresentation p) => p.Parts.Where(x => x.Emphasis).Select(x => x.Text).ToArray();

    [Fact]
    public void Coalesced_MultiChartRowsListEachChartWithGroupedFlags()
    {
        var item = Item("player_score_pb", instrument: "Solo_Guitar", oldN: 210000, newN: 230891, payload: new NotificationPayload
        {
            CoalescedEvents =
            [
                Ev("player_song_rank_improved", "Solo_Guitar", oldRank: 180, newRank: 160),
                Ev("player_fc_achieved", "Solo_Drums", metric: "full_combo"),
                Ev("player_score_pb", "Solo_Guitar", 210000, 230891),
                Ev("player_gold_stars_achieved", "Solo_Drums", 5, 6),
            ],
        });
        var p = NotificationText.Format(item, "Taxes", "art.jpg");
        Assert.Equal("Taxes", p.Title);
        Assert.Equal("For Lead, your play set a new personal best with 230,891 points and climbed from #180 to #160.\n\nFor Drums, got a Full Combo and earned gold stars.", p.Message);
        Assert.Equal(["Lead", "230,891", "#180", "#160", "Drums", "Full Combo", "gold stars"], Bold(p));
        Assert.Equal(p.Message, string.Concat(p.Parts.Select(x => x.Text)));
        Assert.Equal([NotificationFlagKind.NewHighScore, NotificationFlagKind.FullCombo, NotificationFlagKind.GoldStars, NotificationFlagKind.RankUp], p.Flags);
        Assert.Equal([Instrument.Lead, Instrument.Drums], p.FlagGroups.Select(g => g.Instrument));
        Assert.Equal([NotificationFlagKind.NewHighScore, NotificationFlagKind.RankUp], p.FlagGroups[0].Flags);
        Assert.Equal([NotificationFlagKind.FullCombo, NotificationFlagKind.GoldStars], p.FlagGroups[1].Flags);
        Assert.Equal("Lead: New High Score, Rank Up. Drums: Full Combo, Gold Stars", p.FlagsText);
        Assert.True(p.HasFlags);
        var row = new NotificationRowViewModel(p, true, "1h ago");
        Assert.Equal("Unread. Taxes. For Lead, your play set a new personal best with 230,891 points and climbed from #180 to #160. "
            + "For Drums, got a Full Combo and earned gold stars. Affected instruments: Lead, Drums. "
            + "Lead: New High Score, Rank Up. Drums: Full Combo, Gold Stars. 1h ago", row.AccessibleName);
    }

    [Fact]
    public void Coalesced_WindowsMediaFixtureRows()
    {
        // The media rows of tools/windows/notifications_fixture.py, as the journey reads them (wire → text → row).
        var json = Envelope("""
            {"eventId":11,"notificationGuid":"fixture-notif-grid","eventKind":"player_score_pb","songId":"fixture-pulse","instrument":"Solo_Guitar","oldNumeric":180000,"newNumeric":201234,
             "payload":{"coalescedInstruments":["Solo_Guitar","Solo_Bass","Solo_Drums"],"coalescedEvents":[
               {"eventKind":"player_score_pb","instrument":"Solo_Guitar","oldNumeric":180000,"newNumeric":201234},
               {"eventKind":"player_song_rank_improved","instrument":"Solo_Guitar","oldRank":180,"newRank":160},
               {"eventKind":"player_fc_achieved","instrument":"Solo_Bass"},
               {"eventKind":"player_gold_stars_achieved","instrument":"Solo_Bass","oldNumeric":5,"newNumeric":6},
               {"eventKind":"player_first_score","instrument":"Solo_Drums","newNumeric":154321,"newRank":6}]},
             "detectedAt":"2024-01-07T12:00:00Z","expiresAt":"2024-02-07T12:00:00Z"},
            {"eventId":16,"notificationGuid":"fixture-notif-pb","eventKind":"player_score_pb","songId":"fixture-orbit","instrument":"Solo_Drums","oldNumeric":99000,"newNumeric":123456,
             "payload":{"newFullCombo":true},"detectedAt":"2024-01-02T12:00:00Z","expiresAt":"2024-02-02T12:00:00Z"}
            """);
        var items = JsonSerializer.Deserialize(json, NotificationsJsonContext.Default.ImprovementNotificationsEnvelope)!.Items!;
        var grid = NotificationText.Format(items[0], "Fixture Pulse", "art.jpg");
        Assert.Equal("Fixture Pulse", grid.Title);
        Assert.Equal("For Lead, your play set a new personal best with 201,234 points and climbed from #180 to #160.\n\n"
            + "For Bass, got a Full Combo and earned gold stars.\n\nFor Drums, your first play scored 154,321 points and started at #6.", grid.Message);
        Assert.Equal(["Lead", "201,234", "#180", "#160", "Bass", "Full Combo", "gold stars", "Drums", "154,321", "#6"], Bold(grid));
        Assert.Equal("Lead: New High Score, Rank Up. Bass: Full Combo, Gold Stars. Drums: First Play", grid.FlagsText);
        var row = new NotificationRowViewModel(grid, true, "Jan 7");
        Assert.Equal("Unread. Fixture Pulse. For Lead, your play set a new personal best with 201,234 points and climbed from #180 to #160. "
            + "For Bass, got a Full Combo and earned gold stars. For Drums, your first play scored 154,321 points and started at #6. "
            + "Affected instruments: Lead, Bass, Drums. Lead: New High Score, Rank Up. Bass: Full Combo, Gold Stars. Drums: First Play. Jan 7",
            row.AccessibleName);

        var pb = NotificationText.Format(items[1], "Fixture Orbit", "art.jpg");
        Assert.Equal("Fixture Orbit · Drums", pb.Title);
        Assert.Equal("You set a new personal best on Drums for Fixture Orbit with 123,456 points and got a Full Combo.", pb.Message);
        Assert.Equal(["Drums", "Fixture Orbit", "123,456", "Full Combo"], Bold(pb));
        Assert.Equal([NotificationFlagKind.NewHighScore, NotificationFlagKind.FullCombo], pb.Flags);
        Assert.Empty(pb.FlagGroups);
        Assert.Equal("New High Score, Full Combo", pb.FlagsText);
    }

    [Fact]
    public void Coalesced_SingleChartRowsJoinEveryEventIntoOneSentence()
    {
        var item = Item("player_score_pb", instrument: "Solo_Drums", oldN: 120000, newN: 137700, payload: new NotificationPayload
        {
            CoalescedEvents =
            [
                Ev("player_song_rank_improved", "Solo_Drums", oldRank: 1214, newRank: 982),
                Ev("player_score_pb", "Solo_Drums", 120000, 137700),
                Ev("player_fc_achieved", "Solo_Drums"),
                Ev("player_stars_improved", "Solo_Drums", 5, 6),
                Ev("player_gold_stars_achieved", "Solo_Drums", 5, 6),
            ],
        });
        var p = NotificationText.Format(item, "Apple");
        Assert.Equal("Apple · Drums", p.Title);
        Assert.Equal("You set a new personal best on Drums for Apple with 137,700 points, got a Full Combo, earned gold stars, and climbed from #1,214 to #982.", p.Message);
        Assert.Equal(["Drums", "Apple", "137,700", "Full Combo", "gold stars", "#1,214", "#982"], Bold(p));
        Assert.Equal([NotificationFlagKind.NewHighScore, NotificationFlagKind.FullCombo, NotificationFlagKind.GoldStars, NotificationFlagKind.RankUp], p.Flags);
        Assert.Empty(p.FlagGroups);
        Assert.Equal("New High Score, Full Combo, Gold Stars, Rank Up", p.FlagsText);
    }

    [Fact]
    public void Coalesced_DerivesFullComboAndGoldStarsFromTheScoreResult()
    {
        // The live feed's shape: aggregate rows carry the score's result on the payload, not as separate events.
        var item = Item("player_score_pb", instrument: "Solo_Drums", oldN: 120000, newN: 137700, payload: new NotificationPayload
        {
            CoalescedEvents = [Ev("player_score_pb", "Solo_Drums", 120000, 137700), Ev("player_song_rank_improved", null, oldRank: 1214, newRank: 982)],
            NewFullCombo = true, OldStars = 5, NewStars = 6,
        });
        var p = NotificationText.Format(item, "Apple");
        Assert.Equal("You set a new personal best on Drums for Apple with 137,700 points, got a Full Combo, earned gold stars, and climbed from #1,214 to #982.", p.Message);
        Assert.Equal([NotificationFlagKind.NewHighScore, NotificationFlagKind.FullCombo, NotificationFlagKind.GoldStars, NotificationFlagKind.RankUp], p.Flags);

        // A single (uncoalesced) score row derives them too, and a gold result supersedes a stars bump.
        var single = Item("player_first_score", instrument: "Solo_Bass", newN: 98765, newRank: 12, payload: new NotificationPayload { NewFullCombo = false, NewStars = 6 });
        var first = NotificationText.Format(single, "Song");
        Assert.Equal("Your first Bass play on Song scored 98,765 points, started at #12, and earned gold stars.", first.Message);
        Assert.Equal([NotificationFlagKind.FirstPlay, NotificationFlagKind.GoldStars], first.Flags);
        var superseded = NotificationText.Format(Item("player_score_pb", instrument: "Solo_Bass", newN: 5000, payload: new NotificationPayload
        {
            CoalescedEvents = [Ev("player_score_pb", "Solo_Bass", null, 5000), Ev("player_stars_improved", "Solo_Bass", 5, 6)],
            NewStars = 6,
        }), "Song");
        Assert.Equal("You set a new personal best on Bass for Song with 5,000 points and earned gold stars.", superseded.Message);
        Assert.DoesNotContain(NotificationFlagKind.StarsUp, superseded.Flags);
    }

    [Fact]
    public void Coalesced_TopLevelResultOnlyBelongsToTheMatchingChart()
    {
        // Multi-chart: only the event that is the row's own top-level score takes the payload's result.
        var item = Item("player_score_pb", instrument: "Solo_Guitar", oldN: 1, newN: 2000, payload: new NotificationPayload
        {
            CoalescedEvents = [Ev("player_score_pb", "Solo_Guitar", 1, 2000), Ev("player_score_pb", "Solo_Bass", 1, 3000)],
            NewFullCombo = true,
        });
        var p = NotificationText.Format(item, "Inferno Island");
        Assert.Equal("For Lead, your play set a new personal best with 2,000 points and got a Full Combo.\n\nFor Bass, your play set a new personal best with 3,000 points.", p.Message);
        Assert.Equal([NotificationFlagKind.NewHighScore, NotificationFlagKind.FullCombo], p.FlagGroups[0].Flags);
        Assert.Equal([NotificationFlagKind.NewHighScore], p.FlagGroups[1].Flags);

        // Two score events on other charts than the row's: neither owns the payload.
        var other = NotificationText.Format(Item("player_fc_achieved", instrument: "Solo_Guitar", payload: new NotificationPayload
        {
            CoalescedEvents = [Ev("player_score_pb", "Solo_Bass", null, 3000), Ev("player_first_score", "Solo_Bass", null, 4000, newRank: 5)],
            NewStars = 6,
        }), "Song");
        Assert.DoesNotContain(NotificationFlagKind.GoldStars, other.Flags);
        // One score event on another chart than the row's (single chart): the payload is not its result.
        var mismatch = NotificationText.Format(Item("player_fc_achieved", instrument: "Solo_Guitar", payload: new NotificationPayload
        {
            CoalescedEvents = [Ev("player_score_pb", "Solo_Bass", null, 3000)],
            NewStars = 6,
        }), "Song");
        Assert.Equal([NotificationFlagKind.NewHighScore], mismatch.Flags);
        // An event's own result wins over the payload.
        var own = NotificationText.Format(Item("player_score_pb", payload: new NotificationPayload
        {
            CoalescedEvents = [new() { EventKind = "player_score_pb", Instrument = "Solo_Guitar", NewNumeric = 10, NewFullCombo = true }],
            NewStars = 6,
        }), "Song");
        Assert.Equal([NotificationFlagKind.NewHighScore, NotificationFlagKind.FullCombo], own.Flags);
    }

    [Fact]
    public void Coalesced_FirstPlayKeepsOneStartedAtClause()
    {
        var item = Item("player_first_score", instrument: "Solo_Bass", newN: 154321, newRank: 6, payload: new NotificationPayload
        {
            CoalescedEvents = [Ev("player_first_score", "Solo_Bass", null, 154321, newRank: 6), Ev("player_song_rank_improved", "Solo_Bass", oldRank: 9, newRank: 6)],
        });
        var p = NotificationText.Format(item, "Orbit");
        Assert.Equal("Your first Bass play on Orbit scored 154,321 points, started at #6, and climbed from #9 to #6.", p.Message);
        Assert.Equal(2, p.Message.Split("started at").Length);
    }

    [Fact]
    public void Coalesced_SeveralRanksBecomeRankUpdates()
    {
        var item = Item("player_total_score_rank_improved", song: null, instrument: "Solo_Drums", payload: new NotificationPayload
        {
            CoalescedEvents =
            [
                Ev("player_weighted_rank_improved", oldRank: 201, newRank: 163),
                Ev("player_total_score_rank_improved", oldRank: 263, newRank: 189),
            ],
        });
        var p = NotificationText.Format(item, null);
        Assert.Equal("Rank Updates · Drums", p.Title);
        Assert.Equal("For Total Score Rank, moved from #263 to #189.\n\nFor Weighted Percentile Rank, moved from #201 to #163.", p.Message);
        Assert.Equal(["Total Score Rank", "#263", "#189", "Weighted Percentile Rank", "#201", "#163"], Bold(p));
        Assert.Equal([NotificationFlagKind.RankUp], p.Flags);
        Assert.Equal("Rank Updates", NotificationText.Format(item with { Instrument = null }, null).Title);
    }

    [Fact]
    public void Coalesced_InstrumentAggregatesPairValuesWithRanks()
    {
        var item = Item("player_total_score_improved", song: null, instrument: "Solo_Vocals", payload: new NotificationPayload
        {
            CoalescedEvents =
            [
                Ev("player_total_score_improved", null, 100, 123456),
                Ev("player_total_score_rank_improved", oldRank: 50, newRank: 40),
                Ev("player_fc_count_improved", null, 10, 12),
                Ev("player_fc_rate_rank_improved", oldRank: 30, newRank: 20),
                Ev("player_skill_rank_improved", oldRank: 9, newRank: 8),
                Ev("player_weighted_rank_improved", oldRank: 7, newRank: 6),
                Ev("player_max_score_rank_improved", oldRank: 5, newRank: 4),
            ],
        });
        var p = NotificationText.Format(item, null);
        Assert.Equal("Tap Vocals · Improvements", p.Title);
        Assert.Equal(string.Join("\n\n",
            "Your total score increased to 123,456 points and your total score rank moved up from #50 to #40.",
            "Your Full Combo count increased to 12 and your Full Combo percentage rank moved up from #30 to #20.",
            "Your adjusted percentile rank moved up from #9 to #8.",
            "Your percentile rank, weighted by number of entries, moved up from #7 to #6.",
            "Your max score rank moved up from #5 to #4."), p.Message);
        Assert.Contains("total score rank", Bold(p));
        Assert.Contains("percentile rank, weighted by number of entries", Bold(p));
        Assert.Equal([NotificationFlagKind.Progress, NotificationFlagKind.RankUp], p.Flags);
        Assert.Equal("Instrument Updates", NotificationText.Format(item with { Instrument = null }, null).Title);

        // Unpaired halves: a value alone, a rank alone.
        var halves = NotificationText.Format(item with
        {
            Payload = new NotificationPayload
            {
                CoalescedEvents = [Ev("player_total_score_rank_improved", oldRank: 50, newRank: 40), Ev("player_fc_count_improved", null, 10, 12)],
            },
        }, null);
        Assert.Equal("Your total score rank moved up from #50 to #40.\n\nYour Full Combo count increased to 12.", halves.Message);
        var valueOnly = NotificationText.Format(item with
        {
            Payload = new NotificationPayload
            {
                CoalescedEvents = [Ev("player_total_score_improved", null, 1, 2), Ev("player_fc_rate_rank_improved", oldRank: 3, newRank: 2)],
            },
        }, null);
        Assert.Equal("Your total score increased to 2 points.\n\nYour Full Combo percentage rank moved up from #3 to #2.", valueOnly.Message);
    }

    [Fact]
    public void Coalesced_SingleKindsKeepTheirTitlesAndSkipBlankEvents()
    {
        var progress = Item("player_fc_count_improved", song: null, payload: new NotificationPayload
        {
            CoalescedEvents = [new(), Ev(" "), Ev("player_fc_count_improved", null, 1, 3)],
        });
        Assert.Equal("Full Combo Count Improved", NotificationText.Format(progress, null).Title);
        Assert.Equal("Your Lead Full Combo count increased to 3.", NotificationText.Format(progress, null).Message);
        var difficulty = NotificationText.Format(Item("player_score_pb", payload: new NotificationPayload
        {
            CoalescedEvents = [Ev("player_score_pb", "Solo_Guitar", null, 10), new() { EventKind = "player_difficulty_bumped", OldLabel = "Hard", NewLabel = "Expert" }],
        }), "Song");
        Assert.Equal("You set a new personal best on Lead for Song with 10 points and improved difficulty from Hard to Expert.", difficulty.Message);
        Assert.Contains("Expert", Bold(difficulty));
        // Unknown kinds sort last, have no copy and read as the generic Improvement flag.
        var unknown = NotificationText.Format(Item("mystery", payload: new NotificationPayload
        {
            CoalescedEvents = [Ev("mystery"), Ev("player_fc_achieved", "Solo_Guitar")],
        }), "Song");
        Assert.Equal("Song · Lead", unknown.Title);
        Assert.Equal("You got a Full Combo on Lead for Song.", unknown.Message);
        Assert.Equal([NotificationFlagKind.FullCombo, NotificationFlagKind.Improvement], unknown.Flags);
    }

    [Fact]
    public void Wire_DecodesEventValuesLeniently()
    {
        const string payload = """
            {"newFullCombo":"true","oldStars":"5","newStars":6,"oldFullCombo":{"x":1},
             "coalescedEvents":[{"eventKind":"player_score_pb","instrument":"Solo_Bass","oldNumeric":1,"newNumeric":"2.5","oldRank":null,"newRank":[1],
               "oldLabel":" Hard ","newLabel":"  ","oldFullCombo":false,"newFullCombo":"FALSE","oldStars":"x","newStars":"Infinity"},
              {"eventKind":"player_fc_achieved","oldNumeric":true,"newFullCombo":"maybe","newLabel":7}]}
            """;
        var json = Envelope($$"""{"eventId":1,"notificationGuid":"g","eventKind":"player_score_pb","payload":{{payload}},"detectedAt":"2026-09-28T11:00:00Z","expiresAt":"2026-10-01T00:00:00Z"}""");
        var p = JsonSerializer.Deserialize(json, NotificationsJsonContext.Default.ImprovementNotificationsEnvelope)!.Items![0].Payload!;
        Assert.Equal((true, (double?)5, (double?)6, (bool?)null), (p.NewFullCombo, p.OldStars, p.NewStars, p.OldFullCombo));
        var e = p.CoalescedEvents![0];
        Assert.Equal((1d, 2.5, (double?)null, (double?)null), (e.OldNumeric, e.NewNumeric, e.OldRank, e.NewRank));
        Assert.Equal(("Hard", (string?)null), (e.OldLabel, e.NewLabel));
        Assert.Equal(((bool?)false, (bool?)false, (double?)null, (double?)null), (e.OldFullCombo, e.NewFullCombo, e.OldStars, e.NewStars));
        var f = p.CoalescedEvents[1];
        Assert.Equal(((double?)null, (bool?)null, (string?)null), (f.OldNumeric, f.NewFullCombo, f.NewLabel));
        var round = JsonSerializer.Serialize(e, NotificationsJsonContext.Default.NotificationEventPayload);
        Assert.Equal(e, JsonSerializer.Deserialize(round, NotificationsJsonContext.Default.NotificationEventPayload));
        var empty = JsonSerializer.Serialize(new NotificationEventPayload(), NotificationsJsonContext.Default.NotificationEventPayload);
        Assert.Equal(new NotificationEventPayload(), JsonSerializer.Deserialize(empty, NotificationsJsonContext.Default.NotificationEventPayload));
        // Null values write as JSON null when a caller keeps nulls.
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartArray();
            new LenientNumberConverter().Write(writer, null, JsonSerializerOptions.Default);
            new LenientBooleanConverter().Write(writer, null, JsonSerializerOptions.Default);
            new LenientStringConverter().Write(writer, null, JsonSerializerOptions.Default);
            writer.WriteEndArray();
        }
        Assert.Equal("[null,null,null]", System.Text.Encoding.UTF8.GetString(stream.ToArray()));
    }
    #endregion

    [Fact]
    public void Wire_DecodesCoalescedInstruments()
    {
        var feed = JsonSerializer.Deserialize(Envelope("""{"eventId":1,"notificationGuid":"g","eventKind":"player_score_pb","payload":{"coalescedInstruments":["Solo_Bass","Solo_Guitar"]},"detectedAt":"2026-09-28T11:00:00Z","expiresAt":"2026-10-01T00:00:00Z"}"""),
            NotificationsJsonContext.Default.ImprovementNotificationsEnvelope)!;
        Assert.Equal(["Solo_Bass", "Solo_Guitar"], feed.Items![0].Payload!.CoalescedInstruments!);
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
        Assert.Empty(p.Flags);
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
        Assert.True(first.HasDestination && first.HasFlags);
        Assert.Equal("New High Score", first.FlagsText);

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
        var row = new NotificationRowViewModel(new NotificationPresentation("x", "T", "M.", Now, null), false, "1h ago");
        Assert.Equal("T. M. 1h ago", row.AccessibleName);
        Assert.False(row.HasFlags);
        Assert.Equal("", row.FlagsText);
        Assert.False(row.HasDestination);
        Assert.Equal("x", row.Id);
        Assert.Equal("M.", row.Message);
        Assert.Null(row.Destination);
    }
    #endregion
}
