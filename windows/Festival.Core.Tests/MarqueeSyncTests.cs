using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>Song header lockstep marquee (pattern <c>song-header</c> R2, web <c>useMarqueeSync</c>).</summary>
public class MarqueeSyncTests
{
    [Fact]
    public void TwoOverflowingLines_ShareTheWiderLinePlusGap() =>
        Assert.Equal(900 + MarqueeSync.Gap, MarqueeSync.Distance([900, 520]));

    [Fact]
    public void Distance_RoundsLikeTheWeb() => Assert.Equal(929, MarqueeSync.Distance([900.6, 400.2]));

    [Theory]
    [InlineData(new double[0])]
    [InlineData(new double[] { 0, 0 })]
    [InlineData(new double[] { 900, 0 })]
    [InlineData(new double[] { 0, 520 })]
    public void FewerThanTwoOverflowingLines_KeepTheirOwnDistance(double[] widths) => Assert.Null(MarqueeSync.Distance(widths));

    [Fact]
    public void ThreeLines_UseTheWidest() => Assert.Equal(1028, MarqueeSync.Distance([600, 1000, 0, 300]));

    [Fact]
    public void CustomGap() => Assert.Equal(510, MarqueeSync.Distance([500, 200], gap: 10));

    [Theory]
    [InlineData(928, 900, 28)]
    [InlineData(928, 520, 408)]
    [InlineData(500, 520, 0)]
    public void TrackGap_PutsTheCopyOneDistanceAway(double distance, double width, double gap) =>
        Assert.Equal(gap, MarqueeSync.TrackGap(distance, width));
}
