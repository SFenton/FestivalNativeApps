using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>The one Windows large-text threshold (shell title bar, song-header R3 in-page wrap).</summary>
public class LargeTextTests
{
    [Theory]
    [InlineData(1.0, false)]
    [InlineData(1.25, false)]
    [InlineData(1.49, false)]
    [InlineData(1.5, true)]
    [InlineData(2.0, true)]
    [InlineData(2.25, true)]
    public void AppliesFrom150PercentText(double scale, bool large) => Assert.Equal(large, LargeText.Applies(scale));
}
