using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #543: the full Windows boards (song board, Full Rankings, Band Rankings and the song band board) draw
/// the page's entries as one grouped card (touching row slices with hairlines, <c>GroupedRows</c>) instead of a card
/// per row. The live check is the grouped-boards journey (<c>tools/windows/journeys/a11y-grouped-boards.json</c>).
/// </summary>
public class GroupedBoardMarkupTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    #region Helpers

    /// <summary>Loads a Festival.App page.</summary>
    /// <param name="page">File name under Festival.App/Pages.</param>
    /// <returns>The parsed document.</returns>
    private static XDocument Page(string page) => XDocument.Load(Path.Combine(AppRoot, "Pages", page));

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    #endregion

    #region Repeater boards

    [Theory]
    [InlineData("LeaderboardsSongPage.xaml", "RowsRepeater")]
    [InlineData("LeaderboardsFullRankingsPage.xaml", null)]
    [InlineData("LeaderboardsBandRankingsPage.xaml", null)]
    public void FullBoardRepeatersGroupTheirRowsIntoOneCard(string page, string? name)
    {
        var repeaters = Page(page).Descendants()
            .Where(e => e.Name.LocalName == "ItemsRepeater"
                        && e.Descendants().Any(d => d.Name.LocalName == "LeaderboardEntryRow")
                        && (name is null || Attr(e, "Name") == name))
            .ToList();

        Assert.NotEmpty(repeaters);
        foreach (var repeater in repeaters)
        {
            Assert.Equal("True", Attr(repeater, "GroupedRows.IsEnabled"));
            var stack = Assert.Single(repeater.Descendants(), e => e.Name.LocalName == "StackLayout");
            Assert.Equal("0", Attr(stack, "Spacing"));
        }
    }

    [Fact]
    public void PinnedRowStaysAFloatingCardOutsideTheGroup()
    {
        var pinned = Page("LeaderboardsSongPage.xaml").Descendants()
            .Single(e => e.Name.LocalName == "LeaderboardEntryRow" && Attr(e, "IsFloating") == "True");

        Assert.DoesNotContain(pinned.Ancestors(), a => Attr(a, "GroupedRows.IsEnabled") is not null);
    }

    #endregion

    #region Song band board

    [Fact]
    public void SongBandBoardItemsTouchAndCarryAHairline()
    {
        var doc = Page("BandsSongLeaderboardPage.xaml");
        var margin = doc.Descendants()
            .Where(e => e.Name.LocalName == "Setter" && Attr(e, "Property") == "Margin"
                        && e.Ancestors().Any(a => a.Name.LocalName == "ListView.ItemContainerStyle"))
            .Select(e => Attr(e, "Value"))
            .Single();
        var separator = doc.Descendants().Single(e => Attr(e, "Name") == "RowSeparator");

        Assert.Equal("0", margin);
        Assert.Equal("Collapsed", Attr(separator, "Visibility"));
        Assert.Equal("False", Attr(separator, "IsHitTestVisible"));
        Assert.Equal("Raw", Attr(separator, "AutomationProperties.AccessibilityView"));
    }

    #endregion
}
