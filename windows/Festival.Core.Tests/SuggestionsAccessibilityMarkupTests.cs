using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #513 (accessibility backfill for #205, the Windows Suggestions page). The live checks are
/// <c>tools/windows/journeys/a11y-suggestions.json</c>; these keep the markup and code from regressing:
/// <list type="bullet">
/// <item>A filter flyout's switch lists are not Tab stops: an <c>ItemsControl</c> is a focusable control with no
/// automation name, so without <c>IsTabStop="False"</c> each expanded section adds a silent, unnamed stop (UIA reports the
/// window's input-site pane) before its first switch. Songs and Item Shop already opted out; Suggestions now does too.</item>
/// <item>Each filter flyout fits the space below its button when it opens, so its pinned Reset footer stays on screen at
/// 225% text in a compact window (Suggestions now does what Songs and Item Shop did).</item>
/// <item>A suggestion row re-resolves the brushes it sets in code (rival and accuracy pills, delta text, chips, separator)
/// when the contrast theme changes while it is shown, like <c>LeaderboardEntryRow</c> and <c>MetadataPill</c>
/// (pattern <c>metadata-pills</c>, "Live contrast switch").</item>
/// </list>
/// </summary>
public class SuggestionsAccessibilityMarkupTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    /// <summary>Reads an attribute by its local name.</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    [Theory]
    [InlineData("Pages/SuggestionsPage.xaml")]
    [InlineData("Pages/SongsPage.xaml")]
    [InlineData("Pages/ShopPage.xaml")]
    public void FilterFlyoutItemsControls_AreNotTabStops(string page)
    {
        var doc = XDocument.Load(Path.Combine(AppRoot, page));
        var flyouts = doc.Descendants().Where(e => e.Name.LocalName == "Flyout").ToList();
        Assert.NotEmpty(flyouts);
        var lists = flyouts.SelectMany(f => f.Descendants().Where(e => e.Name.LocalName == "ItemsControl")).ToList();
        Assert.NotEmpty(lists);
        Assert.All(lists, list => Assert.Equal("False", Attr(list, "IsTabStop")));
    }

    [Theory]
    [InlineData("Pages/SuggestionsPage.xaml.cs")]
    [InlineData("Pages/SongsPage.xaml.cs")]
    [InlineData("Pages/ShopPage.xaml.cs")]
    public void FilterFlyouts_FitTheWindowBelowTheirButton_OnOpening(string page)
    {
        // At 225% text a fixed MaxHeight pushed the pinned Reset footer below a compact window (issue #513).
        var source = File.ReadAllText(Path.Combine(AppRoot, page));
        Assert.Matches(@"FilterForm\.MaxHeight = Math\.Clamp\(below - 24, \d+, \d+\);", source);
    }

    [Fact]
    public void SuggestionsCardRows_AreOneTabStopPerCard()
    {
        var doc = XDocument.Load(Path.Combine(AppRoot, "Pages", "SuggestionsPage.xaml"));
        var rows = doc.Descendants().Single(e => e.Name.LocalName == "ItemsControl" && Attr(e, "ItemsSource") == "{x:Bind Rows}");
        Assert.Equal("False", Attr(rows, "IsTabStop"));
        Assert.Equal("Once", Attr(rows, "TabFocusNavigation"));
    }

    [Fact]
    public void SuggestionSongRow_ReResolvesItsBrushes_OnContrastThemeChange()
    {
        var source = File.ReadAllText(Path.Combine(AppRoot, "Controls", "SuggestionSongRow.cs"));
        Assert.Contains("ContrastTheme.Changed += OnColorsChanged", source);
        Assert.Contains("ContrastTheme.Changed -= OnColorsChanged", source);
        Assert.Matches(@"OnColorsChanged\([^)]*\)\s*=>\s*DispatcherQueue\?\.TryEnqueue\(ApplyColors\)", source);
        Assert.Matches(new Regex(@"private void ApplyColors\(\)\s*\{\s*PaintChrome\(\);[\s\S]{0,80}BuildMetadata\("), source);
        // Brushes resolved once from Application resources would keep the old theme's colour after a switch.
        Assert.DoesNotContain("Application.Current.Resources[", source);
    }
}
