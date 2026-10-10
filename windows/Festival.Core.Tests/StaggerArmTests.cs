using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>
/// The first-load fade window (pattern load-transition R5, issues #260 and #323): a scroll while the entrance runs rushes
/// it (fades that haven't started start together, rows the scroll realizes join them), a scroll after it closes the
/// window so nothing replays, rows below the first screen fade with the last staggered row, a selected-row reveal holds
/// them for its jump, and a Suggestions batch appended by scrolling still fades only its new rows.
/// </summary>
public sealed class StaggerArmTests
{
    private static TimeSpan Ms(double ms) => TimeSpan.FromMilliseconds(ms);

    private static StaggerArm Loaded(double x = 0, double y = 0)
    {
        var arm = new StaggerArm();
        arm.Arm(0, Ms(1000));
        arm.Settle(x, y);
        return arm;
    }

    [Fact]
    public void BeforeAnyArm_NothingFades()
    {
        var arm = new StaggerArm();
        Assert.False(arm.IsOpen(Ms(0)));
        Assert.False(arm.IsRunning(Ms(0)));
        Assert.False(arm.NeedsSettle);
        Assert.Equal(TimeSpan.Zero, arm.SinceArmed(Ms(500)));
        Assert.Null(arm.Delay(0, 5, Ms(0), 0, 0));
        Assert.Null(arm.Entrance(Ms(100), Ms(0)));
        Assert.Equal(ArmScroll.None, arm.Scrolled(0, 500, Ms(0)));
        Assert.False(arm.Rush(Ms(0), Ms(500)));
    }

    [Fact]
    public void Load_StaggersTheFirstScreenAndFadesTheTailWithItsLastRow()
    {
        var arm = Loaded();
        Assert.Equal(125, arm.Delay(0, 4, Ms(1100), 0, 0)!.Value.TotalMilliseconds);
        Assert.Equal(500, arm.Delay(3, 4, Ms(1100), 0, 0)!.Value.TotalMilliseconds);
        // #323: a row below the first screen is never opaque during the entrance; it fades with the last staggered row.
        Assert.Equal(500, arm.Delay(4, 4, Ms(1100), 0, 0)!.Value.TotalMilliseconds);
        Assert.Equal(500, arm.Delay(30, 4, Ms(1100), 0, 0)!.Value.TotalMilliseconds);
        Assert.True(arm.IsTail(4, 4));
        Assert.False(arm.IsTail(3, 4));
        Assert.Equal(Ms(100), arm.SinceArmed(Ms(1100)));
    }

    [Fact]
    public void Load_EndsWithItsLastFade_ThenRowsShowInPlace()
    {
        var arm = Loaded();
        // Twelve visible rows: the last starts 1.5 s in (1100 + 1500) and ends 400 ms later, past the 1 s window.
        Assert.Equal(1500, arm.Delay(11, 12, Ms(1100), 0, 0)!.Value.TotalMilliseconds);
        Assert.True(arm.IsRunning(Ms(2900)));
        // A row realized after the window while the entrance runs waits for its last start, never ahead of the rows above.
        Assert.Equal(300, arm.Delay(13, 12, Ms(2300), 0, 0)!.Value.TotalMilliseconds);
        Assert.False(arm.IsRunning(Ms(3000)));
        Assert.Null(arm.Delay(0, 12, Ms(3000), 0, 0));
    }

