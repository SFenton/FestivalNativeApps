using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>
/// Issue #319 review (surface-materials R4): an unavailable board-pager arrow dims as a whole by default, but under a
/// contrast theme its card host stays fully opaque (solid Window surface, visible WindowText rim) and only the glyph
/// turns GrayText.
/// </summary>
public class PagerDimmingTests
{
    [Fact]
    public void AvailableArrow_IsFullyOpaque_WithItsNormalGlyph()
    {
        Assert.Equal(1, PagerDimming.HostOpacity(available: true, contrastTheme: false));
        Assert.Equal(1, PagerDimming.HostOpacity(available: true, contrastTheme: true));
        Assert.False(PagerDimming.GrayTextGlyph(available: true, contrastTheme: false));
        Assert.False(PagerDimming.GrayTextGlyph(available: true, contrastTheme: true));
    }

    [Fact]
    public void UnavailableArrow_DimsAsAWhole_OutsideContrastThemes()
    {
        Assert.Equal(0.3, PagerDimming.HostOpacity(available: false, contrastTheme: false));
        Assert.Equal(PagerDimming.DimmedOpacity, PagerDimming.HostOpacity(available: false, contrastTheme: false));
        Assert.False(PagerDimming.GrayTextGlyph(available: false, contrastTheme: false));
    }

    [Fact]
    public void UnavailableArrow_KeepsAnOpaqueHost_AndGrayTextGlyph_UnderAContrastTheme()
    {
        Assert.Equal(1, PagerDimming.HostOpacity(available: false, contrastTheme: true));
        Assert.True(PagerDimming.GrayTextGlyph(available: false, contrastTheme: true));
    }
}
