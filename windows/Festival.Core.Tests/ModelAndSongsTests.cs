using System.Globalization;
using System.Text;

namespace Festival.Core.Tests;

public class ModelAndSongsTests
{
    private static Song Make(string id, string title, string artist = "A", int? year = null, int? duration = null, SongDifficulty? difficulty = null) =>
        new() { SongId = id, Title = title, Artist = artist, Year = year, DurationSeconds = duration, Difficulty = difficulty };

    [Fact]
    public void Instruments_MapServiceIdsLabelsAndIcons()
    {
        Assert.Equal(9, InstrumentInfo.All.Count);
        var expected = new[]
        {
            ("Solo_Guitar", "Lead", "instrument_guitar.png", "instrument_keys.png"),
            ("Solo_Bass", "Bass", "instrument_bass.png", "instrument_bass.png"),
            ("Solo_Drums", "Drums", "instrument_drums.png", "instrument_drums.png"),
            ("Solo_Vocals", "Tap Vocals", "instrument_vocals.png", "instrument_vocals.png"),
            ("Solo_PeripheralGuitar", "Pro Lead", "instrument_pro_guitar.png", "instrument_pro_keys.png"),
            ("Solo_PeripheralBass", "Pro Bass", "instrument_pro_bass.png", "instrument_pro_bass.png"),
            ("Solo_PeripheralVocals", "Karaoke", "instrument_peripheral_vocals.png", "instrument_peripheral_vocals.png"),
            ("Solo_PeripheralCymbals", "Pro Drums + Cymbals", "instrument_peripheral_cymbals.png", "instrument_peripheral_cymbals.png"),
            ("Solo_PeripheralDrums", "Pro Drums", "instrument_peripheral_drums.png", "instrument_peripheral_drums.png"),
        };
        for (var i = 0; i < expected.Length; i++)
        {
            var instrument = InstrumentInfo.All[i];
            Assert.Equal(expected[i], (instrument.ServiceId(), instrument.Label(), instrument.IconFile(), instrument.IconFile(keyboard: true)));
            Assert.True(InstrumentInfo.TryParse(instrument.ServiceId(), out var parsed));
            Assert.Equal(instrument, parsed);
        }
        Assert.False(InstrumentInfo.TryParse("solo_guitar", out _));
        Assert.False(InstrumentInfo.TryParse(null, out _));
    }

    [Fact]
    public void Difficulty_ExcludesUnchartedSentinels()
    {
        var d = new SongDifficulty { Guitar = 3, Bass = 99, Drums = -1, Vocals = double.NaN, ProGuitar = 0, ProBass = 1, ProDrums = 2, ProCymbals = 4, ProVocals = 5 };
        Assert.Equal(3, d.ChartedValue(Instrument.Lead));
        Assert.Null(d.ChartedValue(Instrument.Bass));
        Assert.Null(d.ChartedValue(Instrument.Drums));
        Assert.Null(d.ChartedValue(Instrument.Vocals));
        Assert.Equal(0, d.ChartedValue(Instrument.ProLead));
        Assert.Equal(1, d.ChartedValue(Instrument.ProBass));
        Assert.Equal(5, d.ChartedValue(Instrument.Karaoke));
        Assert.Equal(4, d.ChartedValue(Instrument.ProCymbals));
        Assert.Equal(2, d.ChartedValue(Instrument.ProDrums));
        Assert.Null(new SongDifficulty().ChartedValue(Instrument.Lead));
    }

    [Fact]
    public void Song_ComputedFields()
    {
        var song = Make("s", "T", "Artist", 2020, 3725, new SongDifficulty { Guitar = 1 }) with
        {
            Sig = "Keyboard",
            MaxScores = new Dictionary<string, int> { ["Solo_Guitar"] = 5, ["Solo_Bass"] = 0 },
        };
        Assert.True(song.UsesKeyboardIcon);
        Assert.True(song.Supports(Instrument.Lead));
        Assert.False(song.Supports(Instrument.Bass));
        Assert.Equal(5, song.MaxScore(Instrument.Lead));
        Assert.Null(song.MaxScore(Instrument.Bass));
        Assert.Null(song.MaxScore(Instrument.Drums));
        Assert.Null(Make("x", "t").MaxScore(Instrument.Lead));
        Assert.Equal("1:02:05", song.FormattedDuration);
        Assert.Equal("3:05", Make("x", "t", duration: 185).FormattedDuration);
        Assert.Null(Make("x", "t", duration: 0).FormattedDuration);
        Assert.Equal("Artist · 2020 · 1:02:05", song.Subtitle);
        Assert.Equal("A", Make("x", "t").Subtitle);
        Assert.False(Make("x", "t").Supports(Instrument.Lead));
        Assert.True(System.Text.Json.JsonSerializer.Deserialize<Song>(
            """{"songId":"a","title":"A","artist":"B","doubleBassSupported":true}""", FestivalJsonContext.Default.Song)!.DoubleBassSupported);
        Assert.False(System.Text.Json.JsonSerializer.Deserialize<Song>(
            """{"songId":"a","title":"A","artist":"B","doubleBassSupported":false}""", FestivalJsonContext.Default.Song)!.DoubleBassSupported);
        Assert.Null(System.Text.Json.JsonSerializer.Deserialize<Song>(
            """{"songId":"a","title":"A","artist":"B","doubleBassSupported":null}""", FestivalJsonContext.Default.Song)!.DoubleBassSupported);
        Assert.Null(System.Text.Json.JsonSerializer.Deserialize<Song>(
            """{"songId":"a","title":"A","artist":"B"}""", FestivalJsonContext.Default.Song)!.DoubleBassSupported);
    }

