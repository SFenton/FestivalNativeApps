using Festival.Core.Domain;
using Xunit;

namespace Festival.Core.Tests;

/// <summary>The shared card surface's opaque fallback (surface-materials R4; issue #397).</summary>
public sealed class CardSurfaceOpacityTests
{
    [Theory]
    [InlineData(true, false, false, true)]
    [InlineData(false, false, false, false)]
    [InlineData(true, true, false, false)]
    [InlineData(true, false, true, false)]
    [InlineData(false, true, true, false)]
    public void IsTranslucent_OnlyWithTransparencyOnAndNoAccessibilitySetting(bool effects, bool less, bool more, bool expected) =>
        Assert.Equal(expected, CardSurfaceOpacity.IsTranslucent(effects, less, more));

    [Fact]
    public void Alpha_IsTheFrostedCardOrOpaque()
    {
        Assert.Equal(0xC7, CardSurfaceOpacity.Alpha(true, false, false));
        Assert.Equal(0xFF, CardSurfaceOpacity.Alpha(false, false, false));
        Assert.Equal(0xFF, CardSurfaceOpacity.Alpha(true, true, false));
        Assert.Equal(0xFF, CardSurfaceOpacity.Alpha(true, false, true));
    }

    [Fact]
    public void IncreaseContrast_MakesCardsOpaqueLikeTheBoardFadeHardEdge()
    {
        // The same settings that keep the scroll-edge hard edge (R7) make the cards behind it opaque (R4).
        foreach (var effects in new[] { true, false })
            foreach (var less in new[] { true, false })
                foreach (var more in new[] { true, false })
                    Assert.Equal(SongHeaderEdgeFade.IsEnabled(false, effects, less, more),
                        CardSurfaceOpacity.IsTranslucent(effects, less, more));
    }
}
