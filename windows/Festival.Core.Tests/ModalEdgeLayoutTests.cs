using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

// Issue #638: Notifications docks to the trailing edge in a wide window and becomes a bottom sheet in a narrow one.
public class ModalEdgeLayoutTests
{
    [Theory]
    [InlineData(500, ModalEdge.BottomSheet)]
    [InlineData(640.9, ModalEdge.BottomSheet)]
    [InlineData(641, ModalEdge.TrailingPanel)]
    [InlineData(900, ModalEdge.TrailingPanel)]
    [InlineData(1440, ModalEdge.TrailingPanel)]
    public void Edge_FollowsTheHamburgerThreshold(double width, ModalEdge expected) =>
        Assert.Equal(expected, ModalEdgeLayout.EdgeFor(width));

    [Fact]
    public void Edge_UsesTheGivenThreshold()
    {
        Assert.Equal(ModalEdge.BottomSheet, ModalEdgeLayout.EdgeFor(700, minimalBelow: 800));
        Assert.Equal(ModalEdge.TrailingPanel, ModalEdgeLayout.EdgeFor(800, minimalBelow: 800));
    }

    [Theory]
    [InlineData(1440, 900, 48, 460, 852, 48)]
    [InlineData(900, 700, 48, 460, 652, 48)]
    [InlineData(641, 500, 32, 460, 468, 32)]
    public void Panel_IsTheWebDrawerWidthAndFullHeightBelowTheCaption(
        double width, double height, double caption, double panelWidth, double panelHeight, double top)
    {
        var frame = ModalEdgeLayout.Frame(width, height, caption);
        Assert.Equal(new ModalEdgeFrame(ModalEdge.TrailingPanel, panelWidth, panelHeight, top), frame);
        Assert.Equal((panelWidth, 0d), frame.SlideFrom);
    }

    [Fact]
    public void Panel_KeepsWithin92PercentOfANarrowerWindow()
    {
        var frame = ModalEdgeLayout.Frame(480, 600, 48, minimalBelow: 400);
        Assert.Equal(ModalEdge.TrailingPanel, frame.Edge);
        Assert.Equal(480 * 0.92, frame.Width, 6);
    }

    [Fact]
    public void Sheet_SpansTheWidthAndTakes80PercentOfTheHeight()
    {
        var frame = ModalEdgeLayout.Frame(500, 800, 48);
        Assert.Equal(new ModalEdgeFrame(ModalEdge.BottomSheet, 500, 640, 160), frame);
        Assert.Equal((0d, 640d), frame.SlideFrom);
    }

    [Fact]
    public void Sheet_StaysBelowATallCaption()
    {
        var frame = ModalEdgeLayout.Frame(400, 200, 48);
        Assert.Equal(48, frame.Top);
        Assert.Equal(152, frame.Height);
    }

    [Fact]
    public void Frame_ClampsAnEmptyWindow()
    {
        Assert.Equal(new ModalEdgeFrame(ModalEdge.BottomSheet, 0, 0, 0), ModalEdgeLayout.Frame(-1, -1, 48));
        Assert.Equal(new ModalEdgeFrame(ModalEdge.TrailingPanel, 460, 0, 20), ModalEdgeLayout.Frame(1000, 20, 48));
    }

    [Fact]
    public void Constants_MatchTheWebDrawerAndModalTiming()
    {
        Assert.Equal(460, ModalEdgeLayout.PanelWidth);
        Assert.Equal(0.92, ModalEdgeLayout.PanelMaxWidthFraction);
        Assert.Equal(0.2, ModalEdgeLayout.SheetTopFraction);
        Assert.Equal(641, ModalEdgeLayout.MinimalNavigationBelow);
        Assert.Equal(TimeSpan.FromMilliseconds(250), ModalEdgeLayout.SlideDuration);
        Assert.Equal((0.25f, 0.1f, 0.25f, 1f), ModalEdgeLayout.SlideEase);
    }
}