    [Fact]
    public void ScrollDuringTheEntrance_RushesIt()
    {
        var arm = Loaded();
        Assert.Equal(500, arm.Delay(3, 4, Ms(1100), 0, 0)!.Value.TotalMilliseconds);
        Assert.Equal(ArmScroll.Rushed, arm.Scrolled(0, 240, Ms(1200)));
        Assert.True(arm.HasScrolled);
        Assert.True(arm.IsRushing(Ms(1200)));
        Assert.Equal(int.MaxValue, arm.RushLimit);
        Assert.False(arm.IsRunning(Ms(1200)));
        // Rows the scroll realizes while the rush runs fade together, at once: old first-screen rows and tail rows alike.
        Assert.Equal(TimeSpan.Zero, arm.Delay(2, 4, Ms(1250), 0, 240));
        Assert.Equal(TimeSpan.Zero, arm.Delay(12, 4, Ms(1550), 0, 900));
        Assert.False(arm.SuppressedByScroll(Ms(1300), 2, 4));
        // Once the rushed fades are done, rows just appear: scrolling never replays an entrance.
        Assert.Null(arm.Delay(2, 4, Ms(1600), 0, 1200));
        Assert.True(arm.SuppressedByScroll(Ms(1700), 2, 4));
        Assert.False(arm.SuppressedByScroll(Ms(2000), 2, 4));
        Assert.False(arm.SuppressedByScroll(Ms(1700), 7, 4));
        // Scrolling back to where the page loaded does not reopen it.
        Assert.Equal(ArmScroll.None, arm.Scrolled(0, 0, Ms(1700)));
        Assert.Null(arm.Delay(0, 4, Ms(1700), 0, 0));
    }

    [Fact]
    public void ScrollAfterTheEntrance_JustClosesIt()
    {
        var arm = Loaded();
        arm.Delay(3, 4, Ms(1000), 0, 0);
        Assert.Equal(ArmScroll.Closed, arm.Scrolled(0, 240, Ms(2100)));
        Assert.False(arm.IsRushing(Ms(2100)));
        Assert.Null(arm.Delay(6, 4, Ms(2100), 0, 240));
        Assert.False(arm.Rush(Ms(2100), Ms(500)));
    }

    [Fact]
    public void ScrollSeenOnlyAtRealization_StillRushes()
    {
        var arm = Loaded(0, 100);
        Assert.Equal(TimeSpan.Zero, arm.Delay(1, 4, Ms(1100), 0, 400));
        Assert.True(arm.IsRushing(Ms(1100)));
    }

    [Theory]
    [InlineData(0.5, 0)]
    [InlineData(0, 0.99)]
    [InlineData(double.NaN, double.NaN)]
    public void LayoutRoundingAndUnknownOffsets_AreNotScrolling(double x, double y)
    {
        var arm = Loaded();
        Assert.Equal(ArmScroll.None, arm.Scrolled(x, y, Ms(1100)));
        Assert.True(arm.IsOpen(Ms(1100)));
        Assert.False(arm.HasScrolled);
    }

    [Fact]
    public void HorizontalMovement_AlsoRushes() =>
        Assert.Equal(ArmScroll.Rushed, Loaded().Scrolled(StaggerArm.ScrollSlop, 0, Ms(1100)));

    [Fact]
    public void BeforeTheFirstLayoutSettles_AResetToTheTopIsPartOfTheReload()
    {
        var arm = new StaggerArm();
        arm.Arm(0, Ms(1000));
        Assert.True(arm.NeedsSettle);
        // Songs' new sort scrolls to the top in the same layout as the re-arm: not the reader scrolling.
        Assert.Equal(ArmScroll.None, arm.Scrolled(0, 0, Ms(1000)));
        Assert.Equal(ArmScroll.None, arm.Scrolled(0, 5000, Ms(1000)));
        arm.Settle(double.NaN, 0);
        Assert.True(arm.NeedsSettle);
        arm.Settle(0, 0);
        Assert.False(arm.NeedsSettle);
        Assert.NotNull(arm.Delay(0, 4, Ms(1100), 0, 0));
        // A second settle keeps the first anchor.
        arm.Settle(0, 300);
        Assert.Equal(ArmScroll.Rushed, arm.Scrolled(0, 300, Ms(1100)));
    }

