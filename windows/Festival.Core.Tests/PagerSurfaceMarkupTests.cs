using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #319 (surface-materials R1, leaderboard-row R5): the board pager's arrow buttons and <c>page / total</c>
/// badge draw on the rows' card surface (<c>FSTCardSurfaceBrush</c> + <c>FSTCardStrokeBrush</c>), never a pager-only
/// opaque plate, and the Your Page jump button in the board footer does too.
/// </summary>
public class PagerSurfaceMarkupTests
{
    private const string CardSurface = "{ThemeResource FSTCardSurfaceBrush}";
    private const string CardStroke = "{ThemeResource FSTCardStrokeBrush}";

    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    #region Helpers

    /// <summary>Loads a Festival.App XAML file.</summary>
    /// <param name="relative">Path under Festival.App.</param>
    /// <returns>The parsed document.</returns>
    private static XDocument Load(string relative) => XDocument.Load(Path.Combine(AppRoot, relative));

    /// <summary>Reads an attribute by its local name.</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Reads a style's setter value.</summary>
    /// <param name="style">Style element.</param>
    /// <param name="property">Setter property.</param>
    /// <returns>The value, or null.</returns>
    private static string? Setter(XElement style, string property) =>
        style.Elements().Where(e => e.Name.LocalName == "Setter" && Attr(e, "Property") == property)
            .Select(e => Attr(e, "Value")).FirstOrDefault();

    /// <summary>Finds a keyed style.</summary>
    /// <param name="doc">Document.</param>
    /// <param name="key">x:Key.</param>
    /// <returns>The style element.</returns>
    private static XElement Style(XDocument doc, string key) =>
        doc.Descendants().Single(e => e.Name.LocalName == "Style" && Attr(e, "Key") == key);

    #endregion

    [Fact]
    public void PagerDimming_FollowsTheModelOnEveryUpdate()
    {
        // Page 1's First/Previous start disabled without an IsEnabledChanged, so the dim must also follow the model.
        var code = File.ReadAllText(Path.Combine(AppRoot, "Controls", "LeaderboardsPager.xaml.cs"));
        Assert.Contains("pager.CanGoBack : pager.CanGoForward", code);
        Assert.Contains("foreach (var button in Buttons) ApplyDimming(button);", code);
        Assert.DoesNotContain("button.Parent", code);
        // Every host opacity goes through PagerDimming, which keeps a contrast theme's host (Window surface, WindowText rim)
        // fully opaque (surface-materials R4), and a live contrast switch re-applies it.
        Assert.Single(System.Text.RegularExpressions.Regex.Matches(code, @"\.Opacity\s*="));
        Assert.Contains("Host(button).Opacity = PagerDimming.HostOpacity(available, contrast);", code);
        Assert.Contains("PagerDimming.GrayTextGlyph(available, contrast)", code);
        Assert.Contains("ContrastTheme.Changed += OnColorsChanged;", code);
        Assert.Contains("Unloaded += (_, _) => ContrastTheme.Changed -= OnColorsChanged;", code);
        // Contrast themes ignore the opacity dim; GrayText on Window is the system disabled cue there.
        var xaml = File.ReadAllText(Path.Combine(AppRoot, "Controls", "LeaderboardsPager.xaml"));
        Assert.Contains("x:Key=\"ButtonForegroundDisabled\" Color=\"{ThemeResource SystemColorGrayTextColor}\"", xaml);
    }

    [Fact]
    public void PagerButtons_DrawOnTheRowCardSurface()
    {
        var doc = Load(Path.Combine("Controls", "LeaderboardsPager.xaml"));
        var surface = Style(doc, "PagerSurfaceStyle");
        Assert.Equal(CardSurface, Setter(surface, "Background"));
        Assert.Equal(CardStroke, Setter(surface, "BorderBrush"));
        Assert.Equal("False", Setter(surface, "IsHitTestVisible"));
        // The button is transparent over the card, so hover and press tint the card like a row instead of replacing it.
        var button = Style(doc, "PagerButtonStyle");
        Assert.Equal("Transparent", Setter(button, "Background"));
        Assert.Equal("40", Setter(button, "Width"));
        Assert.Equal("40", Setter(button, "Height"));

        foreach (var name in new[] { "First", "Previous", "Next", "Last" })
        {
            var host = doc.Descendants().Single(e => Attr(e, "Name") == name + "Host");
            var children = host.Elements().ToList();
            Assert.Equal("Border", children[0].Name.LocalName);
            Assert.Equal("{StaticResource PagerSurfaceStyle}", Attr(children[0], "Style"));
            Assert.Equal(name, Attr(children[1], "Name"));
        }
    }

    [Fact]
    public void PageBadge_DrawsOnTheRowCardSurface()
    {
        var doc = Load(Path.Combine("Controls", "LeaderboardsPager.xaml"));
        var info = doc.Descendants().Single(e => Attr(e, "Name") == "Info");
        var badge = info.Parent!;
        Assert.Equal("Border", badge.Name.LocalName);
        Assert.Equal(CardSurface, Attr(badge, "Background"));
        Assert.Equal(CardStroke, Attr(badge, "BorderBrush"));
    }

    [Theory]
    [InlineData("Controls/LeaderboardsSpotlight.xaml")]
    [InlineData("Pages/LeaderboardsSongPage.xaml")]
    public void YourPageButton_DrawsOnTheRowCardSurface(string file)
    {
        var jump = Load(file).Descendants().Single(e => e.Name.LocalName == "Button"
            && Attr(e, "AutomationProperties.Name") == "Jump to your page");
        Assert.Equal(CardSurface, Attr(jump, "Background"));
        Assert.Equal(CardStroke, Attr(jump, "BorderBrush"));
    }

    [Fact]
    public void NoPagerOnlyPlateBrushes()
    {
        foreach (var path in Directory.EnumerateFiles(AppRoot, "*.xaml", SearchOption.AllDirectories)
                     .Concat(Directory.EnumerateFiles(AppRoot, "*.cs", SearchOption.AllDirectories)))
        {
            if (path.Contains(Path.DirectorySeparatorChar + "obj" + Path.DirectorySeparatorChar, StringComparison.Ordinal)
                || path.Contains(Path.DirectorySeparatorChar + "bin" + Path.DirectorySeparatorChar, StringComparison.Ordinal)) continue;
            var text = File.ReadAllText(path);
            Assert.DoesNotContain("FSTPagerButtonBrush", text, StringComparison.Ordinal);
            Assert.DoesNotContain("FSTPagerBadgeBrush", text, StringComparison.Ordinal);
        }
    }
}
