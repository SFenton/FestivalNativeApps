using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #639 (page-tools-and-nav-chrome R5/R6, agent decision): Windows page tools stay reachable while the page
/// scrolls. Every Quick Links page keeps its header (title, Quick Links menu, Select/Deselect, Rank By) above its
/// ScrollViewer, like Rivals; Song Detail's pinned compact bar carries Paths, Item Shop and Quick Links; and Item Shop's
/// status fill is the full 40 epx of the button beside Paths. The live checks are the
/// <c>tools/windows/journeys/a11y-pinned-page-tools.json</c> pages.
/// </summary>
public class PinnedPageToolsMarkupTests
{
    private const string MinTarget = "{StaticResource FSTMinTargetSize}";

    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    #region Helpers

    /// <summary>Loads a Festival.App XAML file.</summary>
    /// <param name="relative">Path under Festival.App.</param>
    /// <returns>The parsed document.</returns>
    private static XDocument Load(string relative) => XDocument.Load(Path.Combine(AppRoot, relative));

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Finds the element with an <c>x:Name</c>.</summary>
    /// <param name="doc">Document.</param>
    /// <param name="name">Name.</param>
    /// <returns>The element.</returns>
    private static XElement Named(XDocument doc, string name) =>
        doc.Descendants().Single(e => Attr(e, "Name") == name);

    /// <summary>Finds the element with an AutomationId.</summary>
    /// <param name="doc">Document.</param>
    /// <param name="id">AutomationId.</param>
    /// <returns>The element.</returns>
    private static XElement ById(XDocument doc, string id) =>
        doc.Descendants().Single(e => Attr(e, "AutomationProperties.AutomationId") == id);

    /// <summary>Whether an element sits inside a ScrollViewer (it would scroll away with the content).</summary>
    /// <param name="element">Element.</param>
    /// <returns><see langword="true"/> inside a scroller.</returns>
    private static bool Scrolls(XElement element) => element.Ancestors().Any(e => e.Name.LocalName == "ScrollViewer");

    #endregion

    [Theory]
    [InlineData("Pages/LeaderboardsPage.xaml")]
    [InlineData("Pages/SettingsPage.xaml")]
    [InlineData("Pages/BandsDetailPage.xaml")]
    [InlineData("Pages/RivalsPage.xaml")]
    [InlineData("Pages/RivalDetailPage.xaml")]
    [InlineData("Controls/PlayerProfileView.xaml")]
    public void QuickLinksMenu_SitsInAPinnedHeaderAboveTheScroller(string file)
    {
        var doc = Load(file);
        var menu = Named(doc, "QuickLinksMenu");
        Assert.False(Scrolls(menu), $"{file}: the Quick Links menu scrolls away with the content");
        // The header comes first in the tree, so Tab and Narrator reach the tools before the content (keyboard order).
        var scroller = Named(doc, "Scroller");
        Assert.True(menu.IsBefore(scroller), $"{file}: the header must precede the scroller");
        Assert.Equal("1", Attr(scroller, "Grid.Row"));
    }

    [Theory]
    [InlineData("fst.player.select")]
    [InlineData("fst.player.deselect")]
    public void ProfileIdentityActions_AreInThePinnedHeader(string id)
    {
        var doc = Load("Controls/PlayerProfileView.xaml");
        var action = ById(doc, id);
        Assert.False(Scrolls(action));
        Assert.Equal(MinTarget, Attr(action, "MinHeight"));
    }

    [Fact]
    public void SongDetailPinnedBar_CarriesPathsItemShopAndQuickLinksInOrder()
    {
        var doc = Load("Pages/SongDetailPage.xaml");
        var tools = Named(doc, "PinnedTools");
        Assert.Equal("WrapPanel", tools.Name.LocalName);
        Assert.Contains(tools.Ancestors(), e => Attr(e, "Name") == "PinnedHeader");
        Assert.False(Scrolls(tools));
        var order = tools.Elements().Select(e => Attr(e, "AutomationProperties.AutomationId")).ToList();
        Assert.Equal(["fst.song-detail.pinned-paths", "fst.song-detail.pinned-shop", "fst.song-detail.pinned-quick-links"], order);
        Assert.Equal("QuickLinksMenuButton", tools.Elements().Last().Name.LocalName);
        // The hero's tools appear in the same order, so either copy reads Paths → Item Shop → Quick Links.
        var hero = ById(doc, "fst.song-detail.paths").Parent!;
        Assert.Equal(["PathsButton", "ShopButton", "QuickLinksMenu"], hero.Elements().Select(e => Attr(e, "Name")));
        // Both shop copies bind the same visibility and spoken status.
        var shop = ById(doc, "fst.song-detail.shop");
        var pinnedShop = ById(doc, "fst.song-detail.pinned-shop");
        foreach (var attr in new[] { "Visibility", "AutomationProperties.Name", "Click", "Style", "MinHeight" })
            Assert.Equal(Attr(shop, attr), Attr(pinnedShop, attr));
    }

    [Fact]
    public void ShopButtons_UseTheBorderlessShopStyle()
    {
        var styles = Load("Themes/Styles.xaml");
        var style = styles.Descendants().Single(e => e.Name.LocalName == "Style" && Attr(e, "Key") == "FSTShopButtonStyle");
        var setters = style.Elements().Where(e => e.Name.LocalName == "Setter")
            .ToDictionary(e => Attr(e, "Property")!, e => Attr(e, "Value"));
        // The 1 epx default border inset the status fill to 38 of the button's 40 epx (#639).
        Assert.Equal("0", setters["BorderThickness"]);
        Assert.Equal("0", setters["Padding"]);
        Assert.Equal("Stretch", setters["VerticalContentAlignment"]);
        var doc = Load("Pages/SongDetailPage.xaml");
        foreach (var id in new[] { "fst.song-detail.shop", "fst.song-detail.pinned-shop" })
        {
            var button = ById(doc, id);
            Assert.Equal("{StaticResource FSTShopButtonStyle}", Attr(button, "Style"));
            Assert.Null(Attr(button, "Padding"));
            Assert.Null(Attr(button, "BorderThickness"));
            Assert.Contains(button.Descendants(), e => e.Name.LocalName == "ShopPulseFill");
        }
        var demo = File.ReadAllText(Path.Combine(AppRoot, "Controls", "FirstRunDemo.Slides.cs"));
        Assert.Contains("S(\"FSTShopButtonStyle\")", demo, StringComparison.Ordinal);
    }
}