    [Fact]
    public void Reload_AfterAScroll_ReopensAndReanchors()
    {
        var arm = Loaded();
        var generation = arm.Generation;
        arm.Scrolled(0, 800, Ms(1100));
        arm.Arm(0, Ms(5000));
        Assert.NotEqual(generation, arm.Generation);
        Assert.False(arm.HasScrolled);
        Assert.False(arm.IsRushing(Ms(5000)));
        Assert.True(arm.NeedsSettle);
        arm.Settle(0, 800);
        Assert.Equal(125, arm.Delay(0, 4, Ms(5100), 0, 800)!.Value.TotalMilliseconds);
    }

    [Fact]
    public void AppendedBatch_IsRevealedByScrollingAndFadesOnlyItsOwnRows()
    {
        var arm = Loaded();
        arm.Scrolled(0, 2000, Ms(3000));
        arm.Arm(10, Ms(3000));
        Assert.Equal(10, arm.BatchStart);
        Assert.False(arm.NeedsSettle);
        // Scrolling on through the batch keeps it open and never rushes it; rows before it never fade again.
        Assert.Equal(ArmScroll.None, arm.Scrolled(0, 4000, Ms(3100)));
        Assert.False(arm.Rush(Ms(3100), Ms(500)));
        Assert.Null(arm.Delay(9, 4, Ms(3100), 0, 4000));
        Assert.Equal(125, arm.Delay(10, 4, Ms(3100), 0, 4000)!.Value.TotalMilliseconds);
        Assert.Equal(250, arm.Delay(11, 4, Ms(3200), 0, 4400)!.Value.TotalMilliseconds);
        Assert.False(arm.SuppressedByScroll(Ms(3200), 3, 4));
        // Once the batch has begun to show, the next batch is new content and staggers from its own first row (#532).
        arm.Arm(20, Ms(3300));
        Assert.Equal(20, arm.BatchStart);
        Assert.Equal(125, arm.Delay(20, 4, Ms(3300), 0, 6000)!.Value.TotalMilliseconds);
        // A batch after the window starts its own.
        arm.Arm(30, Ms(9000));
        Assert.Equal(30, arm.BatchStart);
    }

    [Fact]
    public void BatchAppendedInsideTheLoadWindow_RushesOnlyTheLoadRowsOnceTheReaderScrolls()
    {
        var arm = Loaded();
        var generation = arm.Generation;
        arm.Arm(10, Ms(1200));
        Assert.Equal(generation, arm.Generation);
        Assert.Equal(0, arm.BatchStart);
        Assert.Equal(125, arm.Delay(0, 4, Ms(1250), 0, 0)!.Value.TotalMilliseconds);
        // The scroll rushes the load part only and keeps the batch, which stays a plain stagger.
        Assert.Equal(ArmScroll.Rushed, arm.Scrolled(0, 900, Ms(1300)));
        Assert.Equal(10, arm.BatchStart);
        Assert.Equal(10, arm.RushLimit);
        Assert.Equal(TimeSpan.Zero, arm.Delay(3, 4, Ms(1300), 0, 900));
        Assert.Equal(125, arm.Delay(10, 4, Ms(1300), 0, 900)!.Value.TotalMilliseconds);
        Assert.Equal(ArmScroll.None, arm.Scrolled(0, 1800, Ms(1400)));
        Assert.True(arm.IsOpen(Ms(1400)));
        Assert.Null(arm.Delay(3, 4, Ms(1800), 0, 1800));
    }

