using System.Globalization;
using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #72: title-bar and page tool buttons keep Fluent's 40x40 epx minimum touch target
/// (<c>FSTMinTargetSize</c>), so a tap just beside the glyph still activates them. The live check is the
/// off-centre click probe in <c>.agents/testing/windows.md</c>; this keeps the markup from regressing.
/// </summary>
public class HitTargetMarkupTests
{
    private const string Resource = "{StaticResource FSTMinTargetSize}";

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

    /// <summary>Finds every button with a given UIA AutomationId (the wide title-bar search box shares its button's ID).</summary>
    /// <param name="doc">Document.</param>
    /// <param name="id">AutomationId.</param>
    /// <returns>Matching button elements.</returns>
    private static List<XElement> ById(XDocument doc, string id) =>
        doc.Descendants().Where(e => e.Name.LocalName.EndsWith("Button", StringComparison.Ordinal)
                                     && Attr(e, "AutomationProperties.AutomationId") == id).ToList();

    #endregion

    [Fact]
    public void MinTargetResource_IsFluentMinimum()
    {
        var value = Load(Path.Combine("Themes", "Styles.xaml")).Descendants()
            .Single(e => e.Name.LocalName == "Double" && Attr(e, "Key") == "FSTMinTargetSize").Value;
        Assert.True(double.Parse(value, CultureInfo.InvariantCulture) >= 40);
    }

    [Theory]
    [InlineData("MainWindow.xaml", "fst.global-search.open", true)]
    [InlineData("MainWindow.xaml", "fst.shell.profile", true)]
    [InlineData("Controls/NotificationsBell.xaml", "fst.shell.notifications", true)]
    [InlineData("Pages/SongsPage.xaml", "fst.songs.sort", false)]
    [InlineData("Pages/SongsPage.xaml", "fst.songs.filter", false)]
    [InlineData("Pages/SongsPage.xaml", "fst.songs.section-index-button", true)]
    [InlineData("Pages/SuggestionsPage.xaml", "fst.suggestions.filter-button", false)]
    [InlineData("Pages/PlayerHistoryPage.xaml", "fst.history.sort.open", false)]
    [InlineData("Pages/SongDetailPage.xaml", "fst.history.sort.open", false)]
    [InlineData("Pages/LeaderboardsPage.xaml", "fst.rankings.rank-by-menu", false)]
    [InlineData("Pages/ShopPage.xaml", "fst.shop.filter", false)]
    [InlineData("Pages/ShopPage.xaml", "fst.shop.view-toggle", false)]
    [InlineData("Pages/RivalDetailPage.xaml", "fst.rival-detail.view-profile", false)]
    public void ToolButtons_UseMinTarget(string file, string id, bool iconOnly)
    {
        var button = Assert.Single(ById(Load(file), id));
        Assert.Equal(Resource, Attr(button, "MinHeight"));
        // Labelled buttons are already wider than 40; icon-only ones need the width too.
        if (iconOnly) Assert.Equal(Resource, Attr(button, "MinWidth"));
    }

    [Fact]
    public void QuickLinks_KeepsMinTarget()
    {
        var source = File.ReadAllText(Path.Combine(AppRoot, "Controls", "QuickLinksMenuButton.cs"));
        Assert.Contains("public const double MinTargetSize = 40;", source);
        Assert.Contains("MinHeight = MinTargetSize;", source);
        // A page may restate the minimum (to match its neighbours) but never shrink it below 40.
        var hosts = Directory.EnumerateFiles(AppRoot, "*.xaml", SearchOption.AllDirectories)
            .SelectMany(path => XDocument.Load(path).Descendants().Where(e => e.Name.LocalName == "QuickLinksMenuButton"))
            .ToList();
        Assert.NotEmpty(hosts);
        Assert.All(hosts, host => Assert.Contains(Attr(host, "MinHeight"), new[] { null, Resource }));
    }
}
