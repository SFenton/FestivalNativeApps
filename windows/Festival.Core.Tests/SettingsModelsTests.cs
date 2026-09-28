namespace Festival.Core.Tests;

public class SettingsModelsTests
{
    [Fact]
    public void Normalize_RepairsOrder()
    {
        Assert.Equal(Enum.GetValues<PathColumnKey>(), SettingsOrder.Normalize<PathColumnKey>(null));
        var repaired = SettingsOrder.Normalize([PathColumnKey.Score, PathColumnKey.Score, (PathColumnKey)42, PathColumnKey.Note]);
        Assert.Equal([PathColumnKey.Score, PathColumnKey.Note, PathColumnKey.Beat, PathColumnKey.Time, PathColumnKey.Od], repaired);
    }

    [Fact]
    public void Move_SwapsWithinRangeOnly()
    {
        IReadOnlyList<int> order = [1, 2, 3];
        Assert.Equal([2, 1, 3], SettingsOrder.Move(order, 1, -1));
        Assert.Equal([1, 3, 2], SettingsOrder.Move(order, 1, 1));
        Assert.Equal([1, 2, 3], SettingsOrder.Move(order, 0, -1));
        Assert.Equal([1, 2, 3], SettingsOrder.Move(order, 2, 1));
        Assert.Equal([1, 2, 3], SettingsOrder.Move(order, 7, 1));
    }

    [Theory]
    [InlineData(1, "+1.0%", 101_000)]
    [InlineData(-0.5, "-0.5%", 99_500)]
    [InlineData(0, "0.0%", 100_000)]
    [InlineData(9, "+5.0%", 105_000)]
    [InlineData(-9, "-5.0%", 95_000)]
    [InlineData(1.26, "+1.3%", 101_300)]
    [InlineData(double.NaN, "+1.0%", 101_000)]
    public void Leeway_ClampsFormatsAndComputesMax(double value, string label, int max)
    {
        Assert.Equal(label, ScoreLeeway.Format(value));
        Assert.Equal(max, ScoreLeeway.MaxEffectiveScore(value));
    }

    [Fact]
    public void Labels_CoverEveryCase()
    {
        Assert.Equal(["Score", "Percentage", "Percentile", "Season Achieved", "Intensity", "Game Difficulty", "Stars", "Last Played"],
            Enum.GetValues<MetadataField>().Select(f => f.Label()));
        Assert.Equal(["Note", "Beat", "Time", "OD", "Score"], Enum.GetValues<PathColumnKey>().Select(c => c.Label()));
        Assert.Equal("last-played", MetadataField.LastPlayed.Token());
        Assert.Equal("score", MetadataField.Score.Token());
    }

    [Fact]
    public void Metadata_TogglesIndependently()
    {
        var settings = new AppSettings();
        foreach (var field in Enum.GetValues<MetadataField>())
        {
            Assert.True(settings.IsMetadataVisible(field));
            settings = settings.WithMetadataVisible(field, false);
            Assert.False(settings.IsMetadataVisible(field));
        }
        Assert.All(Enum.GetValues<MetadataField>(), f => Assert.False(settings.IsMetadataVisible(f)));
    }

    [Fact]
    public void Sanitized_ClampsAppSettings()
    {
        var raw = new AppSettings
        {
            Leeway = 12, ExperimentalRanks = true, TapTelemetry = true, TapDiagnostics = false,
            PathDefaultView = (PathDisplayMode)9, SongRowVisualOrder = [MetadataField.Stars], PathColumnOrder = null!,
        }.Sanitized();
        Assert.Equal(5, raw.Leeway);
        Assert.False(raw.ExperimentalRanks);
        Assert.False(raw.TapTelemetry);
        Assert.Equal(PathDisplayMode.Image, raw.PathDefaultView);
        Assert.Equal(MetadataField.Stars, raw.SongRowVisualOrder[0]);
        Assert.Equal(8, raw.SongRowVisualOrder.Count);
        Assert.Equal(5, raw.PathColumnOrder.Count);
        Assert.True(new AppSettings { TapDiagnostics = true, TapTelemetry = true }.Sanitized().TapTelemetry);
        Assert.Equal("totalscore", new AppSettings { LeaderboardRankBy = "bogus" }.Sanitized().LeaderboardRankBy);
        Assert.Equal("totalscore", new AppSettings { LeaderboardRankBy = null! }.Sanitized().LeaderboardRankBy);
        Assert.Equal("fcrate", new AppSettings { LeaderboardRankBy = "fcrate" }.Sanitized().LeaderboardRankBy);
        Assert.NotEqual(new AppSettings(), new AppSettings { LeaderboardRankBy = "fcrate" });
        Assert.Equal("maxscore", new AppSettings { LeaderboardRankBy = "maxscore" }.ResetAppSettings().LeaderboardRankBy);
    }

