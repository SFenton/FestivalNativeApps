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
    public void SongDetailPinnedBar_IsClearAndMasksTheContentScrollingUnderIt()
    {
        // Issue #640 (scroll-edge R1–R3, R7): the bar shows the backdrop art instead of a purple plate, and the canonical
        // top-edge mask hides content behind it and fades it in over 40 epx below it.
        var doc = Load("Pages/SongDetailPage.xaml");
        var bar = Named(doc, "PinnedHeader");
        Assert.Equal("{ThemeResource FSTPinnedHeaderBrush}", Attr(bar, "Background"));
        Assert.Equal("{ThemeResource FSTPinnedHeaderStrokeBrush}", Attr(bar, "BorderBrush"));
        var source = Named(doc, "ScrollFadeSource");
        Assert.Equal("Scroller", Attr(source.Elements().Single(), "Name"));
        Assert.False(bar.Ancestors().Contains(source), "the bar must not be masked with the content");
        var layer = ById(doc, "fst.song-detail.edge-fade");
        Assert.Equal("EdgeFadeLayer", layer.Name.LocalName);
        Assert.Equal("ScrollFadeHost", Attr(layer, "Name"));
        var code = File.ReadAllText(Path.Combine(AppRoot, "Pages", "SongDetailPage.xaml.cs"));
        Assert.Contains("OverlayHeaderFade.Attach(ScrollFadeSource, ScrollFadeHost, Scroller, PinnedHeader)", code, StringComparison.Ordinal);

        var styles = Load("Themes/Styles.xaml");
        string Brush(string theme, string key) => Attr(styles.Descendants()
            .Single(e => e.Name.LocalName == "ResourceDictionary" && Attr(e, "Key") == theme)
            .Elements().Single(e => Attr(e, "Key") == key), "Color")!;
        Assert.Equal("Transparent", Brush("Default", "FSTPinnedHeaderBrush"));
        Assert.Equal("Transparent", Brush("Default", "FSTPinnedHeaderStrokeBrush"));
        // Contrast themes keep a solid window-colour plate and a visible stroke (hard edge, no content behind chrome).
        Assert.Equal("{ThemeResource SystemColorWindowColor}", Brush("HighContrast", "FSTPinnedHeaderBrush"));
        Assert.Equal("{ThemeResource SystemColorWindowTextColor}", Brush("HighContrast", "FSTPinnedHeaderStrokeBrush"));
    }

    [Fact]
    public void BandStats_StayRealizedUnderThePinnedHeader()
    {
        // Issue #658: the pinned header's shorter viewport left Best Song Rank unrealized at 225% text, so Tab skipped it.
        var stats = Load("Pages/BandsDetailPage.xaml").Descendants()
            .Single(e => e.Name.LocalName == "ItemsRepeater" && Attr(e, "ItemsSource") == "{x:Bind ViewModel.Statistics, Mode=OneWay}");
        Assert.Equal("Local", Attr(stats, "TabFocusNavigation"));
        Assert.True(double.Parse(Attr(stats, "VerticalCacheLength") ?? "0", System.Globalization.CultureInfo.InvariantCulture) >= 20);
    }

    [Fact]
    public void OverlayHardEdge_IsAClipNotASubPixelGradient()
    {
        // Issue #658 (scroll-edge R7): with the hard edge, CI's software compositor drew only ~40 epx of Song Details
        // below the bar when the cut was a 0.01 epx mask gradient. The cut is the sprite's inset clip at the clear edge
        // over the unmasked copy; the masked copy is only for the ramp.
        var code = File.ReadAllText(Path.Combine(AppRoot, "Controls", "TopEdgeFade.cs"));
        Assert.Contains("sprite.Brush = hard ? content : mask;", code, StringComparison.Ordinal);
        Assert.Contains("clip.StartAnimation(nameof(clip.TopInset), top);", code, StringComparison.Ordinal);
        Assert.Contains("sprite.Clip = clip;", code, StringComparison.Ordinal);
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