    [Fact]
    public void Catalogue_Validation()
    {
        new SongsResponse(1, null, [Make("a", "t")]).Validate();
        Assert.Throws<FestivalApiException>(() => new SongsResponse(2, null, [Make("a", "t")]).Validate());
        Assert.Throws<FestivalApiException>(() => new SongsResponse(1, null, [Make("", "t")]).Validate());
        Assert.Throws<FestivalApiException>(() => new SongsResponse(1, null, [Make("a", "")]).Validate());
        Assert.Throws<FestivalApiException>(() => new SongsResponse(2, null, [Make("a", "t"), Make("a", "u")]).Validate());
        Assert.Throws<FestivalApiException>(() => new SongsResponse(-1, null, []).Validate());
        new Publication(1, 1, 1, false, false, null).Validate();
        Assert.Throws<FestivalApiException>(() => new Publication(1, 1, 0, false, false, null).Validate());
        Assert.Throws<FestivalApiException>(() => new Publication(1, 0, 1, false, false, null).Validate());
    }

    [Fact]
    public void Leaderboard_PagingAndValidation()
    {
        var board = new LeaderboardResponse { SongId = "s", Instrument = "Solo_Bass", Count = 1, TotalEntries = 26, LocalEntries = 26, Entries = [new LeaderboardEntry()] };
        Assert.Equal(2, board.PageCount());
        Assert.Equal(1, (board with { LocalEntries = null, TotalEntries = 0 }).PageCount());
        Assert.Equal(3, (board with { LocalEntries = null, TotalEntries = 21 }).PageCount(10));
        board.Validate("s", Instrument.Bass, 10);
        Assert.Throws<FestivalApiException>(() => board.Validate("t", Instrument.Bass, 10));
        Assert.Throws<FestivalApiException>(() => board.Validate("s", Instrument.Lead, 10));
        Assert.Throws<FestivalApiException>(() => (board with { Count = 2 }).Validate("s", Instrument.Bass, 10));
        Assert.Throws<FestivalApiException>(() => board.Validate("s", Instrument.Bass, 0));
        Assert.Throws<FestivalApiException>(() => (board with { TotalEntries = -1 }).Validate("s", Instrument.Bass, 10));
        Assert.Throws<FestivalApiException>(() => (board with { LocalEntries = -1 }).Validate("s", Instrument.Bass, 10));
    }

    [Theory]
    [InlineData("alpha", "Alpha Song", true)]
    [InlineData("  ", "Anything", true)]
    [InlineData("elec", "Électrique", true)]
    [InlineData("dont stop", "Don't Stop!", true)]
    [InlineData("rock roll", "Rock-n'-Roll", false)]
    [InlineData("rock n roll", "Rock-n'-Roll", true)]
    [InlineData("zzz", "Alpha", false)]
    [InlineData("--", "Alpha", true)]
    public void Search_MatchesLikeWeb(string query, string title, bool matches) =>
        Assert.Equal(matches, SongSearch.Matches(Make("x", title, "Band"), query));

    [Fact]
    public void Search_MatchesArtist()
    {
        Assert.True(SongSearch.Matches(Make("x", "t", "Beyoncé"), "beyonce"));
        Assert.True(SongSearch.Matches(Make("x", "t", "Beyoncé"), "BEY"));
        Assert.True(SongSearch.Matches(Make("x", "t", "The (Band)"), "the band"));
        Assert.True(SongSearch.Matches(Make("x", "t"), null));
        Assert.Equal("a b", SongSearch.Normalize("  A—B  "));
    }

