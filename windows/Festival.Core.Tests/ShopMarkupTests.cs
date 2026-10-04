using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #206's Item Shop keyboard, Narrator and text-scaling fixes in markup: the tile grid is one Tab stop
/// with arrow keys between tiles (the live Shop has well over a hundred tiles), every full-page state title is a
/// heading, and the tile's Leaving Tomorrow pill wraps at large text sizes. The live checks are the <c>kb-shop-*</c>
/// journeys in <c>tools/windows/journeys/a11y-keyboard.json</c> and the <c>text-200</c> a11y matrix runs.
/// </summary>
public class ShopMarkupTests
{
    private static readonly XDocument Page = XDocument.Load(
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App", "Pages", "ShopPage.xaml"));

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    [Fact]
    public void TileGrid_IsOneTabStopWithArrowKeys()
    {
        var grid = Page.Descendants().Single(e => e.Name.LocalName == "ItemsRepeater" && Attr(e, "Name") == "OfferGrid");
        Assert.Equal("Once", Attr(grid, "TabFocusNavigation"));
        Assert.Equal("Enabled", Attr(grid, "XYFocusKeyboardNavigation"));
    }

    [Fact]
    public void LeavingPill_WrapsInsteadOfClipping()
    {
        var label = Page.Descendants().Single(e => e.Name.LocalName == "TextBlock" && Attr(e, "Name") == "BadgeLabel");
        Assert.Equal("WrapWholeWords", Attr(label, "TextWrapping"));
    }

    [Theory]
    [InlineData("fst.shop.empty")]
    [InlineData("fst.shop.filter.empty")]
    [InlineData("fst.shop.hidden")]
    public void StateTitles_AreHeadings(string id)
    {
        var title = Page.Descendants().Single(e => Attr(e, "AutomationProperties.AutomationId") == id);
        Assert.Equal("Level2", Attr(title, "AutomationProperties.HeadingLevel"));
    }
}
