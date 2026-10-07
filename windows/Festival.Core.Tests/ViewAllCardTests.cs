using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Issue #312, pattern <c>surface-materials</c> R7: the profile Bands groups' "View All Bands (N)" is the web's frosted
/// <c>BandViewAllCard</c> (<c>Controls/ViewAllCard</c>): the canonical card surface and stroke, full width, a 48 epx
/// minimum target, the centred label with an in-card chevron, never the purple <c>FSTViewAllButtonStyle</c>.
/// </summary>
public class ViewAllCardTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    private const string ControlsNs = "using:Festival.App.Controls";

    #region Helpers

    /// <summary>Reads an attribute by its local name (XAML attached properties keep the dotted name).</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Local attribute name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Every <c>controls:ViewAllCard</c> in Festival.App, with its file.</summary>
    /// <returns>(file name, element) pairs.</returns>
    private static List<(string File, XElement Card)> Consumers() =>
        Directory.EnumerateFiles(AppRoot, "*.xaml", SearchOption.AllDirectories)
            .Where(path => !Path.GetRelativePath(AppRoot, path).Split(Path.DirectorySeparatorChar)
                .Any(part => part is "bin" or "obj"))
            .SelectMany(path => XDocument.Load(path).Descendants()
                .Where(e => e.Name.LocalName == "ViewAllCard" && e.Name.NamespaceName == ControlsNs)
                .Select(e => (Path.GetFileName(path), e)))
            .ToList();

    /// <summary>The implicit <c>controls:ViewAllCard</c> style's setters.</summary>
    /// <returns>Property to value.</returns>
    private static Dictionary<string, string?> StyleSetters()
    {
        var document = XDocument.Load(Path.Combine(AppRoot, "Themes", "Styles.xaml"));
        var style = document.Descendants().Single(e => e.Name.LocalName == "Style" && Attr(e, "TargetType") == "controls:ViewAllCard");
        Assert.Null(Attr(style, "Key"));
        Assert.Null(Attr(style, "BasedOn"));
        return style.Elements().Where(e => e.Name.LocalName == "Setter")
            .ToDictionary(e => Attr(e, "Property")!, e => Attr(e, "Value"));
    }

    #endregion

    [Fact]
    public void Style_IsTheFrostedCardSurfaceWithA48EpxTarget()
    {
        var setters = StyleSetters();
        Assert.Equal("{ThemeResource FSTCardSurfaceBrush}", setters["Background"]);
        Assert.Equal("{ThemeResource FSTCardStrokeBrush}", setters["BorderBrush"]);
        Assert.Equal("1", setters["BorderThickness"]);
        Assert.Equal("{StaticResource OverlayCornerRadius}", setters["CornerRadius"]);
        Assert.Equal("Stretch", setters["HorizontalAlignment"]);
        Assert.Equal("{StaticResource FSTViewAllCardMinHeight}", setters["MinHeight"]);
        Assert.False(setters.ContainsKey("Template"));
        var height = XDocument.Load(Path.Combine(AppRoot, "Themes", "Styles.xaml")).Descendants()
            .Single(e => e.Name.LocalName == "Double" && Attr(e, "Key") == "FSTViewAllCardMinHeight");
        Assert.Equal("48", height.Value);
    }

    [Fact]
    public void Control_CentresTheLabelWithADecorativeChevronAndCardHoverFills()
    {
        var source = File.ReadAllText(Path.Combine(AppRoot, "Controls", "ViewAllCard.cs"));
        Assert.Contains("class ViewAllCard : Button", source, StringComparison.Ordinal);
        Assert.Contains("Glyph = \"\\uE76C\"", source, StringComparison.Ordinal);
        Assert.Contains("AutomationProperties.SetAccessibilityView(chevron, AccessibilityView.Raw)", source, StringComparison.Ordinal);
        Assert.Contains("HorizontalAlignment = HorizontalAlignment.Center", source, StringComparison.Ordinal);
        Assert.Contains("FontWeights.SemiBold", source, StringComparison.Ordinal);
        Assert.Contains("\"FSTCardSurfacePointerOverBrush\"", source, StringComparison.Ordinal);
        Assert.DoesNotContain("Accent", source, StringComparison.Ordinal);
    }

    [Fact]
    public void ProfileBands_UseTheFrostedCardNotThePurpleCta()
    {
        var consumers = Consumers();
        Assert.Equal(["PlayerProfileView.xaml"], consumers.Select(c => c.File));
        string[] styled = ["Style", "Margin", "Padding", "MinHeight", "Height", "HorizontalAlignment", "HorizontalContentAlignment",
            "Background", "Foreground", "BorderBrush", "CornerRadius", "FontWeight", "FontSize", "Content"];
        foreach (var (file, card) in consumers)
        {
            foreach (var property in styled)
                Assert.True(Attr(card, property) is null, $"{file}: {property} overrides the ViewAllCard style");
            Assert.Equal("{x:Bind ViewAllText}", Attr(card, "Label"));
            Assert.Equal("{x:Bind ViewAllName}", Attr(card, "AutomationProperties.Name"));
            Assert.Equal("{x:Bind ViewAllAutomationId}", Attr(card, "AutomationProperties.AutomationId"));
        }
        var profile = File.ReadAllText(Path.Combine(AppRoot, "Controls", "PlayerProfileView.xaml"));
        Assert.DoesNotContain("FSTViewAllButtonStyle", profile, StringComparison.Ordinal);
    }
}
