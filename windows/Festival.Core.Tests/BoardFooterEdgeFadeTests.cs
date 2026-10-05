using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>The fade above a leaderboard's floating footer (issues #93, #305).</summary>
public sealed class BoardFooterEdgeFadeTests
{
    [Fact]
    public void Depth_MatchesTheWebScrollMask() => Assert.Equal(40, BoardFooterEdgeFade.Depth);

    [Theory]
    [InlineData(1000, 1000, 0)]
    [InlineData(1000, 1200, 0)]
    [InlineData(1000, 980, 0.5)]
    [InlineData(1000, 960, 1)]
    [InlineData(1000, 0, 1)]
    [InlineData(0, 0, 0)]
    [InlineData(double.NaN, 0, 0)]
    public void Strength_EasesOutOverTheLastDepthOfScroll(double scrollable, double offset, double expected) =>
        Assert.Equal(expected, BoardFooterEdgeFade.Strength(scrollable, offset), 6);

    [Fact]
    public void Stops_FadeToTheFooterTopThenClearBeneathIt()
    {
        var stops = BoardFooterEdgeFade.Stops(1);
        var scale = 40f / 41f;
        Assert.Equal([0f, 0.25f * scale, 0.5f * scale, 0.75f * scale, scale, 1f], stops.Select(s => s.Offset));
        Assert.Equal([1f, 0.84375f, 0.5f, 0.15625f, 0f, 0f], stops.Select(s => s.Alpha), new FloatTolerance());
    }

    [Fact]
    public void Stops_AtTheEndKeepRowsOpaqueButStillClearBeneathTheFooter()
    {
        var stops = BoardFooterEdgeFade.Stops(0);
        Assert.All(stops.Take(5), s => Assert.Equal(1f, s.Alpha));
        Assert.Equal((1f, 0f), stops[^1]);
    }

    [Fact]
    public void Stops_HalfStrengthHalvesTheBand() =>
        Assert.Equal(0.5f, BoardFooterEdgeFade.Stops(0.5)[4].Alpha, 6);

    // Issue #305: the edge depends only on the footer being on screen and the appearance settings, never on whether
    // the footer holds the selected player's pinned row.
    [Theory]
    [InlineData(true, false, true, false, false, BoardFooterTreatment.Fade)]
    [InlineData(false, false, true, false, false, BoardFooterTreatment.None)]
    [InlineData(true, true, true, false, false, BoardFooterTreatment.Plate)]
    [InlineData(true, true, false, true, true, BoardFooterTreatment.Plate)]
    [InlineData(false, true, true, false, false, BoardFooterTreatment.None)]
    [InlineData(true, false, false, false, false, BoardFooterTreatment.None)]
    [InlineData(true, false, true, true, false, BoardFooterTreatment.None)]
    [InlineData(true, false, true, false, true, BoardFooterTreatment.None)]
    public void Treatment_FadesAnyShownFooterUnlessAppearanceAsksForThePlainList(
        bool shown, bool contrastTheme, bool transparencyEffects, bool lessTransparency, bool moreContrast, BoardFooterTreatment expected) =>
        Assert.Equal(expected, BoardFooterEdgeFade.Treatment(shown, contrastTheme, transparencyEffects, lessTransparency, moreContrast));

    private sealed class FloatTolerance : IEqualityComparer<float>
    {
        public bool Equals(float x, float y) => Math.Abs(x - y) < 1e-5;

        public int GetHashCode(float obj) => 0;
    }
}
