using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #534: every app flyout and AutoSuggestBox opens inside the app window. A windowed WinUI popup opens in
/// its own <c>PopupHost</c> bridge whose input site is exactly the bridge's size, which Axe.Windows reports as
/// <c>BoundingRectangleCompletelyObscuresContainer</c> (windows-accessibility.md open item 8). The live check is the
/// accessibility matrix (<c>tools/windows/a11y_matrix.py --scan</c>); this keeps new markup from regressing.
/// </summary>
public class PopupHostingMarkupTests
{
    private static readonly string AppRoot =
        Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App"));

    #region Helpers

    /// <summary>App source files of one kind, skipping build output.</summary>
    /// <param name="pattern">File pattern.</param>
    /// <returns>Paths relative to Festival.App.</returns>
    private static IEnumerable<string> Sources(string pattern) =>
        Directory.EnumerateFiles(AppRoot, pattern, SearchOption.AllDirectories)
            .Select(path => Path.GetRelativePath(AppRoot, path))
            .Where(path => !path.StartsWith("bin", StringComparison.OrdinalIgnoreCase)
                           && !path.StartsWith("obj", StringComparison.OrdinalIgnoreCase));

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Every XAML element with one of the given local names, as <c>file: name</c> plus the element.</summary>
    /// <param name="names">Element local names.</param>
    /// <returns>Matches across Festival.App.</returns>
    private static List<(string Where, XElement Element)> Elements(params string[] names) =>
        Sources("*.xaml")
            .SelectMany(file => XDocument.Load(Path.Combine(AppRoot, file)).Descendants()
                .Where(e => names.Contains(e.Name.LocalName))
                .Select(e => ($"{file}: {e.Name.LocalName} {Attr(e, "Name")}", e)))
            .ToList();

    #endregion

    [Fact]
    public void XamlFlyouts_ConstrainToRootBounds()
    {
        var flyouts = Elements("Flyout", "MenuFlyout", "CommandBarFlyout");
        Assert.NotEmpty(flyouts);
        var windowed = flyouts.Where(f => Attr(f.Element, "ShouldConstrainToRootBounds") != "True").Select(f => f.Where);
        Assert.Empty(windowed);
    }

    [Fact]
    public void CodeFlyouts_ConstrainToRootBounds()
    {
        // The object initializer (balanced braces) must set it; a bare `new` without one fails.
        var created = new Regex(
            @"new\s+(MenuFlyout|Flyout|CommandBarFlyout|Popup)\b\s*(\(\s*\))?\s*(?<init>\{(?>[^{}]+|\{(?<d>)|\}(?<-d>))*(?(d)(?!))\})?");
        var found = Sources("*.cs")
            .SelectMany(file => created.Matches(File.ReadAllText(Path.Combine(AppRoot, file)))
                .Select(m => (Where: $"{file}: new {m.Groups[1].Value}", Init: m.Groups["init"].Value)))
            .ToList();
        Assert.NotEmpty(found);
        Assert.Empty(found.Where(f => !f.Init.Contains("ShouldConstrainToRootBounds = true", StringComparison.Ordinal))
            .Select(f => f.Where));
    }

    [Fact]
    public void AutoSuggestBoxes_KeepSuggestionsInWindow()
    {
        var boxes = Elements("AutoSuggestBox");
        Assert.NotEmpty(boxes);
        Assert.Empty(boxes.Where(b => Attr(b.Element, "PopupHosting.InWindow") != "True").Select(b => b.Where));
    }
}
