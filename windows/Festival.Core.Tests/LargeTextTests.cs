using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>The one Windows large-text threshold (song-header R3 in-page wrap, Settings service-state stacking).</summary>
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

    [Fact]
    public void ServiceStateRow_SharesTheThreshold() => Assert.Equal(LargeText.Scale, ServiceInfoText.StackedStateTextScale);
}
