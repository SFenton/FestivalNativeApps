using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Resource lookup
/// <summary>Theme-aware brush lookup for code-built band visuals.</summary>
internal static class BandsResources
{
    /// <summary>Finds an application brush (merged and theme dictionaries included).</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>The brush, or a neutral gray when missing.</returns>
    public static Brush Brush(string key) =>
        Application.Current.Resources.TryGetValue(key, out var value) && value is Brush brush
            ? brush : new SolidColorBrush(Colors.Gray);
}
#endregion
