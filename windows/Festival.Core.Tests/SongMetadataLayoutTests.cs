using System.Globalization;

namespace Festival.Core.Tests;

/// <summary>Songs metadata placement and test IDs (issue #228).</summary>
public class SongMetadataLayoutTests
{
    [Fact]
    public void AutomationIds_FollowTheCrossPlatformRoot()
    {
        Assert.Equal("fst.songs.metadata.score.fixture-pulse", SongMetadataLayout.AutomationId(MetadataField.Score, "fixture-pulse"));
        Assert.Equal("fst.songs.metadata.lastplayed.s1", SongMetadataLayout.AutomationId(MetadataField.LastPlayed, "s1"));
        Assert.Equal("fst.songs.metadata.percentage.s1", SongMetadataLayout.AutomationId(MetadataField.Percentage, "s1"));
        Assert.Equal("fst.songs.metadata.chart.s1", SongMetadataLayout.ChartAutomationId("s1"));
        Assert.Equal("fst.songs.metadata.state.s1", SongMetadataLayout.StateAutomationId("s1"));
        // Every field has a distinct lower-case key.
        var ids = Enum.GetValues<MetadataField>().Select(f => SongMetadataLayout.AutomationId(f, "x")).ToList();
        Assert.Equal(ids.Count, ids.Distinct().Count());
        Assert.All(ids, id => Assert.Equal(id.ToLowerInvariant(), id));
    }

    [Fact]
    public void WidestSamples_OnePerEnabledField()
    {
        var all = SongMetadataLayout.WidestSamples(new AppSettings());
        Assert.Equal(Enum.GetValues<MetadataField>().Length, all.Count);
        Assert.Equal(all.Count, all.Select(s => s.Kind).Distinct().Count());
        Assert.Contains(all, s => s.Kind == MetadataField.Percentage && s.Text == "100% FC" && s.FullCombo);
        Assert.Contains(all, s => s.Kind == MetadataField.Stars && s.Stars == (5, true));
        Assert.Contains(all, s => s.Kind == MetadataField.Difficulty && s.Text == "M");
        Assert.Contains(all, s => s.Kind == MetadataField.Intensity && s.IntensityRaw == 6);

        var none = new AppSettings
        {
            MetadataScore = false, MetadataPercentage = false, MetadataPercentile = false, MetadataStars = false,
            MetadataSeason = false, MetadataIntensity = false, MetadataDifficulty = false, MetadataLastPlayed = false,
        };
        // A full combo still shows "FC" with Percentage hidden, so it always reserves room.
        var fcOnly = Assert.Single(SongMetadataLayout.WidestSamples(none));
        Assert.Equal("FC", fcOnly.Text);
    }

    [Fact]
    public void WidestSamples_LastPlayedUsesTheCurrentCulture()
    {
        var previous = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("en-GB");
            var sample = SongMetadataLayout.WidestSamples(new AppSettings()).Single(s => s.Kind == MetadataField.LastPlayed);
            Assert.Equal("Last played 28 Sept 2026", sample.Text.Replace("Sep ", "Sept "));
        }
        finally
        {
            CultureInfo.CurrentCulture = previous;
        }
    }

    [Fact]
    public void RequiredWidth_SumsPillsSpacingChromeAndTitle()
    {
        var baseline = SongMetadataLayout.RowChrome + SongMetadataLayout.MinimumTitleWidth;
        Assert.Equal(baseline, SongMetadataLayout.RequiredWidth([], false));
        Assert.Equal(baseline + 100 + 6 + 50, SongMetadataLayout.RequiredWidth([100, 50], false));
        Assert.Equal(baseline + 100 + 6 + 50 + 6 + SongMetadataLayout.ChartIconSize, SongMetadataLayout.RequiredWidth([100, 50], true));
        // Unmeasured or bogus widths are ignored rather than poisoning the threshold.
        Assert.Equal(baseline + 100, SongMetadataLayout.RequiredWidth([100, 0, double.NaN, double.PositiveInfinity, -4], false));
    }

    [Theory]
    [InlineData(900, 900, false, true)]
    [InlineData(899, 900, false, false)]
    [InlineData(869, 900, true, true)]
    [InlineData(868, 900, true, true)]
    [InlineData(867.9, 900, true, false)]
    [InlineData(0, 100, true, false)]
    [InlineData(double.NaN, 100, false, false)]
    [InlineData(5000, double.PositiveInfinity, true, false)]
    public void Inline_UsesHysteresisOnlyWhenAlreadyInline(double list, double required, bool wasInline, bool expected) =>
        Assert.Equal(expected, SongMetadataLayout.Inline(list, required, wasInline));

    [Fact]
    public void Inline_ResizeAcrossTheThresholdFlipsOncePerDirection()
    {
        const double required = 800;
        var inline = false;
        var flips = 0;
        // Growing, then hovering around the threshold, then shrinking.
        foreach (var width in new double[] { 700, 790, 800, 795, 780, 770, 800, 790, 760, 700 })
        {
            var next = SongMetadataLayout.Inline(width, required, inline);
            if (next != inline) flips++;
            inline = next;
        }
        Assert.Equal(2, flips);
        Assert.False(inline);
    }
}
