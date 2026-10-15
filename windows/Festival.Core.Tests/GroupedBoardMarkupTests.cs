using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #543: the full Windows boards (song board, Full Rankings, Band Rankings and the song band board) draw
/// the page's entries as one grouped card (touching row slices with hairlines, <c>GroupedRows</c>) instead of a card
/// per row. The live check is the grouped-boards journey (<c>tools/windows/journeys/a11y-grouped-boards.json</c>).
/// Issue #588 adds the in-card variant: Song Detail's Score History rows sit inside the history card with View All Scores.
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

    #region In-card rows

    [Fact]
    public void ScoreHistoryCardHoldsTheSelectorChartRowsAndViewAll()
    {
        // Issue #588: one Score History card (like Apple's grouped SongScoreHistorySection), in reading order.
        var doc = Page("SongDetailPage.xaml");
        var card = doc.Descendants().Single(e => Attr(e, "Name") == "HistoryCard");
        Assert.Equal("{StaticResource FSTCardStyle}", Attr(card, "Style"));
        var order = card.Descendants().Select(e => Attr(e, "Name"))
            .Where(n => n is "HistorySelector" or "HistoryChart" or "HistoryPagerSlot" or "HistoryRows" or "HistoryViewAll")
            .ToList();
        Assert.Equal(["HistorySelector", "HistoryChart", "HistoryPagerSlot", "HistoryRows", "HistoryViewAll"], order);

        var rows = card.Descendants().Single(e => Attr(e, "Name") == "HistoryRows");
        Assert.Equal("True", Attr(rows, "GroupedRows.IsEnabled"));
        Assert.Equal("True", Attr(rows, "GroupedRows.InCard"));
        Assert.Equal("True", Attr(rows, "FadeIn.Stagger"));
        // Issue #629: the top five realize in one pass (non-virtualizing, one column), so a swap never reads as the viewport.
        Assert.DoesNotContain(rows.Descendants(), e => e.Name.LocalName == "StackLayout");
        var layout = Assert.Single(rows.Descendants(), e => e.Name.LocalName == "MasonryLayout");
        Assert.Equal("1", Attr(layout, "MaxColumns"));
        Assert.Equal("0", Attr(layout, "RowSpacing"));

        // The swap holds only the graph section, so the list after it resizes to the new chart's rows (load-transition R7).
        var graph = card.Descendants().Single(e => Attr(e, "Name") == "HistoryGraph");
        Assert.Contains(graph.Descendants(), e => Attr(e, "Name") == "HistoryPagerSlot");
        Assert.DoesNotContain(graph.Descendants(), e => Attr(e, "Name") is "HistoryRows" or "HistoryViewAll");
        var code = File.ReadAllText(Path.Combine(AppRoot, "Pages", "SongDetailPage.xaml.cs"));
        Assert.Contains("HistoryGraph.MinHeight = Math.Max(HistoryGraph.MinHeight, HistoryGraph.ActualHeight)", code, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("LeaderboardsPage.xaml", "BoardCard", true)]
    [InlineData("LeaderboardsPage.xaml", "BandBoardCard", false)]
    [InlineData("SongDetailPage.xaml", "PreviewCard", false)]
    [InlineData("SongDetailPage.xaml", "BandPreviewCard", false)]
    public void PreviewCardHoldsItsRowsAndViewAll(string page, string cardName, bool spotlight)
    {
        // Issue #643: each preview is one card (leaderboard-row R10, surface-materials R6) with the rows as in-card
        // slices and View All inside it, last (view-all-cta R1). The empty state stays card-less (#377).
        var card = Page(page).Descendants().Single(e => Attr(e, "Name") == cardName);
        Assert.Equal("{StaticResource FSTCardStyle}", Attr(card, "Style"));
        Assert.Equal("8,8,8,12", Attr(card, "Padding"));

        var rows = Assert.Single(card.Descendants(), e => e.Name.LocalName == "ItemsRepeater");
        Assert.Equal("True", Attr(rows, "GroupedRows.IsEnabled"));
        Assert.Equal("True", Attr(rows, "GroupedRows.InCard"));
        var layout = Assert.Single(rows.Descendants(), e => e.Name.LocalName.EndsWith("Layout", StringComparison.Ordinal) && !e.Name.LocalName.Contains('.'));
        Assert.Equal("0", Attr(layout, "Spacing"));

        var viewAll = card.Descendants().Last(e => e.Name.LocalName == "Button");
        Assert.Equal("{StaticResource FSTViewAllButtonStyle}", Attr(viewAll, "Style"));
        Assert.True(card.Descendants().ToList().IndexOf(rows) < card.Descendants().ToList().IndexOf(viewAll));

        var parent = card.Parent!;
        Assert.Contains(parent.Elements(), e => e.Name.LocalName == "EmptyStateView");
        Assert.DoesNotContain(card.Descendants(), e => e.Name.LocalName == "EmptyStateView");

        if (spotlight)
        {
            var spot = Assert.Single(card.Descendants(), e => e.Name.LocalName == "LeaderboardsSpotlight");
            Assert.Equal("True", Attr(spot, "InCard"));
        }
        foreach (var skeleton in card.Descendants().Where(e => e.Name.LocalName == "LeaderboardsSkeleton"))
            Assert.Equal("True", Attr(skeleton, "InCard"));
    }

    [Fact]
    public void FirstRunPreviewDemosDrawOneCard()
    {
        // Issue #643: the guide's Top Scores, Score History, rankings and Compete demos mirror the one-card previews.
        var code = File.ReadAllText(Path.Combine(AppRoot, "Controls", "FirstRunDemo.Slides.cs"));
        Assert.Contains("private static Border RowsCard(", code, StringComparison.Ordinal);
        Assert.Contains("GroupedRows.SliceFor(i, rows.Length, rows[i], i > 0 ? rows[i - 1] : null, inCard: true)", code, StringComparison.Ordinal);
        Assert.DoesNotContain("IsFloating = row.IsSelected", code, StringComparison.Ordinal);
        Assert.DoesNotContain("foreach (var row in rows) Stage(new LeaderboardEntryRow", code, StringComparison.Ordinal);
    }

    [Fact]
    public void BoardsDoNotUseInCardSlices()
    {
        // Full boards draw the grouped card themselves (#543); only rows inside a card's own surface are in-card.
        foreach (var page in new[] { "LeaderboardsSongPage.xaml", "LeaderboardsFullRankingsPage.xaml", "LeaderboardsBandRankingsPage.xaml" })
            Assert.DoesNotContain(Page(page).Descendants(), e => Attr(e, "GroupedRows.InCard") is not null);
    }

    #endregion
}