    [Fact]
    public void BatchAppendedWhileTheRushRuns_StartsAtItsOwnRowAndKeepsTheLoadRush()
    {
        // Suggestions (issue #532): the reader's scroll rushes the load, and the batch it generates lands before the
        // rush's fades are done. The load has ended, so the batch must not merge into it from row 0.
        var arm = Loaded();
        Assert.Equal(ArmScroll.Rushed, arm.Scrolled(0, 900, Ms(1300)));
        var generation = arm.Generation;
        arm.Arm(10, Ms(1400));
        Assert.Equal(10, arm.BatchStart);
        Assert.NotEqual(generation, arm.Generation);
        // Old rows the scroll realizes while the rush runs still fade at once; the batch is a plain stagger, never rushed.
        Assert.True(arm.IsRushing(Ms(1450)));
        Assert.Equal(10, arm.RushLimit);
        Assert.Equal(TimeSpan.Zero, arm.Delay(2, 4, Ms(1450), 0, 900));
        Assert.Equal(125, arm.Delay(10, 4, Ms(1450), 0, 900)!.Value.TotalMilliseconds);
        Assert.False(arm.RushReaches(10));
        // After the rush, rows already shown never fade again. Card 10 has begun to fade, so the next batch inside the
        // window is new content and staggers from its own first row.
        Assert.Null(arm.Delay(1, 4, Ms(1800), 0, 0));
        arm.Arm(20, Ms(2000));
        Assert.Equal(20, arm.BatchStart);
        Assert.Null(arm.Delay(2, 4, Ms(2100), 0, 0));
        Assert.Equal(125, arm.Delay(20, 4, Ms(2100), 0, 0)!.Value.TotalMilliseconds);
    }

    [Fact]
    public void BatchesAppendedBeforeAnyCardFades_FormOneReveal()
    {
        var arm = Loaded();
        arm.Scrolled(0, 900, Ms(3000));
        arm.Arm(10, Ms(3100));
        arm.Arm(13, Ms(3200));
        Assert.Equal(10, arm.BatchStart);
        Assert.Equal(125, arm.Delay(10, 4, Ms(3300), 0, 900)!.Value.TotalMilliseconds);
    }

    [Fact]
    public void BatchCardRealizedAgainInsideItsWindow_NeverReplays()
    {
        // Suggestions (issue #532): a card the batch faded, recycled and realized again while the window is open.
        var arm = Loaded();
        arm.Scrolled(0, 900, Ms(3000));
        arm.Arm(10, Ms(3100));
        Assert.Equal(250, arm.Delay(11, 4, Ms(3100), 0, 900)!.Value.TotalMilliseconds);
        // Before its fade began it keeps the same start; after, it shows in place.
        Assert.Equal(150, arm.Delay(11, 4, Ms(3200), 0, 900)!.Value.TotalMilliseconds);
        Assert.Null(arm.Delay(11, 4, Ms(3400), 0, 0));
        // A card of the batch not shown yet still fades.
        Assert.NotNull(arm.Delay(12, 4, Ms(3400), 0, 0));
        // A new load forgets what faded: its rows stagger again.
        arm.Arm(0, Ms(5000));
        arm.Settle(0, 0);
        Assert.Equal(125, arm.Delay(0, 4, Ms(5000), 0, 0)!.Value.TotalMilliseconds);
    }

    [Fact]
    public void LoadArmDuringARush_EndsTheRush()
    {
        var arm = Loaded();
        arm.Scrolled(0, 900, Ms(1300));
        arm.Arm(0, Ms(1400));
        Assert.Equal(0, arm.BatchStart);
        Assert.False(arm.IsRushing(Ms(1400)));
        Assert.Equal(0, arm.RushLimit);
    }

    [Fact]
    public void LoadArmOverAnOpenBatch_RushesOnScrollAgain()
    {
        var arm = new StaggerArm();
        arm.Arm(10, Ms(1000));
        arm.Arm(0, Ms(1100));
        Assert.Equal(0, arm.BatchStart);
        arm.Settle(0, 0);
        Assert.Equal(ArmScroll.Rushed, arm.Scrolled(0, 50, Ms(1200)));
    }

