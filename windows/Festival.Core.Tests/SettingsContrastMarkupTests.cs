using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #214: the Settings page follows contrast themes, including one switched on while the page is open.
/// Colours come from theme dictionaries (no hex literals in the page), and its scoped lightweight button styling
/// merges <c>Themes/*ButtonResources.xaml</c> theme dictionaries instead of <c>StaticResource</c> aliases, which
/// resolve once at load and keep the old theme's brush. The live checks are the Settings contrast runs in
/// <c>.agents/pages/settings/windows.md</c>.
/// </summary>
public class SettingsContrastMarkupTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    private static readonly string[] ButtonResourceFiles =
        ["NavRowButtonResources.xaml", "FirstRunButtonResources.xaml", "DangerButtonResources.xaml"];

    #region Helpers

    /// <summary>Loads a Festival.App XAML file.</summary>
    /// <param name="relative">Path under Festival.App.</param>
    /// <returns>The parsed document.</returns>
    private static XDocument Load(string relative) => XDocument.Load(Path.Combine(AppRoot, relative));

    /// <summary>Settings page markup.</summary>
    /// <returns>The parsed page.</returns>
    private static XDocument Page() => Load(Path.Combine("Pages", "SettingsPage.xaml"));

    /// <summary>Keys of one theme dictionary in a resource file.</summary>
    /// <param name="doc">Resource dictionary file.</param>
    /// <param name="theme">Theme dictionary key (<c>Default</c> or <c>HighContrast</c>).</param>
    /// <returns>The resource keys defined for that theme.</returns>
    private static HashSet<string> ThemeKeys(XDocument doc, string theme) =>
        doc.Descendants().Single(e => e.Name.LocalName == "ResourceDictionary" && Key(e) == theme)
            .Elements().Select(Key).OfType<string>().ToHashSet();

    /// <summary>Reads <c>x:Key</c>.</summary>
    /// <param name="element">Element.</param>
    /// <returns>The key, or null.</returns>
    private static string? Key(XElement element) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == "Key")?.Value;

    #endregion

    [Fact]
    public void SettingsPage_HasNoColourLiterals()
    {
        var literals = Page().Descendants().SelectMany(e => e.Attributes())
            .Where(a => Regex.IsMatch(a.Value, "^#[0-9A-Fa-f]{6,8}$"))
            .Select(a => $"{a.Parent!.Name.LocalName}.{a.Name.LocalName}={a.Value}").ToList();
        Assert.Empty(literals);
    }

    [Fact]
    public void SettingsPage_ScopedButtonStyling_UsesThemeDictionaries()
    {
        var aliases = Page().Descendants()
            .Where(e => e.Name.LocalName == "StaticResource" && (Key(e) ?? "").StartsWith("Button", StringComparison.Ordinal))
            .Select(Key).ToList();
        Assert.Empty(aliases);
        var merged = Page().Descendants().Where(e => e.Name.LocalName == "ResourceDictionary")
            .Select(e => e.Attributes().FirstOrDefault(a => a.Name.LocalName == "Source")?.Value).OfType<string>()
            .Select(Path.GetFileName).ToList();
        foreach (var file in ButtonResourceFiles) Assert.Contains(file, merged);
    }

    [Theory]
    [InlineData("NavRowButtonResources.xaml")]
    [InlineData("FirstRunButtonResources.xaml")]
    [InlineData("DangerButtonResources.xaml")]
    public void ButtonResources_DefineEveryKeyForBothThemes_WithSystemColoursInContrast(string file)
    {
        var doc = Load(Path.Combine("Themes", file));
        var defaults = ThemeKeys(doc, "Default");
        Assert.NotEmpty(defaults);
        Assert.Equal(defaults, ThemeKeys(doc, "HighContrast"));
        var contrast = doc.Descendants().Single(e => e.Name.LocalName == "ResourceDictionary" && Key(e) == "HighContrast");
        foreach (var brush in contrast.Elements())
        {
            var color = brush.Attributes().Single(a => a.Name.LocalName == "Color").Value;
            Assert.True(color == "Transparent" || color.StartsWith("{ThemeResource SystemColor", StringComparison.Ordinal),
                $"{file} HighContrast {Key(brush)} = {color}");
        }
    }
}
