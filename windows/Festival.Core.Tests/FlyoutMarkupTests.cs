using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #254: a <c>MenuFlyoutSeparator</c> placed outside a menu (e.g. in a plain <c>Flyout</c>'s panel) is a
/// focusable <c>Control</c> with no automation name, so keyboard Tab stopped on it and Narrator read nothing. Plain
/// flyouts draw dividers with a non-focusable <c>Rectangle</c> filled with <c>DividerStrokeColorDefaultBrush</c>.
/// </summary>
public class FlyoutMarkupTests
{
    private static readonly string AppRoot =
        Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App"));

    /// <summary>Elements whose items are menu entries, so a separator inside them is skipped by keyboard focus.</summary>
    private static readonly HashSet<string> MenuHosts =
        ["MenuFlyout", "MenuFlyoutSubItem", "MenuBarItem", "MenuFlyout.Items", "MenuFlyoutSubItem.Items", "MenuBarItem.Items"];

    #region Helpers

    /// <summary>Every XAML file in Festival.App outside build output.</summary>
    /// <returns>Absolute paths.</returns>
    private static IEnumerable<string> XamlFiles() =>
        Directory.EnumerateFiles(AppRoot, "*.xaml", SearchOption.AllDirectories)
            .Where(p => Path.GetRelativePath(AppRoot, p).Split(Path.DirectorySeparatorChar)[0] is not ("bin" or "obj"));

    #endregion

    [Fact]
    public void Scan_FindsAppXaml()
    {
        Assert.Contains(XamlFiles(), p => Path.GetFileName(p) == "MainWindow.xaml");
    }

    [Fact]
    public void MenuFlyoutSeparators_OnlyAppearInsideMenus()
    {
        var misplaced = XamlFiles()
            .SelectMany(path => XDocument.Load(path).Descendants()
                .Where(e => e.Name.LocalName == "MenuFlyoutSeparator"
                            && !e.Ancestors().Any(a => MenuHosts.Contains(a.Name.LocalName)))
                .Select(_ => Path.GetFileName(path)))
            .ToList();
        Assert.Empty(misplaced);
    }

    [Fact]
    public void ProfileFlyout_SelectedSummary_UsesNonFocusableDivider()
    {
        var doc = XDocument.Load(Path.Combine(AppRoot, "MainWindow.xaml"));
        var summary = doc.Descendants().Single(e =>
            e.Attributes().Any(a => a.Name.LocalName == "AutomationProperties.AutomationId" && a.Value == "fst.profile.selected"));
        var divider = Assert.Single(summary.Elements(), e => e.Name.LocalName == "Rectangle");
        Assert.Equal("{ThemeResource DividerStrokeColorDefaultBrush}",
            divider.Attributes().Single(a => a.Name.LocalName == "Fill").Value);
        Assert.DoesNotContain(summary.Descendants(), e => e.Name.LocalName == "MenuFlyoutSeparator");
    }
}
