using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>Guards viewport-sized loading placement without changing the shared load choreography (#624).</summary>
public class LoadingPlacementMarkupTests
{
    private static readonly string AppRoot = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    /// <summary>Reads a XAML attribute by its local name.</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Attribute name.</param>
    /// <returns>Value when present.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>
    /// Returns a ring's loading region: a Raw, non-hit-testable group whose only child is a transparent fill holding
    /// only the ring, so the region's UI Automation bounds (journey <c>assertcentred</c>/<c>assertgap</c>) are its layout box.
    /// </summary>
    /// <param name="ring">The busy ring.</param>
    /// <returns>Region element.</returns>
    private static XElement Region(XElement ring)
    {
        var fill = ring.Parent!;
        Assert.Equal("Grid", fill.Name.LocalName);
        Assert.Equal("Transparent", Attr(fill, "Background"));
        Assert.Single(fill.Elements());
        var region = fill.Parent!;
        Assert.Equal("AccessibleGroup", region.Name.LocalName);
        Assert.Equal("False", Attr(region, "IsHitTestVisible"));
        Assert.Single(region.Elements());
        return region;
    }

    [Fact]
    public void OverviewRing_FillsRemainingViewportBelowPinnedHeader()
    {
        var doc = XDocument.Load(Path.Combine(AppRoot, "Pages", "LeaderboardsPage.xaml"));
        var scroller = doc.Descendants().Single(e => Attr(e, "Name") == "Scroller");
        Assert.Equal("Stretch", Attr(scroller, "VerticalContentAlignment"));
        // The header is pinned above the scroller (#639), so the scroller's whole viewport is the region below it.
        Assert.Equal("1", Attr(scroller, "Grid.Row"));
        var page = scroller.Elements().Single();
        Assert.Equal("Grid", page.Name.LocalName);
        Assert.Null(page.Element(page.Name.Namespace + "Grid.RowDefinitions"));
        var ring = doc.Descendants().Single(e => Attr(e, "Name") == "ReadyRing");
        Assert.Null(Attr(ring, "Margin"));
        Assert.Equal("Center", Attr(ring, "HorizontalAlignment"));
        Assert.Equal("Center", Attr(ring, "VerticalAlignment"));
        var region = Region(ring);
        Assert.Same(page, region.Parent);
        Assert.Equal("Raw", Attr(region, "AutomationProperties.AccessibilityView"));
        Assert.Equal("Loading leaderboards", Attr(ring, "AutomationProperties.Name"));
        Assert.Equal("Spinner", Attr(ring, "LoadSwapVisual.Role"));
        Assert.Equal("{x:Bind ViewModel.LoadSwap, Mode=OneWay}", Attr(ring, "LoadSwapVisual.Swap"));
        Assert.DoesNotContain(ring.Ancestors(), e => e.Name.LocalName == "StackPanel");
        var cards = doc.Descendants().Single(e => Attr(e, "Name") == "InstrumentRepeater");
        Assert.Equal("StackPanel", cards.Parent!.Name.LocalName);
        Assert.Same(page, cards.Parent.Parent);
        var actions = doc.Descendants().Single(e => Attr(e, "Name") == "HeaderActions");
        Assert.DoesNotContain(actions.Ancestors(), e => e.Name.LocalName == "ScrollViewer");
    }

    [Theory]
    [InlineData("LeaderboardsFullRankingsPage", "LoadSwapVisual.PlaceSpinner(LoadingRing, LoadingRegion, footer: Footer);")]
    [InlineData("LeaderboardsBandRankingsPage", "LoadSwapVisual.PlaceSpinner(LoadingRing, LoadingRegion, footer: Footer);")]
    [InlineData("LeaderboardsSongPage", "LoadSwapVisual.PlaceSpinner(LoadingRing, LoadingRegion, Header, Footer, Scroller);")]
    [InlineData("BandsSongLeaderboardPage", "LoadSwapVisual.PlaceSpinner(LoadingRing, LoadingRegion, footer: Footer);")]
    [InlineData("BandsPlayerBandsPage", "LoadSwapVisual.PlaceSpinner(LoadingRing, LoadingRegion, footer: Footer);")]
    public void BoardRing_CentresAboveFloatingFooter(string page, string placement)
    {
        var doc = XDocument.Load(Path.Combine(AppRoot, "Pages", page + ".xaml"));
        var ring = doc.Descendants().Single(e => Attr(e, "Name") == "LoadingRing");
        var region = Region(ring);
        Assert.Equal("LoadingRegion", Attr(region, "Name"));
        Assert.Equal("Raw", Attr(region, "AutomationProperties.AccessibilityView"));
        Assert.Null(Attr(region, "AutomationProperties.Name"));
        Assert.Null(Attr(ring, "Margin"));
        Assert.Null(Attr(ring, "VerticalAlignment"));
        Assert.Equal("Spinner", Attr(ring, "LoadSwapVisual.Role"));
        Assert.StartsWith("Loading ", Attr(ring, "AutomationProperties.Name"));
        var footer = doc.Descendants().Single(e => Attr(e, "Name") == "Footer");
        Assert.Equal("Bottom", Attr(footer, "VerticalAlignment"));
        var span = region.AncestorsAndSelf().First(e => e.Parent == footer.Parent);
        Assert.Equal(Attr(footer, "Grid.Row"), Attr(span, "Grid.Row"));
        Assert.Equal(Attr(footer, "Grid.RowSpan"), Attr(span, "Grid.RowSpan"));
        var code = File.ReadAllText(Path.Combine(AppRoot, "Pages", page + ".xaml.cs"));
        Assert.Contains(placement, code);
    }
}
