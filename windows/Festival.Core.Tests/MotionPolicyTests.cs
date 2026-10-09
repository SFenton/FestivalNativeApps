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
        // Exits (Songs Jump, issue #231) use WinUI's fast control duration, quicker than the entrance.
        Assert.Equal(167, FadeInTiming.HideDuration.TotalMilliseconds);
        Assert.True(FadeInTiming.HideDuration < FadeInTiming.Duration);
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
    [InlineData(0, 0, 3, 125.0)]
    [InlineData(2, 0, 3, 375.0)]
    [InlineData(10, 10, 3, 125.0)]
    [InlineData(12, 10, 3, 375.0)]
    [InlineData(1, -5, 3, 250.0)]
    public void BatchDelay_StaggersANewBatchFromItsFirstRow(int index, int start, int max, double expectedMs) =>
        Assert.Equal(expectedMs, FadeInTiming.BatchDelay(index, start, max)!.Value.TotalMilliseconds);

    [Theory]
    [InlineData(9, 10, 3)]
    [InlineData(0, 10, 3)]
    [InlineData(13, 10, 3)]
    [InlineData(3, 0, 3)]
    public void BatchDelay_AlreadyRevealedAndOffscreenRowsDoNotAnimate(int index, int start, int max) =>
        Assert.Null(FadeInTiming.BatchDelay(index, start, max));

    [Theory]
    [InlineData(10, 16, 200, 10)]
    [InlineData(0, 16, 999, 0)]
    [InlineData(10, 16, 1000, 16)]
    [InlineData(10, 16, -1, 16)]
    [InlineData(16, 0, 200, 0)]
    public void MergeBatchStart_KeepsTheEarliestUnrevealedRowWithinTheWindow(int current, int next, int sinceMs, int expected) =>
        Assert.Equal(expected, FadeInTiming.MergeBatchStart(current, next, TimeSpan.FromMilliseconds(sinceMs)));

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

    [Fact]
    public void PinnedRow_RevealsWithTheFirstRow()
    {
        Assert.Equal(FadeInTiming.StaggerDelay(0, 1), PinnedRowReveal.RevealDelay);
        Assert.Equal(125, PinnedRowReveal.RevealDelay.TotalMilliseconds);
    }

    [Theory]
    [InlineData(false, true, LoadSwapPhase.ContentIn, true)]
    [InlineData(true, true, LoadSwapPhase.ContentIn, false)]
    [InlineData(true, false, LoadSwapPhase.ContentIn, false)]
    [InlineData(false, false, LoadSwapPhase.ContentIn, false)]
    [InlineData(false, true, LoadSwapPhase.Loading, false)]
    [InlineData(false, true, LoadSwapPhase.SpinnerOut, false)]
    [InlineData(false, true, LoadSwapPhase.ContentOut, false)]
    public void PinnedRow_FadesOnItsOwnOnlyWhenItArrivesOverAShownBoard(bool had, bool has, LoadSwapPhase phase, bool expected) =>
        Assert.Equal(expected, PinnedRowReveal.FadesOnArrival(had, has, phase));

    [Theory]
    [InlineData(true, false, false, true)]
    [InlineData(false, false, false, false)]
    [InlineData(true, true, false, false)]
    [InlineData(true, false, true, false)]
    public void Motion_NeedsSystemAnimationsAndNoReduceMotion(bool system, bool app, bool launch, bool expected) =>
        Assert.Equal(expected, MotionSwitch.Allowed(system, app, launch));

    [Fact]
    public void Accordion_OpenGrowsThenFadesIn()
    {
        var plan = AccordionMotion.Plan(open: true, heightProgress: 0, opacity: 0, motionAllowed: true);
        Assert.Equal(150, AccordionMotion.PhaseDuration.TotalMilliseconds);
        Assert.Equal(new AccordionPhase(TimeSpan.Zero, TimeSpan.FromMilliseconds(150)), plan.Height);
        Assert.Equal(new AccordionPhase(TimeSpan.FromMilliseconds(150), TimeSpan.FromMilliseconds(150)), plan.Fade);
        Assert.Equal(300, plan.Total.TotalMilliseconds);
        Assert.Equal((0f, 0f, 0f, 1f), AccordionMotion.EnterSpline);
    }

    [Fact]
    public void Accordion_CloseFadesOutThenCollapses()
    {
        var plan = AccordionMotion.Plan(open: false, heightProgress: 1, opacity: 1, motionAllowed: true);
        Assert.Equal(new AccordionPhase(TimeSpan.Zero, TimeSpan.FromMilliseconds(150)), plan.Fade);
        Assert.Equal(new AccordionPhase(TimeSpan.FromMilliseconds(150), TimeSpan.FromMilliseconds(150)), plan.Height);
        Assert.Equal(300, plan.Total.TotalMilliseconds);
        Assert.Equal((1f, 1f, 0f, 1f), AccordionMotion.ExitSpline);
    }

    [Fact]
    public void Accordion_InterruptedMoveRunsOnlyTheRest()
    {
        // Reopened while half faded out: the height is still full, so only the fade back in remains.
        var reopen = AccordionMotion.Plan(open: true, heightProgress: 1, opacity: 0.5, motionAllowed: true);
        Assert.Equal(TimeSpan.Zero, reopen.Height.Duration);
        Assert.Equal(new AccordionPhase(TimeSpan.Zero, TimeSpan.FromMilliseconds(75)), reopen.Fade);

        // Closed while still growing: nothing has faded in yet, so it collapses straight away from the reached height.
        var close = AccordionMotion.Plan(open: false, heightProgress: 0.4, opacity: 0, motionAllowed: true);
        Assert.Equal(TimeSpan.Zero, close.Fade.Duration);
        Assert.Equal(new AccordionPhase(TimeSpan.Zero, TimeSpan.FromMilliseconds(60)), close.Height);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void Accordion_IsInstantWithoutMotion(bool open)
    {
        var plan = AccordionMotion.Plan(open, heightProgress: open ? 0 : 1, opacity: open ? 0 : 1, motionAllowed: false);
        Assert.Equal(TimeSpan.Zero, plan.Total);
        Assert.Equal(TimeSpan.Zero, plan.Height.Duration);
        Assert.Equal(TimeSpan.Zero, plan.Fade.Duration);
    }

    [Theory]
    [InlineData(50, 100, 0.5)]
    [InlineData(150, 100, 1)]
    [InlineData(-5, 100, 0)]
    [InlineData(10, 0, 1)]
    [InlineData(double.NaN, 100, 1)]
    public void Accordion_ProgressIsClampedFraction(double current, double open, double expected) =>
        Assert.Equal(expected, AccordionMotion.Progress(current, open), 3);

    [Fact]
    public void Accordion_ClampsOutOfRangeInputs()
    {
        var plan = AccordionMotion.Plan(open: true, heightProgress: double.NaN, opacity: 2, motionAllowed: true);
        Assert.Equal(150, plan.Height.Duration.TotalMilliseconds);
        Assert.Equal(TimeSpan.Zero, plan.Fade.Duration);
    }

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

    [Theory]
    [InlineData(100, 150, 57, 0)]
    [InlineData(162, 150, 57, 0)]
    [InlineData(163, 150, 57, 57)]
    [InlineData(900, 150, 0, 64)]
    [InlineData(900, 150, double.NaN, 64)]
    public void PinnedHeaderInset_CoversOnlyOncePinned(double offset, double fullHeader, double pinned, double expected)
    {
        Assert.Equal(expected, Festival.Core.ViewModels.SongDetailLayout.PinnedHeaderInset(offset, fullHeader, pinned));
        Assert.Equal(expected > 0, Festival.Core.ViewModels.SongDetailLayout.PinsHeader(offset, fullHeader));
    }

    [Fact]
    public void AccuracyValue_ZeroWhenMissing()
    {
        Assert.Equal(0, new Festival.Core.ViewModels.LeaderboardRow(new LeaderboardEntry()).AccuracyValue);
        Assert.Equal(990_000, new Festival.Core.ViewModels.LeaderboardRow(new LeaderboardEntry { Accuracy = 990_000 }).AccuracyValue);
    }
}
