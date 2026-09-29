using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Services;

#region Contrast theme
/// <summary>
/// Windows contrast-theme state and the contrast role brushes (<c>Themes/Styles.xaml</c>: brand hues by default, system
/// colours under a contrast theme). Code that computes a brand tint (accuracy pills, Shop pulse) asks <see cref="IsOn"/>
/// and falls back to a role brush.
/// </summary>
public static class ContrastTheme
{
    private static Windows.UI.ViewManagement.AccessibilitySettings? settings;

    /// <summary>Whether a Windows contrast theme is on (read live; the settings object is created once).</summary>
    public static bool IsOn => (settings ??= new Windows.UI.ViewManagement.AccessibilitySettings()).HighContrast;

    /// <summary>Looks up an app brush, resolved for the current theme.</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Brush.</returns>
    public static Brush Brush(string key) => (Brush)Application.Current.Resources[key];
}
#endregion
