using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #377 (empty-error-states R1/R2/R5) in markup: every Windows empty state is the one shared
/// <c>Controls/EmptyStateView</c>, after the web <c>EmptyState</c>. It is centred text with no card and no Reset or Clear
/// Filters button; failures keep <c>ServiceStatusView</c>'s card, so empty and failed reads stay distinct.
/// </summary>
public class EmptyStateMarkupTests
{
    private static readonly string AppRoot = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    private static readonly XDocument Control = XDocument.Load(Path.Combine(AppRoot, "Controls", "EmptyStateView.xaml"));

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Every app XAML file with its relative path.</summary>
    /// <returns>Path and document pairs.</returns>
    private static IEnumerable<(string Path, XDocument Doc)> AppXaml() =>
        Directory.EnumerateFiles(AppRoot, "*.xaml", SearchOption.AllDirectories)
            .Select(p => (Rel: Path.GetRelativePath(AppRoot, p), Full: p))
            .Where(p => !p.Rel.StartsWith($"bin{Path.DirectorySeparatorChar}", StringComparison.Ordinal)
                        && !p.Rel.StartsWith($"obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
            .Select(p => (p.Rel, XDocument.Load(p.Full)));

    /// <summary>Every <c>EmptyStateView</c> use in the app.</summary>
    /// <returns>Path and element pairs.</returns>
    private static IEnumerable<(string Path, XElement Element)> Uses() =>
        AppXaml().SelectMany(x => x.Doc.Descendants().Where(e => e.Name.LocalName == "EmptyStateView").Select(e => (x.Path, e)));

    [Fact]
    public void Control_IsCentredTextWithNoCardOrButton()
    {
        Assert.DoesNotContain(Control.Descendants(), e => e.Name.LocalName is "Border" or "Button");
        Assert.DoesNotContain(Control.Descendants(), e => Attr(e, "Style")?.Contains("FSTCardStyle", StringComparison.Ordinal) ?? false);
        var stack = Control.Descendants().Single(e => Attr(e, "Name") == "Stack");
        Assert.Equal("Center", Attr(stack, "HorizontalAlignment"));
        Assert.Equal("Center", Attr(stack, "VerticalAlignment"));
        Assert.Equal("8", Attr(stack, "Spacing"));
        var title = Control.Descendants().Single(e => Attr(e, "Name") == "TitleBlock");
        Assert.Equal("Level2", Attr(title, "AutomationProperties.HeadingLevel"));
        Assert.Equal("Center", Attr(title, "TextAlignment"));
        var icon = Control.Descendants().Single(e => Attr(e, "Name") == "IconGlyph");
        Assert.Equal("Raw", Attr(icon, "AutomationProperties.AccessibilityView"));
    }

    [Theory]
    [InlineData(@"Pages\ShopPage.xaml", 3)]
    [InlineData(@"Pages\SongsPage.xaml", 1)]
    [InlineData(@"Pages\SuggestionsPage.xaml", 1)]
    [InlineData(@"Pages\RivalsPage.xaml", 2)]
    [InlineData(@"Controls\RivalPageStates.xaml", 2)]
    [InlineData(@"Pages\BandsPlayerBandsPage.xaml", 1)]
    [InlineData(@"Pages\BandsSongLeaderboardPage.xaml", 1)]
    [InlineData(@"Pages\BandsPage.xaml", 1)]
    [InlineData(@"Pages\BandsDetailPage.xaml", 3)]
    [InlineData(@"Pages\LeaderboardsPage.xaml", 2)]
    [InlineData(@"Pages\LeaderboardsSongPage.xaml", 1)]
    [InlineData(@"Pages\LeaderboardsBandRankingsPage.xaml", 1)]
    [InlineData(@"Pages\LeaderboardsFullRankingsPage.xaml", 1)]
    [InlineData(@"Pages\SearchPage.xaml", 1)]
    [InlineData(@"Pages\PlayerHistoryPage.xaml", 1)]
    [InlineData(@"Pages\SongDetailPage.xaml", 2)]
    [InlineData(@"Controls\NotificationsBell.xaml", 2)]
    [InlineData(@"Controls\PlayerProfileView.xaml", 2)]
    [InlineData(@"Controls\SongPathsView.xaml", 1)]
    public void EmptyRegions_UseTheSharedView(string file, int count)
    {
        Assert.Equal(count, Uses().Count(u => u.Path == file));
    }

    [Fact]
    public void Uses_SitOnNoCardAndOfferNoFilterReset()
    {
        foreach (var (path, use) in Uses())
        {
            Assert.False(use.Ancestors().Any(a => Attr(a, "Style")?.Contains("FSTCardStyle", StringComparison.Ordinal) ?? false),
                $"{path}: an EmptyStateView sits on a card");
            foreach (var button in use.Descendants().Where(e => e.Name.LocalName == "Button"))
            {
                var label = $"{Attr(button, "Content")} {Attr(button, "AutomationProperties.AutomationId")}";
                Assert.DoesNotContain("Reset", label, StringComparison.OrdinalIgnoreCase);
                Assert.DoesNotContain("Clear", label, StringComparison.OrdinalIgnoreCase);
            }
        }
    }

    [Theory]
    [InlineData("fst.shop.filter.empty-reset")]
    [InlineData("fst.suggestions.reset-filters")]
    public void RemovedResetButtons_StayRemoved(string id)
    {
        Assert.DoesNotContain(AppXaml().SelectMany(x => x.Doc.Descendants()), e => Attr(e, "AutomationProperties.AutomationId") == id);
    }
}