    [Fact]
    public void Sort_OrdersWithTitleAndIdTies()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var songs = new[]
        {
            Make("3", "beta", "Zed", 2020, 200),
            Make("1", "Alpha", "Mid", null, null),
            Make("2", "alpha", "Ann", 2020, 100),
        };
        Assert.Equal(["1", "2", "3"], Ids(SongCatalogQuery.Apply(songs, "", SongFilter.None, SongSortMode.Title, true)));
        Assert.Equal(["3", "2", "1"], Ids(SongCatalogQuery.Apply(songs, "", SongFilter.None, SongSortMode.Title, false)));
        Assert.Equal(["2", "1", "3"], Ids(SongCatalogQuery.Apply(songs, "", SongFilter.None, SongSortMode.Artist, true)));
        Assert.Equal(["1", "2", "3"], Ids(SongCatalogQuery.Apply(songs, "", SongFilter.None, SongSortMode.Year, true)));
        Assert.Equal(["1", "2", "3"], Ids(SongCatalogQuery.Apply(songs, "", SongFilter.None, SongSortMode.Duration, true)));
        Assert.Equal(["3", "2", "1"], Ids(SongCatalogQuery.Apply(songs, "", SongFilter.None, SongSortMode.Duration, false)));
        Assert.Equal(["3"], Ids(SongCatalogQuery.Apply(songs, "bet", SongFilter.None, SongSortMode.Title, true)));
        Assert.Equal(["Title", "Artist", "Year", "Duration", "Item Shop", "Has FC", "Score", "Percentage", "Percentile", "Stars", "Season",
            "Intensity", "Difficulty", "Max Score %", "Max Score Diff", "Last Played"], SongSortModeInfo.All.Select(m => m.Label()));
    }

    [Fact]
    public void Sections_GroupFirstSeen()
    {
        var songs = new[]
        {
            Make("1", "apple", "Émile", 2019, 100),
            Make("2", "Avocado", "Zed", 2019, 130),
            Make("3", "9 Lives", "", null, 400),
            Make("4", "Banana", "   ", 2020, null),
        };
        var byTitle = SongCatalogQuery.Sections(SongCatalogQuery.Apply(songs, "", SongFilter.None, SongSortMode.Title, true), SongSortMode.Title);
        Assert.Equal(["#", "A", "B"], byTitle.Select(s => s.Label));
        Assert.Equal(2, byTitle[1].Songs.Count);
        Assert.Equal(["E", "Z", "#", "#"], songs.Select(s => SongCatalogQuery.SectionKey(s, SongSortMode.Artist)));
        Assert.Equal(["2010s", "2010s", "Unknown Year", "2020s"], songs.Select(s => SongCatalogQuery.SectionKey(s, SongSortMode.Year)));
        Assert.Equal(["1–2 Minutes", "2–3 Minutes", "6–7 Minutes", "Unknown Duration"],
            songs.Select(s => SongCatalogQuery.SectionKey(s, SongSortMode.Duration)));
        Assert.Equal("#", SongCatalogQuery.FirstLetter("(Don't Fear)"));
        Assert.Equal("Under 1 Minute", SongCatalogQuery.DurationBucket(59));
        Assert.Equal("3–4 Minutes", SongCatalogQuery.DurationBucket(200));
        Assert.Equal("4–5 Minutes", SongCatalogQuery.DurationBucket(299));
        Assert.Equal("9–10 Minutes", SongCatalogQuery.DurationBucket(599));
        Assert.Equal("Over 10 Minutes", SongCatalogQuery.DurationBucket(600));
        Assert.Equal("1970s", SongCatalogQuery.DecadeBucket(1979));
        Assert.Equal("Unknown Year", SongCatalogQuery.DecadeBucket(0));
        Assert.Empty(SongCatalogQuery.Sections([], SongSortMode.Title));
    }

    [Fact]
    public void Filter_InstrumentAndDifficulty()
    {
        var easyLead = Make("1", "a", difficulty: new SongDifficulty { Guitar = 0, Bass = 5 });
        var hardLead = Make("2", "b", difficulty: new SongDifficulty { Guitar = 6 });
        var noLead = Make("3", "c", difficulty: new SongDifficulty { Bass = 2 });
        var none = Make("4", "d");
        Song[] all = [easyLead, hardLead, noLead, none];
        Assert.Equal(4, all.Count(SongFilter.None.Matches));
        Assert.False(SongFilter.None.IsActive);
        var lead = new SongFilter(Instrument.Lead);
        Assert.True(lead.IsActive);
        Assert.Equal(["1", "2"], Ids(all.Where(lead.Matches)));
        // Web difficultyFilter: hidden intensity buckets on the selected chart only (raw 0 = 1 bar, raw 6 = 7 bars).
        Assert.Equal(["2"], Ids(all.Where(new SongFilter(Instrument.Lead, [1, 2, 3, 4, 5, 6]).Matches)));
        Assert.Equal(["1"], Ids(all.Where(new SongFilter(Instrument.Lead, [7]).Matches)));
        Assert.Equal(4, all.Count(new SongFilter(null, [1, 2, 3]).Matches));
        Assert.False(new SongFilter(null, [1, 2, 3]).IsActive);
        Assert.True(new SongFilter(null, [0, 7]).IsValid);
        Assert.False(new SongFilter(null, [8]).IsValid);
        Assert.False(new SongFilter { ExcludedIntensities = [3, 3] }.IsValid);
        Assert.Equal([1, 3], new SongFilter(null, [3, 1, 3]).ExcludedIntensities);
        Assert.Null(lead.ScopedTo([Instrument.Bass]).Instrument);
        Assert.Equal(Instrument.Lead, lead.ScopedTo([Instrument.Lead]).Instrument);
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(5.9, 6)]
    [InlineData(6, 7)]
    [InlineData(99, 7)]
    [InlineData(-2, 1)]
    [InlineData(double.NaN, 0)]
    public void DifficultyScale_MapsRawToBars(double raw, int bars) => Assert.Equal(bars, DifficultyScale.BarsForRaw(raw));

    [Fact]
    public void DifficultyScale_GeometryAndAnnouncement()
    {
        Assert.Equal((62.0, 20.0, 7), (DifficultyScale.Width, DifficultyScale.Height, DifficultyScale.BarCount));
        Assert.Equal([(20.0, 0.0), (26.0, 0.0), (24.0, 20.0), (18.0, 20.0)], DifficultyScale.BarPolygon(2));
        Assert.Equal(62.0, DifficultyScale.BarPolygon(6)[1].X);
        Assert.Equal("Difficulty 4 of 7", DifficultyScale.Announcement(3.2));
        Assert.Equal("Difficulty unavailable", DifficultyScale.Announcement(null));
        Assert.Equal("Difficulty unavailable", DifficultyScale.Announcement(double.PositiveInfinity));
    }

    [Theory]
    [InlineData(0, "one", 1)]
    [InlineData(1.5, "two", 2)]
    [InlineData(2, "three", 3)]
    [InlineData(3.99, "four", 4)]
    [InlineData(4, "five", 5)]
    [InlineData(5.9, "six", 6)]
    [InlineData(6, "seven", 7)]
    [InlineData(99, "seven", 7)]
    [InlineData(-3, "one", 1)]
    public void DifficultyMeterState_LevelStates(double raw, string name, int bars)
    {
        var state = DifficultyScale.State(raw);
        Assert.True(state.IsAvailable);
        Assert.Equal(name, state.StateName);
        Assert.Equal(bars, state.FilledBars);
        Assert.Equal("fst.songs.difficulty-meter", state.AutomationId);
        Assert.Equal($"Difficulty {bars} of 7", state.Name);
        Assert.Equal(Enumerable.Range(0, 7).Select(i => i < bars), Enumerable.Range(0, 7).Select(state.IsFilled));
    }

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void DifficultyMeterState_InvalidShowsTextNotBars(double raw)
    {
        var state = DifficultyScale.State(raw);
        Assert.False(state.IsAvailable);
        Assert.Equal("invalid", state.StateName);
        Assert.Equal(0, state.FilledBars);
        Assert.Equal("fst.songs.difficulty-unavailable", state.AutomationId);
        Assert.Equal("Difficulty unavailable", state.Name);
        Assert.DoesNotContain(true, Enumerable.Range(0, 7).Select(state.IsFilled));
    }

    [Fact]
    public void DifficultyMeterState_RecycledMeterReturnsToMeterId()
    {
        // A recycled row can go invalid → valid; the ID must follow the state, not stick at "unavailable".
        Assert.Equal("fst.songs.difficulty-unavailable", DifficultyScale.State(double.NaN).AutomationId);
        Assert.Equal("fst.songs.difficulty-meter", DifficultyScale.State(2).AutomationId);
    }

    [Fact]
    public void ScoreFormatting_Formats()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Assert.Equal("100%", ScoreFormatting.Accuracy(1_000_000));
        Assert.Equal("98.5%", ScoreFormatting.Accuracy(985_000));
        Assert.Equal("98.5%", ScoreFormatting.Accuracy(984_960));
        Assert.Equal("", ScoreFormatting.Accuracy(null));
        Assert.Equal("", ScoreFormatting.Accuracy(double.NaN));
        Assert.Equal("123,456", ScoreFormatting.Score(123456));
        Assert.Equal("#1,234", ScoreFormatting.Rank(1234));
        Assert.Equal((46, 204, 113), ToInts(ScoreFormatting.AccuracyTint(1_000_000)));
        Assert.Equal((220, 40, 40), ToInts(ScoreFormatting.AccuracyTint(double.NaN)));
        Assert.Equal((133, 122, 77), ToInts(ScoreFormatting.AccuracyTint(500_000)));
    }

    private static (int, int, int) ToInts((byte R, byte G, byte B) c) => (c.R, c.G, c.B);

    private static string[] Ids(IEnumerable<Song> songs) => songs.Select(s => s.SongId).ToArray();
}