    [Fact]
    public void ExpectedScroll_HoldsTailRowsUntilTheJumpRushesThem()
    {
        var arm = Loaded();
        var token = arm.ExpectScroll(Ms(1000 + 1100));
        Assert.Equal(Ms(2100), arm.ExpectedScroll);
        // First-screen rows keep their stagger; tail rows wait for the jump rather than fading in unseen.
        Assert.Equal(125, arm.Delay(0, 4, Ms(1000), 0, 0)!.Value.TotalMilliseconds);
        Assert.Equal(1100, arm.Delay(6, 4, Ms(1000), 0, 0)!.Value.TotalMilliseconds);
        // A tail row realized later keeps its own delay, which already lands after the jump (the jump rushes it).
        Assert.Equal(500, arm.Delay(8, 4, Ms(1700), 0, 0)!.Value.TotalMilliseconds);
        // The stagger has ended, but the held rows keep the entrance running until the jump.
        Assert.True(arm.IsRunning(Ms(2100)));
        Assert.False(arm.HasScrolled);
        Assert.True(arm.Rush(Ms(2100), FadeInTiming.RevealScroll));
        // Rows the jump realizes while it runs fade in together, at once.
        Assert.Equal(TimeSpan.Zero, arm.Delay(20, 4, Ms(2700), 0, 900));
        Assert.Null(arm.Delay(20, 4, Ms(3000), 0, 900));
        // The jump's own movement is not the reader's; a stale reveal's token changes nothing.
        Assert.Equal(ArmScroll.None, arm.Scrolled(0, 900, Ms(2150)));
        arm.EndExpectation(token);
        Assert.Null(arm.ExpectedScroll);
    }

    [Fact]
    public void CalledOffExpectation_ReleasesHeldRows()
    {
        var arm = Loaded();
        var stale = arm.ExpectScroll(Ms(3000));
        var token = arm.ExpectScroll(Ms(2500));
        arm.EndExpectation(stale);
        Assert.Equal(Ms(2500), arm.ExpectedScroll);
        arm.EndExpectation(token);
        Assert.Null(arm.ExpectedScroll);
        Assert.Equal(500, arm.Delay(6, 4, Ms(1000), 0, 0)!.Value.TotalMilliseconds);
    }

    [Fact]
    public void ReaderScrollBeforeTheReveal_IsReported()
    {
        var arm = Loaded();
        arm.ExpectScroll(Ms(2000));
        Assert.Equal(ArmScroll.Rushed, arm.Scrolled(0, 300, Ms(1500)));
        Assert.True(arm.HasScrolled);
        Assert.Null(arm.ExpectedScroll);
        Assert.False(arm.Rush(Ms(2000), Ms(500)));
    }

    [Fact]
    public void Entrance_FollowsThePageChoreographyUntilAScrollRushesIt()
    {
        var arm = Loaded();
        Assert.Equal(Ms(300), arm.Entrance(Ms(300), Ms(1000)));
        Assert.Equal(Ms(1650), arm.Entrance(Ms(1650), Ms(1000)));
        // Past the window, a late card waits for the entrance's last start (2650) rather than popping in.
        Assert.Equal(Ms(550), arm.Entrance(Ms(300), Ms(2100)));
        Assert.Equal(Ms(450), arm.Entrance(Ms(300), Ms(2200)));
        Assert.Equal(ArmScroll.Rushed, arm.Scrolled(0, 500, Ms(2300)));
        Assert.Equal(TimeSpan.Zero, arm.Entrance(Ms(300), Ms(2400)));
        Assert.Null(arm.Entrance(Ms(300), Ms(2800)));
    }

