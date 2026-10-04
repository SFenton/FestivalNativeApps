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
    private static Windows.UI.ViewManagement.UISettings? uiSettings;
    private static EventHandler? changed;

    /// <summary>Whether a Windows contrast theme is on (read live; the settings object is created once).</summary>
    public static bool IsOn => (settings ??= new Windows.UI.ViewManagement.AccessibilitySettings()).HighContrast;

    /// <summary>
    /// Raised on a background thread when system colours change, which includes switching a contrast theme on or off
    /// (<c>HighContrastChanged</c> needs a CoreWindow). One shared <c>UISettings</c> serves every code-built control that
    /// must re-resolve its role brushes; handlers marshal to their own dispatcher.
    /// </summary>
    public static event EventHandler? Changed
    {
        add
        {
            if (uiSettings is null)
            {
                uiSettings = new Windows.UI.ViewManagement.UISettings();
                uiSettings.ColorValuesChanged += (_, _) => changed?.Invoke(null, EventArgs.Empty);
            }
            changed += value;
        }
        remove => changed -= value;
    }

    /// <summary>Looks up an app brush, resolved for the current theme.</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Brush.</returns>
    public static Brush Brush(string key) => (Brush)Application.Current.Resources[key];
}
#endregion
