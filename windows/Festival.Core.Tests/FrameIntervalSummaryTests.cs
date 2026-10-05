using System.Globalization;
using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>The <c>--frame-stats</c> perf-log summary the Songs scroll stress journey reads (issue #247).</summary>
public sealed class FrameIntervalSummaryTests
{
    [Fact]
    public void Format_NoIntervals_WritesNothing() => Assert.Null(FrameIntervalSummary.Format([]));

    [Fact]
    public void Format_ReportsPercentilesMaxAndSlowFrames()
    {
        var intervals = Enumerable.Range(1, 100).Select(i => (double)i).Reverse().ToList();
        Assert.Equal("ui-frames count=100 p50=51.00 p95=96.00 p99=100.00 max=100.00 over33=67",
            FrameIntervalSummary.Format(intervals));
        Assert.Equal(1, intervals[0]);
    }

    [Theory]
    [InlineData(33.4, 0)]
    [InlineData(33.41, 1)]
    public void Format_SlowFramesAreThoseOverThreshold(double interval, int slow) =>
        Assert.EndsWith($"over33={slow}", FrameIntervalSummary.Format([8.3, interval]));

    [Fact]
    public void Format_AllSlow_CountsEveryFrame() =>
        Assert.Equal("ui-frames count=2 p50=300.00 p95=300.00 p99=300.00 max=300.00 over33=2",
            FrameIntervalSummary.Format([300, 40]));

    [Fact]
    public void Format_IgnoresCurrentCulture()
    {
        var culture = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo("de-DE");
            Assert.Contains("max=8.25", FrameIntervalSummary.Format([8.25]));
        }
        finally
        {
            CultureInfo.CurrentCulture = culture;
        }
    }
}
