using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Layout geometry
/// <summary>
/// Element positions for per-scroll-frame handlers (#642). <c>TransformToVisual</c> creates a new WinRT transform object on
/// every call, and C#/WinRT adds GC memory pressure for each wrapper it makes, so measuring a few elements on every
/// scroll frame induced full (gen2) collections that stalled scrolling. A handler that runs while a scroll moves
/// transforms one element it scrolls with (a list's panel, a scroller's content) and places the rest by their layout
/// offsets (<see cref="UIElement.ActualOffset"/>, a value with no wrapper) within it.
/// </summary>
internal static class LayoutGeometry
{
    /// <summary>
    /// An element's top relative to an ancestor from the layout offsets on the way up. Render transforms are ignored;
    /// composition translations (the fade entrances) are ignored by <c>TransformToVisual</c> as well.
    /// </summary>
    /// <param name="element">Element.</param>
    /// <param name="ancestor">Ancestor that scrolls with it.</param>
    /// <returns>Top (epx), or <see langword="null"/> when <paramref name="ancestor"/> is not an ancestor.</returns>
    public static double? TopWithin(UIElement element, UIElement ancestor)
    {
        var top = 0.0;
        for (DependencyObject? node = element; node is not null; node = VisualTreeHelper.GetParent(node))
        {
            if (ReferenceEquals(node, ancestor)) return top;
            if (node is UIElement part) top += part.ActualOffset.Y;
        }
        return null;
    }
}
#endregion
