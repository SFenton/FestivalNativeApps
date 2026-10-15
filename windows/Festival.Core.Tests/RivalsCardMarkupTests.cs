using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #603 (rival-rows R1, R3, R6): every Windows rival list draws its rows in one card with hairlines (the
/// hub's section cards, Rival Detail's category cards, All Rivals and Rivalry) instead of a card per row, and every
/// song comparison row is the one iOS-design <c>RivalSongRowView</c> layout. The live check is the rivals-cards
/// journey (<c>tools/windows/journeys/a11y-rivals-cards.json</c>).
/// </summary>
public class RivalsCardMarkupTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    #region Helpers

    /// <summary>Loads a Festival.App XAML file.</summary>
    /// <param name="folder">Folder under Festival.App.</param>
    /// <param name="file">File name.</param>
    /// <returns>The parsed document.</returns>
    private static XDocument Load(string folder, string file) => XDocument.Load(Path.Combine(AppRoot, folder, file));

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Asserts a row template's hairline is the shared, hidden-by-default, non-interactive separator.</summary>
    /// <param name="scope">Template subtree.</param>
    private static void AssertHairline(XElement scope)
    {
        var separator = Assert.Single(scope.Descendants(), e => Attr(e, "Name") == "RowSeparator");
        Assert.Equal("{ThemeResource FSTRowSeparatorBrush}", Attr(separator, "Background"));
        Assert.Equal("Collapsed", Attr(separator, "Visibility"));
        Assert.Equal("False", Attr(separator, "IsHitTestVisible"));
        Assert.Equal("Raw", Attr(separator, "AutomationProperties.AccessibilityView"));
    }

    #endregion

    #region Virtualized lists

    [Theory]
    [InlineData("AllRivalsPage.xaml", "RivalList", "RivalRowView", "AllRivalsPage.xaml.cs")]
    [InlineData("RivalryPage.xaml", "SongList", "RivalSongRowView", "RivalryPage.xaml.cs")]
    public void ListsDrawOneGroupedCard(string page, string list, string row, string code)
    {
        var view = Assert.Single(Load("Pages", page).Descendants(), e => Attr(e, "Name") == list);
        var setters = view.Descendants()
            .Where(e => e.Name.LocalName == "Setter" && e.Ancestors().Any(a => a.Name.LocalName == "ListView.ItemContainerStyle"))
            .ToDictionary(e => Attr(e, "Property")!, e => Attr(e, "Value"));

        // No per-row card: the container neither paints a card nor separates rows.
        Assert.Equal("0", setters["Margin"]);
        Assert.False(setters.ContainsKey("Background"));
        Assert.Equal("True", Attr(view, "FadeIn.Together"));
        Assert.Null(Attr(view, "FadeIn.Stagger"));

        var template = Assert.Single(view.Descendants(), e => e.Name.LocalName == "DataTemplate");
        Assert.Single(template.Descendants(), e => e.Name.LocalName == row);
        AssertHairline(template);
        Assert.Contains("GroupedRows.ApplyToContainer(sender, args)", File.ReadAllText(Path.Combine(AppRoot, "Pages", code)), StringComparison.Ordinal);
    }

    [Fact]
    public void AllRivalsKeepsItsSplitSelection()
    {
        // View All and the wide split's selection behaviour are unchanged by the card.
        var code = File.ReadAllText(Path.Combine(AppRoot, "Pages", "AllRivalsPage.xaml.cs"));
        Assert.Contains("ListViewSelectionMode.Single", code, StringComparison.Ordinal);
        Assert.Contains("OnRivalSelectionChanged", code, StringComparison.Ordinal);
    }

    #endregion

    #region Repeater cards

    [Theory]
    [InlineData("RivalsPage.xaml", "RivalRowView")]
    [InlineData("RivalDetailPage.xaml", "RivalSongRowView")]
    public void CardRepeatersSeparateTheirRows(string page, string row)
    {
        var repeaters = Load("Pages", page).Descendants()
            .Where(e => e.Name.LocalName == "ItemsRepeater" && e.Descendants().Any(d => d.Name.LocalName == row)
                        && !e.Descendants().Any(d => d.Name.LocalName == "ItemsRepeater"))
            .ToList();

        Assert.NotEmpty(repeaters);
        foreach (var repeater in repeaters)
        {
            Assert.Equal("True", Attr(repeater, "RowSeparators.Enabled"));
            AssertHairline(repeater);
        }
    }

    #endregion

    #region Song row

    [Fact]
    public void SongRowIsTheIosDesign()
    {
        var doc = Load("Controls", "RivalSongRowView.xaml");
        var names = doc.Descendants().Select(e => Attr(e, "Name")).Where(n => n is not null).ToHashSet();

        // Art over the instrument icon, both standing pills and the rank gap; no compact variant or score chips.
        Assert.Contains(doc.Descendants(), e => e.Name.LocalName == "SongArt");
        Assert.Equal(2, doc.Descendants().Count(e => Attr(e, "Style") == "{StaticResource FSTRivalPillStyle}"));
        Assert.Contains(doc.Descendants(), e => (Attr(e, "Text") ?? "").Contains("RankGapText", StringComparison.Ordinal));
        Assert.Contains("Leading", names);
        Assert.DoesNotContain(doc.Descendants(), e => (Attr(e, "Text") ?? "").Contains("ScoreText", StringComparison.Ordinal));
        Assert.DoesNotContain(doc.Descendants(), e => (Attr(e, "Visibility") ?? "").Contains("Compact", StringComparison.Ordinal));
        foreach (var page in new[] { "RivalDetailPage.xaml", "RivalryPage.xaml" })
            Assert.DoesNotContain(Load("Pages", page).Descendants(), e => e.Name.LocalName == "RivalSongRowView" && Attr(e, "Compact") is not null);
    }

    #endregion

    #region First Run demos

    /// <summary>A method's source, from its signature to the next member.</summary>
    /// <param name="code">File text.</param>
    /// <param name="signature">Signature text.</param>
    /// <returns>The member's text.</returns>
    private static string Member(string code, string signature)
    {
        var start = code.IndexOf(signature, StringComparison.Ordinal);
        Assert.True(start >= 0, signature);
        var next = code.IndexOf("\n    private ", start + signature.Length, StringComparison.Ordinal);
        return next < 0 ? code[start..] : code[start..next];
    }

    [Fact]
    public void FirstRunRivalDemosAreOneSeparatedCard()
    {
        // Issue #643 (rival-rows R6): the guide's rival lists use the pages' treatment, touching rows in one card with
        // the shared hairline shown by RowSeparators above every row after the first.
        var code = File.ReadAllText(Path.Combine(AppRoot, "Controls", "FirstRunDemo.Slides.cs"));
        Assert.Contains("RowSeparators.Apply(row, index)", Member(code, "private static DemoSeparatedRow SeparatedRow("), StringComparison.Ordinal);
        Assert.Contains("SeparatedRow(new RivalRowView", Member(code, "private static LeaderboardRowButton RivalRow("), StringComparison.Ordinal);

        var row = Member(code, "private sealed partial class DemoSeparatedRow");
        Assert.Contains("ISeparatedRow", row, StringComparison.Ordinal);
        Assert.Contains("B(\"FSTRowSeparatorBrush\")", row, StringComparison.Ordinal);
        Assert.Contains("Visibility = Visibility.Collapsed", row, StringComparison.Ordinal);
        Assert.Contains("AccessibilityView.Raw", row, StringComparison.Ordinal);
        Assert.Contains("IsHitTestVisible = false", row, StringComparison.Ordinal);

        foreach (var demo in new[] { "private void BuildCompeteHub()", "private void BuildRivalsSection()", "private void BuildInstrumentRivals()", "private void BuildRivalDetail()" })
        {
            var body = Member(code, demo);
            Assert.Contains("RivalRowsCard(", body, StringComparison.Ordinal);
            Assert.DoesNotContain("Style = S(\"FSTCardStyle\")", body, StringComparison.Ordinal);
            Assert.DoesNotContain("Spacing = 2 }", body, StringComparison.Ordinal);
            Assert.DoesNotContain("Spacing = 4 }", body, StringComparison.Ordinal);
            Assert.DoesNotContain("Background = B(\"FSTRowSeparatorBrush\")", body, StringComparison.Ordinal);
        }

        // The overview's below half continues the card's row indices, so its first row has a hairline too.
        Assert.Contains("RivalDirection.Below, above.Rows.Count)", Member(code, "private void BuildRivalsSection()"), StringComparison.Ordinal);
        Assert.Contains("SeparatedRow(new RivalSongRowView", Member(code, "private void BuildRivalDetail()"), StringComparison.Ordinal);
    }

    #endregion
}
