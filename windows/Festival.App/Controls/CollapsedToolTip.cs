using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

/// <summary>
/// Closes an element's open tooltip when a responsive layout collapses the element (issue #571).
/// </summary>
/// <remarks>
/// WinUI does not close the tooltip of an element that goes <see cref="Visibility.Collapsed"/> while its pointer or
/// keyboard tooltip is open: no PointerExited or LostFocus reaches it, so the tooltip floats where the element was
/// (e.g. the compact title-bar search button after the window widens) and its windowed <c>PopupHost</c> stays in the
/// UI Automation tree. Attach this to every element that a width breakpoint swaps out.
/// </remarks>
public static class CollapsedToolTip
{
    #region Attach
    /// <summary>Closes <paramref name="element"/>'s tooltip whenever its <see cref="UIElement.Visibility"/> becomes
    /// <see cref="Visibility.Collapsed"/>.</summary>
    /// <param name="element">An element with a <see cref="ToolTipService"/> tooltip that a layout collapses.</param>
    public static void CloseWhenCollapsed(UIElement element)
    {
        Own(element);
        element.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (sender, _) =>
        {
            if (sender is UIElement target && target.Visibility == Visibility.Collapsed) Close(target);
        });
    }

    /// <summary>Closes the element's tooltip if it is open.</summary>
    /// <param name="element">The tooltip owner.</param>
    public static void Close(UIElement element)
    {
        if (ToolTipService.GetToolTip(element) is ToolTip owned) owned.IsOpen = false;
    }

    /// <summary>Wraps plain tooltip content (e.g. a XAML string) in a <see cref="ToolTip"/> the app can close.</summary>
    /// <param name="element">The tooltip owner.</param>
    /// <remarks>ToolTipService keeps the ToolTip it builds for plain content internal, and clearing the value does
    /// not close one that is already open, so the app must own the ToolTip object.</remarks>
    private static void Own(UIElement element)
    {
        var tip = ToolTipService.GetToolTip(element);
        if (tip is null or ToolTip) return;
        ToolTipService.SetToolTip(element, new ToolTip { Content = tip });
    }
    #endregion
}
