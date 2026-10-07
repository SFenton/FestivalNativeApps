using System.Xml.Linq;
using Festival.Core.Domain;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

/// <summary>
/// Issue #268 (check of #68/#41), pattern <c>view-all-cta</c>: every "View all" call to action below a card's rows
/// (Song Detail's View Full Leaderboard and View All Scores, the Rivals hub's View All Rivals, Rival Detail's category
/// View All (#321), Leaderboards' View All Rankings) is the same button: one shared style
/// with no per-page layout overrides, a Fluent 40 epx minimum target, and a UIA name that starts with its visible label.
/// </summary>
public class ViewAllCtaTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    private const string StyleRef = "{StaticResource FSTViewAllButtonStyle}";

    #region Helpers

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Every button in Festival.App that uses the shared View all style, with its file.</summary>
    /// <returns>(file name, element) pairs.</returns>
    private static List<(string File, XElement Button)> Consumers() =>
        Directory.EnumerateFiles(AppRoot, "*.xaml", SearchOption.AllDirectories)
            .Where(path => !Path.GetRelativePath(AppRoot, path).Split(Path.DirectorySeparatorChar)
                .Any(part => part is "bin" or "obj"))
            .SelectMany(path => XDocument.Load(path).Descendants()
                .Where(e => e.Name.LocalName == "Button" && Attr(e, "Style") == StyleRef)
                .Select(e => (Path.GetFileName(path), e)))
            .ToList();

    /// <summary>An x:Bind to a view model property (a card's own or a page's section path), optionally OneWay.</summary>
    /// <param name="property">Final property name.</param>
    /// <returns>Anchored pattern.</returns>
    private static string BindingTo(string property) => $@"^\{{x:Bind (\w+\.)*{property}(, Mode=OneWay)?\}}$";

    #endregion

    [Theory]
    [InlineData("View Full Leaderboard", "Lead", "View Full Leaderboard, Lead")]
    [InlineData("View All Rivals", "Common Rivals", "View All Rivals, Common Rivals")]
    [InlineData("View All Rankings (3)", "Duos", "View All Rankings (3), Duos")]
    public void Name_StartsWithVisibleLabelThenCard(string label, string card, string expected)
    {
        Assert.Equal(expected, ViewAllCta.Name(label, card));
        Assert.StartsWith(label, ViewAllCta.Name(label, card), StringComparison.Ordinal);
    }

    [Fact]
    public void RankingName_UsesTheSharedRule() =>
        Assert.Equal(ViewAllCta.Name("View All Rankings (12)", "Lead"), RankingViewAll.Name("View All Rankings (12)", "Lead"));

    [Fact]
    public void Labels_MatchTheWebCopyInTitleCase()
    {
        Assert.Equal("View Full Leaderboard", ViewAllCta.FullLeaderboardLabel);
        Assert.Equal("View All Rivals", ViewAllCta.RivalsLabel);
        Assert.Equal("View All Rankings", ViewAllCta.RankingsLabel);
        Assert.Equal("View All Scores", ViewAllCta.ScoresLabel);
        Assert.Equal("View All Bands", ViewAllCta.BandsLabel);
        Assert.Equal("View All", ViewAllCta.ListLabel);
        Assert.Equal("View All Results", ViewAllCta.ResultsLabel);
    }

    [Fact]
    public void RivalsAndSongDetail_UseTheSharedButton()
    {
        var consumers = Consumers();
        // Song Detail Score History + instrument + band cards, Leaderboards solo + band cards, the Rivals hub cards and
        // Rival Detail's category cards (#321: their former in-card text link is now this button).
        // The profile's Bands groups use the frosted ViewAllCard instead (surface-materials R7, issue #312).
        Assert.Equal(["LeaderboardsPage.xaml", "LeaderboardsPage.xaml", "RivalDetailPage.xaml", "RivalsPage.xaml", "SongDetailPage.xaml",
            "SongDetailPage.xaml", "SongDetailPage.xaml"],
            consumers.Select(c => c.File).Order(StringComparer.Ordinal));
    }

    [Fact]
    public void Consumers_SetNoLayoutOrColourOverrides()
    {
        string[] styled = ["Margin", "Padding", "MinHeight", "Height", "HorizontalAlignment", "HorizontalContentAlignment",
            "Background", "Foreground", "BorderBrush", "CornerRadius", "FontWeight", "FontSize", "HighContrastAdjustment"];
        foreach (var (file, button) in Consumers())
        {
            foreach (var property in styled)
                Assert.True(Attr(button, property) is null, $"{file}: {property} overrides FSTViewAllButtonStyle");
            // Visible text and UIA name come from the card's view model so the name always starts with the label.
            Assert.Matches(BindingTo("ViewAllText"), Attr(button, "Content"));
            Assert.Matches(BindingTo("ViewAllName"), Attr(button, "AutomationProperties.Name"));
            Assert.Matches(BindingTo("ViewAllAutomationId"), Attr(button, "AutomationProperties.AutomationId"));
        }
    }

    [Fact]
    public void Style_IsAccentFullWidthWithFluentMinimumTarget()
    {
        var style = XDocument.Load(Path.Combine(AppRoot, "Themes", "Styles.xaml")).Descendants()
            .Single(e => e.Name.LocalName == "Style" && Attr(e, "Key") == "FSTViewAllButtonStyle");
        Assert.Equal("{StaticResource AccentButtonStyle}", Attr(style, "BasedOn"));
        var setters = style.Elements().Where(e => e.Name.LocalName == "Setter")
            .ToDictionary(e => Attr(e, "Property")!, e => Attr(e, "Value"));
        Assert.Equal("Stretch", setters["HorizontalAlignment"]);
        Assert.Equal("{StaticResource FSTMinTargetSize}", setters["MinHeight"]);
        Assert.Equal("0,4,0,0", setters["Margin"]);
        Assert.Equal("None", setters["HighContrastAdjustment"]);
        Assert.False(setters.ContainsKey("Template"));
    }
}