    [Fact]
    public void ShopHighlight_RequiresVisibleShop()
    {
        Assert.True(new AppSettings().ShopHighlightEnabled);
        Assert.False(new AppSettings { HideShop = true }.ShopHighlightEnabled);
        Assert.False(new AppSettings { DisableShopHighlighting = true }.ShopHighlightEnabled);
    }

    [Fact]
    public void Reset_RestoresAppSettingsOnly()
    {
        var player = new SelectedPlayer("0123456789abcdef0123456789abcdef", "Tester");
        var changed = new AppSettings
        {
            SelectedPlayer = player, SongSort = SongSortMode.Artist, SongSortAscending = false,
            ShowInstrumentIcons = false, EnableVisualOrder = true, SongRowVisualOrder = [MetadataField.Stars],
            PathColumnOrder = [PathColumnKey.Score], FilterInvalidScores = true, Leeway = -2, PathDefaultView = PathDisplayMode.Text,
            PathUnavailableWarningDismissed = true, HideShop = true, DisableShopHighlighting = true, TapDiagnostics = true,
            TapTelemetry = true, MetadataScore = false, MetadataPercentage = false, MetadataPercentile = false, MetadataSeason = false,
            MetadataIntensity = false, MetadataDifficulty = false, MetadataStars = false, MetadataLastPlayed = false,
            VisibleInstruments = [Instrument.Bass], ReduceMotion = true, DisableAnimatedArtwork = true, SaveData = true,
            MoreContrast = true, LessTransparency = true,
        }.Sanitized();

        var reset = changed.ResetAppSettings();

        Assert.Equal(new AppSettings { SelectedPlayer = player, SongSort = SongSortMode.Artist, SongSortAscending = false }.Sanitized(), reset);
    }

    [Fact]
    public void Equality_ComparesNewFields()
    {
        var baseline = new AppSettings().Sanitized();
        Assert.Equal(baseline, new AppSettings().Sanitized());
        Assert.Equal(baseline.GetHashCode(), new AppSettings().Sanitized().GetHashCode());
        AppSettings[] variants =
        [
            baseline with { ShowInstrumentIcons = false }, baseline with { EnableVisualOrder = true },
            baseline with { SongRowVisualOrder = SettingsOrder.Move(baseline.SongRowVisualOrder, 0, 1) },
            baseline with { PathColumnOrder = SettingsOrder.Move(baseline.PathColumnOrder, 0, 1) },
            baseline with { FilterInvalidScores = true }, baseline with { Leeway = 2 }, baseline with { PathDefaultView = PathDisplayMode.Text },
            baseline with { PathUnavailableWarningDismissed = true }, baseline with { ExperimentalRanks = true },
            baseline with { HideShop = true }, baseline with { DisableShopHighlighting = true }, baseline with { TapDiagnostics = true },
            baseline with { TapTelemetry = true }, baseline with { MetadataScore = false }, baseline with { MetadataPercentage = false },
            baseline with { MetadataPercentile = false }, baseline with { MetadataSeason = false }, baseline with { MetadataIntensity = false },
            baseline with { MetadataDifficulty = false }, baseline with { MetadataStars = false }, baseline with { MetadataLastPlayed = false },
            baseline with { MoreContrast = true }, baseline with { LessTransparency = true },
        ];
        Assert.All(variants, v => Assert.NotEqual(baseline, v));
    }

    [Fact]
    public void JsonStore_RoundTripsEveryAppSetting()
    {
        var path = Path.Combine(Path.GetTempPath(), "fst-settings-" + Guid.NewGuid().ToString("N"), "settings.json");
        try
        {
            var store = new JsonFileSettingsStore(path);
            var settings = new AppSettings
            {
                ShowInstrumentIcons = false, EnableVisualOrder = true, SongRowVisualOrder = [MetadataField.LastPlayed],
                PathColumnOrder = [PathColumnKey.Od], FilterInvalidScores = true, Leeway = -1.5, PathDefaultView = PathDisplayMode.Text,
                HideShop = true, DisableShopHighlighting = true, TapDiagnostics = true, TapTelemetry = true, MetadataStars = false,
                MoreContrast = true, LessTransparency = true,
            }.Sanitized();
            store.Save(settings);
            Assert.Equal(settings, new JsonFileSettingsStore(path).Load());
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(path)!, true);
        }
    }
}
