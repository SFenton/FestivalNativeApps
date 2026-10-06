using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>
/// The stagger window (pattern load-transition R5, issue #260): a load arm closes at the first scroll movement, so old
/// rows realized by scrolling never fade, while a Suggestions batch appended by scrolling still fades its new rows.
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
        Assert.False(arm.NeedsSettle);
        Assert.Equal(TimeSpan.Zero, arm.SinceArmed(Ms(500)));
        Assert.Null(arm.Delay(0, 5, Ms(0), 0, 0));
        Assert.False(arm.Scrolled(0, 500));
    }

    [Fact]
    public void Load_FadesTheFirstScreenWithinTheWindow()
    {
        var arm = Loaded();
        Assert.Equal(125, arm.Delay(0, 4, Ms(1100), 0, 0)!.Value.TotalMilliseconds);
        Assert.Equal(500, arm.Delay(3, 4, Ms(1100), 0, 0)!.Value.TotalMilliseconds);
        Assert.Null(arm.Delay(4, 4, Ms(1100), 0, 0));
        Assert.Equal(Ms(100), arm.SinceArmed(Ms(1100)));
        // The window still expires on its own.
        Assert.Null(arm.Delay(0, 4, Ms(2000), 0, 0));
    }

    [Fact]
    public void FirstScroll_ClosesTheLoadArmWithinTheWindow()
    {
        var arm = Loaded();
        Assert.True(arm.Scrolled(0, 240));
        Assert.False(arm.IsOpen(Ms(1200)));
        // An old row with an index inside the visible count, realized by that scroll 200 ms after the load: no fade.
        Assert.Null(arm.Delay(2, 4, Ms(1200), 0, 240));
        Assert.True(arm.SuppressedByScroll(Ms(1200), 2, 4));
        Assert.False(arm.SuppressedByScroll(Ms(2000), 2, 4));
        // A row past the visible count would never have faded, so the scroll kept nothing from it.
        Assert.False(arm.SuppressedByScroll(Ms(1200), 7, 4));
        // Scrolling back to where the page loaded does not reopen it.
        Assert.False(arm.Scrolled(0, 0));
        Assert.Null(arm.Delay(0, 4, Ms(1300), 0, 0));
    }

    [Fact]
    public void ScrollSeenOnlyAtRealization_StillClosesTheArm()
    {
        var arm = Loaded(0, 100);
        Assert.Null(arm.Delay(1, 4, Ms(1100), 0, 400));
        Assert.True(arm.SuppressedByScroll(Ms(1100), 1, 4));
    }

    [Theory]
    [InlineData(0.5, 0)]
    [InlineData(0, 0.99)]
    [InlineData(double.NaN, double.NaN)]
    public void LayoutRoundingAndUnknownOffsets_AreNotScrolling(double x, double y)
    {
        var arm = Loaded();
        Assert.False(arm.Scrolled(x, y));
        Assert.True(arm.IsOpen(Ms(1100)));
    }

    [Fact]
    public void HorizontalMovement_AlsoCloses()
    {
        var arm = Loaded();
        Assert.True(arm.Scrolled(StaggerArm.ScrollSlop, 0));
    }

    [Fact]
    public void BeforeTheFirstLayoutSettles_AResetToTheTopIsPartOfTheReload()
    {
        var arm = new StaggerArm();
        arm.Arm(0, Ms(1000));
        Assert.True(arm.NeedsSettle);
        // Songs' new sort scrolls to the top in the same layout as the re-arm: not the reader scrolling.
        Assert.False(arm.Scrolled(0, 0));
        Assert.False(arm.Scrolled(0, 5000));
        arm.Settle(double.NaN, 0);
        Assert.True(arm.NeedsSettle);
        arm.Settle(0, 0);
        Assert.False(arm.NeedsSettle);
        Assert.NotNull(arm.Delay(0, 4, Ms(1100), 0, 0));
        // A second settle keeps the first anchor.
        arm.Settle(0, 300);
        Assert.True(arm.Scrolled(0, 300));
    }

    [Fact]
    public void Reload_AfterAScroll_ReopensAndReanchors()
    {
        var arm = Loaded();
        arm.Scrolled(0, 800);
        arm.Arm(0, Ms(5000));
        Assert.True(arm.NeedsSettle);
        arm.Settle(0, 800);
        Assert.Equal(125, arm.Delay(0, 4, Ms(5100), 0, 800)!.Value.TotalMilliseconds);
    }

    [Fact]
    public void AppendedBatch_IsRevealedByScrollingAndFadesOnlyItsOwnRows()
    {
        var arm = Loaded();
        arm.Scrolled(0, 2000);
        arm.Arm(10, Ms(3000));
        Assert.Equal(10, arm.BatchStart);
        Assert.False(arm.NeedsSettle);
        // Scrolling on through the batch keeps it open; rows before it never fade again.
        Assert.False(arm.Scrolled(0, 4000));
        Assert.Null(arm.Delay(9, 4, Ms(3100), 0, 4000));
        Assert.Equal(125, arm.Delay(10, 4, Ms(3100), 0, 4000)!.Value.TotalMilliseconds);
        Assert.Equal(250, arm.Delay(11, 4, Ms(3200), 0, 4400)!.Value.TotalMilliseconds);
        Assert.False(arm.SuppressedByScroll(Ms(3200), 3, 4));
        // Back-to-back batches merge into one reveal from the earliest new row.
        arm.Arm(20, Ms(3300));
        Assert.Equal(10, arm.BatchStart);
        // A batch after the window starts its own.
        arm.Arm(30, Ms(9000));
        Assert.Equal(30, arm.BatchStart);
    }

    [Fact]
    public void BatchAppendedInsideTheLoadWindow_KeepsOnlyTheBatchOnceTheReaderScrolls()
    {
        var arm = Loaded();
        arm.Arm(10, Ms(1200));
        Assert.Equal(0, arm.BatchStart);
        Assert.Equal(125, arm.Delay(0, 4, Ms(1250), 0, 0)!.Value.TotalMilliseconds);
        // The scroll closes the load part only: it drops the load rows and keeps the batch.
        Assert.True(arm.Scrolled(0, 900));
        Assert.Equal(10, arm.BatchStart);
        Assert.Null(arm.Delay(3, 4, Ms(1300), 0, 900));
        Assert.True(arm.SuppressedByScroll(Ms(1300), 3, 4));
        Assert.False(arm.SuppressedByScroll(Ms(1300), 10, 4));
        Assert.Equal(125, arm.Delay(10, 4, Ms(1300), 0, 900)!.Value.TotalMilliseconds);
        Assert.False(arm.Scrolled(0, 1800));
        Assert.True(arm.IsOpen(Ms(1400)));
    }

    [Fact]
    public void LoadArmOverAnOpenBatch_ClosesOnScrollAgain()
    {
        var arm = new StaggerArm();
        arm.Arm(10, Ms(1000));
        arm.Arm(0, Ms(1100));
        Assert.Equal(0, arm.BatchStart);
        arm.Settle(0, 0);
        Assert.True(arm.Scrolled(0, 50));
    }

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
    public void LongerWindow_StillClosesOnTheFirstScroll()
    {
        var arm = new StaggerArm(Ms(5000));
        Assert.Equal(Ms(5000), arm.Window);
        Assert.Equal(FadeInTiming.ArmWindow, new StaggerArm().Window);
        arm.Arm(0, Ms(1000));
        arm.Settle(0, 0);
        Assert.True(arm.IsOpen(Ms(4000)));
        Assert.True(arm.Scrolled(0, 300));
        Assert.Null(arm.Delay(6, 8, Ms(4100), 0, 300));
        Assert.True(arm.SuppressedByScroll(Ms(4100), 6, 8));
        Assert.False(arm.SuppressedByScroll(Ms(6000), 6, 8));
    }
}
