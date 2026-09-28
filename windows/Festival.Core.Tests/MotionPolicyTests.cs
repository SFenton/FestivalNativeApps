using Festival.Core.Data;
using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>Web fade-in timing, motion switches and the Item Shop breathe colours.</summary>
public sealed class MotionPolicyTests
{
    [Fact]
    public void FadeIn_MatchesWebConstants()
    {
        Assert.Equal(400, FadeInTiming.Duration.TotalMilliseconds);
        Assert.Equal(125, FadeInTiming.Interval.TotalMilliseconds);
        Assert.Equal(12f, FadeInTiming.OffsetY);
        Assert.Equal((0f, 0f, 0.58f, 1f), FadeInTiming.EaseOut);
    }

    [Theory]
    [InlineData(0, 10, 125.0)]
    [InlineData(3, 10, 500.0)]
    [InlineData(9, 10, 1250.0)]
    public void StaggerDelay_StartsOneIntervalIn(int index, int max, double expectedMs) =>
        Assert.Equal(expectedMs, FadeInTiming.StaggerDelay(index, max)!.Value.TotalMilliseconds);

    [Theory]
    [InlineData(10, 10)]
    [InlineData(-1, 10)]
    [InlineData(20, 50)]
    public void StaggerDelay_RowsBeyondTheViewportDoNotAnimate(int index, int max) =>
        Assert.Null(FadeInTiming.StaggerDelay(index, max));

    [Theory]
    [InlineData(800, 64, 14)]
    [InlineData(64, 64, 2)]
    [InlineData(5000, 64, 20)]
    [InlineData(0, 64, 1)]
    [InlineData(800, 0, 1)]
    [InlineData(double.PositiveInfinity, 64, 1)]
    public void VisibleCount_IsRowsThatFitPlusOne(double viewport, double row, int expected) =>
        Assert.Equal(expected, FadeInTiming.VisibleCount(viewport, row));

    [Fact]
    public void WithinWindow_OnlyShortlyAfterLoading()
    {
        Assert.True(FadeInTiming.WithinWindow(TimeSpan.Zero));
        Assert.True(FadeInTiming.WithinWindow(TimeSpan.FromMilliseconds(999)));
        Assert.False(FadeInTiming.WithinWindow(FadeInTiming.ArmWindow));
        Assert.False(FadeInTiming.WithinWindow(TimeSpan.FromMilliseconds(-1)));
    }

    [Theory]
    [InlineData(true, false, false, true)]
    [InlineData(false, false, false, false)]
    [InlineData(true, true, false, false)]
    [InlineData(true, false, true, false)]
    public void Motion_NeedsSystemAnimationsAndNoReduceMotion(bool system, bool app, bool launch, bool expected) =>
        Assert.Equal(expected, MotionSwitch.Allowed(system, app, launch));

    [Fact]
    public void ShopPulse_WebColoursAndTiming()
    {
        Assert.Equal(3, ShopPulse.Cycle.TotalSeconds);
        Assert.Equal(0xF5121826u, ShopPulse.BaseArgb);
        Assert.Equal(0xFFCFA500u, ShopPulse.TargetArgb(ShopHighlight.New));
        Assert.Equal(0xFFEF4444u, ShopPulse.TargetArgb(ShopHighlight.LeavingTomorrow));
        Assert.Equal(0xFF1E7F46u, ShopPulse.TargetArgb(null));
    }

    [Fact]
    public void ShopPulse_ButtonNameCarriesTheStatus()
    {
        Assert.Equal("Open in Item Shop, Leaving Tomorrow", ShopPulse.ButtonName(ShopHighlight.LeavingTomorrow));
        Assert.Equal("Open in Item Shop, New", ShopPulse.ButtonName(ShopHighlight.New));
        Assert.Equal("Open in Item Shop", ShopPulse.ButtonName(null));
    }
}
