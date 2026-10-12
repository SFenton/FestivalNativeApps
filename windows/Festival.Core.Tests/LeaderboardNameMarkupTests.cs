using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards the leaderboard row name (pattern <c>leaderboard-row</c> R3, issues #292 and #455): it is the shared
/// <c>MarqueeText</c> (a long name scrolls inside its column), wraps onto more lines at large Windows text sizes instead of
/// scrolling or ellipsizing, and stays out of the UIA tree so Narrator reads it once in the row's name. The live checks are
/// <c>tools/windows/journeys/a11y-leaderboard-names.json</c> (<c>ui_ci.py</c> <c>leaderboard-names*</c>).
/// </summary>
public class LeaderboardNameMarkupTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    [Fact]
    public void RowNameIsARawMarqueeThatWrapsAtLargeText()
    {
        var row = XDocument.Load(Path.Combine(AppRoot, "Controls", "LeaderboardEntryRow.xaml"));
        var name = Assert.Single(row.Descendants(), e => Attr(e, "Name") == "NameText");

        Assert.Equal("MarqueeText", name.Name.LocalName);
        Assert.Equal("True", Attr(name, "WrapsAtLargeText"));
        Assert.Equal("Raw", Attr(name, "AutomationProperties.AccessibilityView"));
    }
}
