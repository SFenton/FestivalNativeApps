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

    [Fact]
    public void ShopPulse_BreatheIsSteppedAtThirtyPerSecond()
    {
        var steps = ShopPulse.BreatheSteps();
        Assert.Equal(30, ShopPulse.StepsPerSecond);
        Assert.Equal(91, steps.Count);
        Assert.Equal(0f, steps[0].Progress);
        Assert.Equal(0f, steps[0].Level, 3);
        Assert.Equal(1f, steps[^1].Progress);
        Assert.Equal(0f, steps[^1].Level, 3);
        Assert.Equal(1f, steps.MaxBy(s => s.Level).Level, 3);
        Assert.Equal(0.5f, steps.MaxBy(s => s.Level).Progress, 3);
        Assert.All(steps.Zip(steps.Skip(1)), pair => Assert.True(pair.Second.Progress > pair.First.Progress));
        Assert.All(steps, s => Assert.InRange(s.Level, 0f, 1f));
    }
}

/// <summary>Song Detail layout rules (Intensity columns) and the accuracy badge value.</summary>
public sealed class SongDetailLayoutTests
{
    [Theory]
    [InlineData(500, 9, 3)]
    [InlineData(900, 9, 3)]
    [InlineData(1100, 9, 9)]
    [InlineData(1100, 3, 3)]
    [InlineData(600, 4, 4)]
    [InlineData(double.NaN, 9, 3)]
    public void IntensityColumns_ThreePerRowUnlessAllFit(double width, int count, int columns) =>
        Assert.Equal(columns, Festival.Core.ViewModels.SongDetailLayout.IntensityColumns(width, count));

    [Theory]
    [InlineData(500, 48, 90, 410, 138)]
    [InlineData(500, 48, 120, 380, 168)]
    [InlineData(500, 48, 0, 436, 112)]
    [InlineData(10, 48, double.NaN, -54, 112)]
    [InlineData(0, -5, 57, -64, 64)]
    public void RevealBelowPinnedHeader_KeepsTheHeaderHeightAbove(double top, double height, double header, double expectedTop,
        double expectedHeight)
    {
        var (newTop, newHeight) = Festival.Core.ViewModels.SongDetailLayout.RevealBelowPinnedHeader(top, height, header);
        Assert.Equal(expectedTop, newTop);
        Assert.Equal(expectedHeight, newHeight);
    }

    [Fact]
    public void AccuracyValue_ZeroWhenMissing()
    {
        Assert.Equal(0, new Festival.Core.ViewModels.LeaderboardRow(new LeaderboardEntry()).AccuracyValue);
        Assert.Equal(990_000, new Festival.Core.ViewModels.LeaderboardRow(new LeaderboardEntry { Accuracy = 990_000 }).AccuracyValue);
    }
}