    [Fact]
    public void RushReaches_EveryLoadRowAndEntranceElement_NeverAnAppendedBatch()
    {
        // Before a rush nothing is reached: a pinned row or page section keeps its own delay.
        var arm = Loaded();
        Assert.False(arm.RushReaches(-1));
        Assert.False(arm.RushReaches(0));
        // A board's pinned row (-1) is rushed with its rows by the reader's scroll (issue #323, load-transition R5).
        Assert.Equal(ArmScroll.Rushed, arm.Scrolled(0, 300, Ms(1100)));
        Assert.True(arm.RushReaches(-1));
        Assert.True(arm.RushReaches(0));
        Assert.True(arm.RushReaches(40));

        // ... and by a selected-row reveal's automatic scroll.
        var revealed = Loaded();
        Assert.True(revealed.Rush(Ms(1500), FadeInTiming.RevealScroll));
        Assert.True(revealed.RushReaches(-1));

        // A batch appended into the load is never rushed; the load's rows and entrance elements are.
        var batched = Loaded();
        batched.Arm(10, Ms(1200));
        Assert.Equal(ArmScroll.Rushed, batched.Scrolled(0, 900, Ms(1300)));
        Assert.True(batched.RushReaches(-1));
        Assert.True(batched.RushReaches(9));
        Assert.False(batched.RushReaches(10));

        // A scroll after the entrance only closes it: nothing pending is restarted.
        var closed = Loaded();
        Assert.Equal(ArmScroll.Closed, closed.Scrolled(0, 300, Ms(2600)));
        Assert.False(closed.RushReaches(-1));

        // A reload re-arms: the previous rush reaches nothing of the new entrance.
        arm.Arm(0, Ms(5000));
        Assert.False(arm.RushReaches(-1));
    }

    [Theory]
    [InlineData(0, 10, 525)]
    [InlineData(4, 10, 1025)]
    [InlineData(9, 10, 1650)]
    [InlineData(17, 10, 1650)]
    [InlineData(24, 40, 2900)]
    public void RevealWait_IsTheRowsOwnEntrance(int index, int visible, double ms) =>
        Assert.Equal(Ms(ms), FadeInTiming.RevealWait(index, visible));

    [Theory]
    [InlineData(0, 125)]
    [InlineData(4, 500)]
    [InlineData(40, 2500)]
    public void TailDelay_IsTheLastStaggeredRows(int visible, double ms) =>
        Assert.Equal(Ms(ms), FadeInTiming.TailDelay(visible));

    [Theory]
    [InlineData("5000", 5000)]
    [InlineData("60000", 60000)]
    [InlineData("0", null)]
    [InlineData("60001", null)]
    [InlineData("-5", null)]
    [InlineData("abc", null)]
    [InlineData(null, null)]
    public void ParseWindow_AcceptsOnlyBoundedMilliseconds(string? raw, int? expected) =>
        Assert.Equal(expected is { } ms ? Ms(ms) : null, StaggerArm.ParseWindow(raw));

    [Fact]
    public void LongerWindow_StillRushesOnTheFirstScroll()
    {
        var arm = new StaggerArm(Ms(5000));
        Assert.Equal(Ms(5000), arm.Window);
        Assert.Equal(FadeInTiming.ArmWindow, new StaggerArm().Window);
        arm.Arm(0, Ms(1000));
        arm.Settle(0, 0);
        Assert.True(arm.IsOpen(Ms(4000)));
        Assert.Equal(ArmScroll.Rushed, arm.Scrolled(0, 300, Ms(4000)));
        Assert.Equal(TimeSpan.Zero, arm.Delay(6, 8, Ms(4100), 0, 300));
        Assert.Null(arm.Delay(6, 8, Ms(4500), 0, 300));
        Assert.True(arm.SuppressedByScroll(Ms(4500), 6, 8));
        Assert.False(arm.SuppressedByScroll(Ms(6000), 6, 8));
    }

    [Fact]
    public void AppendedBatch_KeepsTheLoadsScroll()
    {
        var arm = Loaded();
        Assert.Equal(ArmScroll.Rushed, arm.Scrolled(0, 120, Ms(1100)));
        arm.Arm(20, Ms(1300));
        Assert.True(arm.HasScrolled);
    }

    [Fact]
    public void LayoutRounding_IsNotTheReaderScrolling()
    {
        var arm = Loaded(0, 100);
        Assert.Equal(ArmScroll.None, arm.Scrolled(0, 100.5, Ms(1100)));
        Assert.False(arm.HasScrolled);
    }
}