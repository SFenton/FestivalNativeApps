using Festival.Core.Domain;

namespace Festival.Core.Tests;

public class AccessibilityPolicyTests
{
    [Theory]
    [InlineData(true, true, false, ArtworkMode.Hidden)]
    [InlineData(false, true, false, ArtworkMode.Hidden)]
    [InlineData(true, false, false, ArtworkMode.Hidden)]
    [InlineData(true, true, true, ArtworkMode.Hidden)]
    public void ContrastTheme_HidesDecorativeArtwork(bool animations, bool visible, bool reduce, ArtworkMode mode) =>
        Assert.Equal(mode, ArtworkPlaybackPolicy.Resolve(new ArtworkPolicyInputs(animations, visible, false, reduce, false, false, HighContrast: true)));

    [Fact]
    public void ContrastThemeOff_KeepsTheExistingPolicy() =>
        Assert.Equal(ArtworkMode.Animated, ArtworkPlaybackPolicy.Resolve(new ArtworkPolicyInputs(true, true, false, false, false, false)));
}
