using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>Centres a load in the bounded viewport, never in its header, footer or scrolling content.</summary>
public class LoadingRegionTests
{
    [Theory]
    [InlineData(700.0, null, null, 0.0, 0.0)]
    [InlineData(700.0, 120.0, null, 120.0, 0.0)]
    [InlineData(700.0, null, 640.0, 0.0, 60.0)]
    [InlineData(700.0, 120.0, 640.0, 120.0, 60.0)]
    [InlineData(700.0, -40.0, 760.0, 0.0, 0.0)]
    [InlineData(700.0, 800.0, 640.0, 640.0, 60.0)]
    [InlineData(700.0, 120.0, 80.0, 80.0, 620.0)]
    [InlineData(0.0, 100.0, 200.0, 0.0, 0.0)]
    public void Insets_ExcludeOnlyVisibleChrome(double height, double? header, double? footer, double top, double bottom)
    {
        Assert.Equal((top, bottom), LoadingRegion.Insets(height, header, footer));
    }

    [Theory]
    [InlineData(700.0, 120.0, 640.0, 120.0, 60.0)]
    [InlineData(700.0, 620.0, 640.0, 592.0, 60.0)]
    [InlineData(700.0, 700.0, 640.0, 592.0, 60.0)]
    [InlineData(700.0, 30.0, 40.0, 0.0, 652.0)]
    [InlineData(30.0, 10.0, 20.0, 0.0, 0.0)]
    public void Insets_KeepRoomForTheIndicator(double height, double? header, double? footer, double top, double bottom)
    {
        Assert.Equal((top, bottom), LoadingRegion.Insets(height, header, footer, 48));
    }

    [Fact]
    public void Insets_AreAFixedPointOfTheirOwnSlot()
    {
        // Re-resolving against the same slot must not grow the insets (a growing slot caused a layout cycle).
        var first = LoadingRegion.Insets(700, 680, 640, 48);
        Assert.Equal((592.0, 60.0), first);
        Assert.Equal(first, LoadingRegion.Insets(700, 680, 640, 48));
        Assert.True(700 - first.Top - first.Bottom >= 48);
    }
}
