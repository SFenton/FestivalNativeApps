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
        Assert.Equal((0.25f, 0.1f, 0.25f, 1f), AccordionMotion.Spline);
    }

    [Fact]
    public void Accordion_CloseFadesOutThenCollapses()
    {
        var plan = AccordionMotion.Plan(open: false, heightProgress: 1, opacity: 1, motionAllowed: true);
        Assert.Equal(new AccordionPhase(TimeSpan.Zero, TimeSpan.FromMilliseconds(150)), plan.Fade);
        Assert.Equal(new AccordionPhase(TimeSpan.FromMilliseconds(150), TimeSpan.FromMilliseconds(150)), plan.Height);
        Assert.Equal(300, plan.Total.TotalMilliseconds);
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
    [InlineData(new double[0], 8, 0)]
    [InlineData(new[] { 90.0 }, 8, 90)]
    [InlineData(new[] { 90.0, 120, 140 }, 8, 366)]
    [InlineData(new[] { 90.0, 0, 140 }, 8, 238)]
    [InlineData(new[] { 90.0, double.NaN, 140 }, 8, 238)]
    public void ToolsRowWidth_SumsVisibleToolsAndGaps(double[] widths, double spacing, double expected) =>
        Assert.Equal(expected, Festival.Core.ViewModels.SongDetailLayout.ToolsRowWidth(widths, spacing));

    [Theory]
    // Compact window (500 epx, 452 epx bar): Paths, Item Shop and Quick Links leave the title too little room.
    [InlineData(452, 366, true)]
    // Paths alone fits beside the title.
    [InlineData(452, 90, false)]
    // Boundary: 40 art + 2 × 12 gaps + tools + 160 title.
    [InlineData(40 + 24 + 160 + 200, 200, false)]
    [InlineData(40 + 24 + 160 + 200 - 1, 200, true)]
    // Medium/wide bars keep one row; no tools or an unmeasured bar never move.
    [InlineData(1152, 366, false)]
    [InlineData(452, 0, false)]
    [InlineData(0, 366, false)]
    [InlineData(double.NaN, 366, false)]
    public void PinnedToolsBelowTitle_KeepsTheTitleReadable(double bar, double tools, bool below) =>
        Assert.Equal(below, Festival.Core.ViewModels.SongDetailLayout.PinnedToolsBelowTitle(bar, tools));

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

    #region Reflow motion
    [Fact]
    public void Reflow_UsesFluentPointToPointTiming()
    {
        Assert.Equal(300, ReflowTiming.Duration.TotalMilliseconds);
        Assert.Equal((0f, 0f, 0f, 1f), ReflowTiming.Spline);
    }

    [Fact]
    public void ReflowEase_StartsFastAndSettlesSlowly()
    {
        Assert.Equal(0, ReflowTiming.Ease(0));
        Assert.Equal(1, ReflowTiming.Ease(1));
        Assert.Equal(0, ReflowTiming.Ease(-1));
        Assert.Equal(1, ReflowTiming.Ease(2));
        Assert.Equal(0, ReflowTiming.Ease(double.NaN));
        // x(u) = u³, y(u) = 3u² − 2u³: halfway through, about 89% of the way.
        Assert.Equal(3 * Math.Pow(0.5, 2.0 / 3) - 1, ReflowTiming.Ease(0.5), 6);
        var last = 0.0;
        for (var t = 0.05; t <= 1; t += 0.05)
        {
            var eased = ReflowTiming.Ease(t);
            Assert.True(eased >= last);
            Assert.True(eased >= t, "decelerating: always ahead of linear");
            last = eased;
        }
    }

    [Fact]
    public void ReflowRemaining_RunsDownToZero()
    {
        Assert.Equal(1, ReflowTiming.Remaining(TimeSpan.Zero));
        Assert.Equal(0, ReflowTiming.Remaining(ReflowTiming.Duration));
        Assert.Equal(0, ReflowTiming.Remaining(TimeSpan.FromSeconds(5)));
        Assert.InRange(ReflowTiming.Remaining(TimeSpan.FromMilliseconds(150)), 0.1, 0.12);
    }

    [Theory]
    [InlineData(0, 1, true, 300)]
    [InlineData(1, 0, true, 300)]
    [InlineData(0.25, 1, true, 225)]
    [InlineData(0.6, 0, true, 180)]
    [InlineData(1, 1, true, 0)]
    [InlineData(0, 1, false, 0)]
    [InlineData(double.NaN, 1, true, 300)]
    public void ReflowPlan_CoversOnlyWhatIsLeft(double from, double to, bool motion, double expectedMs) =>
        Assert.Equal(expectedMs, ReflowTiming.Plan(from, to, motion).TotalMilliseconds, 3);

    [Fact]
    public void ReflowProgress_EasesToTheTarget()
    {
        var duration = ReflowTiming.Duration;
        Assert.Equal(0.2, ReflowTiming.Progress(0.2, 1, TimeSpan.Zero, duration));
        Assert.Equal(1, ReflowTiming.Progress(0.2, 1, duration, duration));
        Assert.Equal(0, ReflowTiming.Progress(1, 0, TimeSpan.FromSeconds(1), duration));
        Assert.Equal(0, ReflowTiming.Progress(1, 0, TimeSpan.Zero, TimeSpan.Zero));
        var mid = ReflowTiming.Progress(1, 0, TimeSpan.FromMilliseconds(150), duration);
        Assert.InRange(mid, 0.1, 0.12);
    }

    [Theory]
    [InlineData(600, 0, 600)]
    [InlineData(600, 1, 0)]
    [InlineData(600, 0.5, 300)]
    [InlineData(600, 2, 0)]
    [InlineData(600, double.NaN, 600)]
    [InlineData(-10, 0, 0)]
    public void ReflowPaneOffset_SlidesTheClosedPaneOut(double pane, double progress, double expected) =>
        Assert.Equal(expected, ReflowTiming.PaneOffset(pane, progress));

    [Theory]
    [InlineData(true, true, false, false, true)]
    [InlineData(false, true, false, false, false)]
    [InlineData(true, false, false, false, false)]
    [InlineData(true, true, true, false, false)]
    [InlineData(true, true, false, true, false)]
    public void ReflowAnimatesSplit_OnlyBetweenListAndSplit(bool motion, bool loaded, bool stackedBefore, bool stackedAfter, bool expected) =>
        Assert.Equal(expected, ReflowTiming.AnimatesSplit(motion, loaded, stackedBefore, stackedAfter));

    [Theory]
    [InlineData(0, 0, false)]
    [InlineData(0.4, -0.4, false)]
    [InlineData(0.5, 0, true)]
    [InlineData(0, -12, true)]
    [InlineData(double.NaN, 40, false)]
    [InlineData(double.PositiveInfinity, 0, false)]
    public void ReflowMoves_SkipsTinyShifts(double dx, double dy, bool expected) =>
        Assert.Equal(expected, ReflowTiming.Moves(dx, dy));

    [Theory]
    [InlineData(-50, 40, 800, false)]
    [InlineData(-50, 60, 800, true)]
    [InlineData(799, 10, 800, true)]
    [InlineData(800, 10, 800, false)]
    public void ReflowInView_OverlapsTheViewport(double top, double height, double viewport, bool expected) =>
        Assert.Equal(expected, ReflowTiming.InView(top, height, viewport));

    [Theory]
    [InlineData(0, 100, 500, true)]
    [InlineData(900, 100, 500, true)]
    [InlineData(1000, 100, 500, false)]
    [InlineData(-550, 100, 500, true)]
    [InlineData(-600, 100, 500, false)]
    [InlineData(-15000, 400, 500, false)]
    [InlineData(double.NaN, 100, 500, false)]
    public void ReflowNear_IgnoresParkedContainers(double top, double height, double viewport, bool expected) =>
        Assert.Equal(expected, ReflowTiming.Near(top, height, viewport));
    #endregion
}
