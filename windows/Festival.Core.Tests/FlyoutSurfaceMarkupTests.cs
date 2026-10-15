using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #641: every menu, flyout and ComboBox drop-down paints the one app flyout surface. WinUI 2.x menus ship a
/// transparent presenter that relies on a windowed popup's system backdrop, which in-window popups (#534) never get. The
/// live check is <c>tools/windows/journeys/a11y-menu-surface.json</c> (pixel probes per transparency mode).
/// </summary>
public class FlyoutSurfaceMarkupTests
{
    private static readonly string AppRoot =
        Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App"));

    private static readonly XNamespace Xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

    /// <summary>The app's dark ("Default") theme dictionary in Themes/Styles.xaml.</summary>
    /// <returns>The dictionary element.</returns>
    private static XElement DefaultTheme() =>
        XDocument.Load(Path.Combine(AppRoot, "Themes", "Styles.xaml")).Descendants()
            .Single(e => e.Name.LocalName == "ResourceDictionary" && (string?)e.Attribute(Xaml + "Key") == "Default");

    [Theory]
    [InlineData("MenuFlyoutPresenterBackground")]
    [InlineData("CommandBarFlyoutBackground")]
    [InlineData("FlyoutPresenterBackground")]
    [InlineData("ComboBoxDropDownBackground")]
    public void PresenterBackgrounds_UseTheAppFlyoutSurface(string key)
    {
        var alias = DefaultTheme().Elements().SingleOrDefault(e => (string?)e.Attribute(Xaml + "Key") == key);

        Assert.NotNull(alias);
        Assert.Equal("StaticResource", alias.Name.LocalName);
        Assert.Equal("FSTFlyoutSurfaceBrush", (string?)alias.Attribute("ResourceKey"));
    }

    [Fact]
    public void FlyoutSurface_IsAcrylicWithAnOpaqueFallback()
    {
        var brush = DefaultTheme().Elements().Single(e => (string?)e.Attribute(Xaml + "Key") == "FSTFlyoutSurfaceBrush");

        Assert.Equal("AcrylicBrush", brush.Name.LocalName);
        var fallback = (string?)brush.Attribute("FallbackColor");
        Assert.NotNull(fallback);
        Assert.Matches("^#FF[0-9A-Fa-f]{6}$", fallback);
    }

    [Fact]
    public void ApplyTransparency_SwitchesTheFlyoutSurfaceToItsFallback()
    {
        var source = File.ReadAllText(Path.Combine(AppRoot, "MainWindow.xaml.cs"));

        Assert.Matches(@"AcrylicSurfaceKeys\s*=\s*\[[^\]]*""FSTFlyoutSurfaceBrush""", source);
        Assert.Contains("acrylic.AlwaysUseFallback = !transparent", source);
    }
}
