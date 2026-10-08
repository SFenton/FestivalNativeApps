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

    [Fact]
    public void FilterSwitches_AreNamedByLabelWithDescriptionAsHelpText()
    {
        var template = Page.Descendants().Single(e => e.Name.LocalName == "DataTemplate" && Attr(e, "Key") == "ShopFilterToggleTemplate");
        var toggle = template.Descendants().Single(e => e.Name.LocalName == "ToggleSwitch");
        Assert.Equal("{x:Bind Label}", Attr(toggle, "AutomationProperties.Name"));
        Assert.Equal("{x:Bind Description}", Attr(toggle, "AutomationProperties.HelpText"));
        Assert.Equal("{x:Bind AutomationId}", Attr(toggle, "AutomationProperties.AutomationId"));
    }

    [Fact]
    public void HeaderTools_WrapInSortFilterToggleOrder()
    {
        // Issue #379 (page-tools-and-nav-chrome R11): three header buttons wrap instead of clipping at large text.
        var row = Page.Descendants().Single(e => e.Name.LocalName == "WrapPanel" && Attr(e, "Name") == "HeaderActions");
        Assert.Equal(["fst.shop.sort", "fst.shop.filter", "fst.shop.view-toggle"],
            row.Elements().Select(e => Attr(e, "AutomationProperties.AutomationId")));
    }

    [Fact]
    public void SortFlyout_ReusesTheSongsSortForm()
    {
        // Issue #379: one Sort form for Songs and the Item Shop, each with its own automation IDs and heading.
        var songs = XDocument.Load(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App", "Pages", "SongsPage.xaml"));
        foreach (var (doc, prefix, title) in new[] { (Page, "fst.shop.sort", "Sort Item Shop"), (songs, "fst.songs.sort", "Sort Songs") })
        {
            var button = doc.Descendants().Single(e => Attr(e, "AutomationProperties.AutomationId") == prefix);
            var form = Assert.Single(button.Descendants(), e => e.Name.LocalName == "SongSortForm");
            Assert.Equal((prefix, title, "{x:Bind ViewModel.SortDraft}"), (Attr(form, "IdPrefix"), Attr(form, "Title"), Attr(form, "Draft")));
            Assert.Equal("OnSortOpening", Attr(form.Parent!, "Opening"));
        }
    }

    [Theory]
    [InlineData("fst.shop.empty")]
    [InlineData("fst.shop.filter.empty")]
    [InlineData("fst.shop.hidden")]
    public void StateTitles_AreSharedEmptyStateHeadings(string id)
    {
        // EmptyStateView's page variant makes its title a level-2 heading (EmptyStateMarkupTests guards the control).
        var state = Page.Descendants().Single(e => Attr(e, "TitleAutomationId") == id);
        Assert.Equal("EmptyStateView", state.Name.LocalName);
        Assert.Null(Attr(state, "IsCompact"));
    }

    [Fact]
    public void FilteredEmpty_HasNoResetButton()
    {
        // Issue #377: the Filter button is the way back; the empty state offers no Reset Filters.
        Assert.DoesNotContain(Page.Descendants(), e => Attr(e, "AutomationProperties.AutomationId") == "fst.shop.filter.empty-reset");
        var state = Page.Descendants().Single(e => Attr(e, "TitleAutomationId") == "fst.shop.filter.empty");
        Assert.Empty(state.Descendants());
    }

    [Fact]
    public void Notices_StackDetailsThenSortPause()
    {
        // catalogue-sort R7 (#379): the paused Duration sort reads as its own notice under the catalogue-links notice.
        var notices = Page.Descendants().Single(e => Attr(e, "Name") == "Notices");
        Assert.Equal(["fst.shop.song-details-error", "fst.shop.sort-paused"],
            notices.Elements().Select(e => Attr(e, "AutomationProperties.AutomationId")));
        var paused = notices.Elements().Last();
        Assert.Equal(("{x:Bind ViewModel.HasSortPause, Mode=OneWay}", "{x:Bind ViewModel.SortPaused, Mode=OneWay}"),
            (Attr(paused, "IsOpen"), Attr(paused, "Message")));
    }
}
