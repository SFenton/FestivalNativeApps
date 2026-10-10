using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

/// <summary>
/// Closes an element's open tooltip when a responsive layout collapses the element (issue #571).
/// </summary>
/// <remarks>
/// WinUI does not close the tooltip of an element that goes <see cref="Visibility.Collapsed"/> while its pointer or
/// keyboard tooltip is open: no PointerExited or LostFocus reaches it, so the tooltip floats where the element was
/// (e.g. the compact title-bar search button after the window widens) and its windowed <c>PopupHost</c> stays in the
/// UI Automation tree. Attach this to every element that a width breakpoint swaps out, or
/// <see cref="CloseWithinWhenCollapsed"/> to a container that a breakpoint swaps out as a whole.
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

    /// <summary>Closes the tooltip of every element inside <paramref name="container"/> whenever the container's
    /// <see cref="UIElement.Visibility"/> becomes <see cref="Visibility.Collapsed"/>.</summary>
    /// <param name="container">A layout (e.g. a row of buttons) that a breakpoint swaps out as a whole; its children
    /// keep their own <c>Visible</c> value, so <see cref="CloseWhenCollapsed"/> on them never fires.</param>
    /// <remarks>The tooltips inside must be app-owned: give code-built children theirs with <see cref="Set"/> and
    /// XAML string tooltips an owned one with <see cref="Own"/>.</remarks>
    public static void CloseWithinWhenCollapsed(UIElement container) =>
        container.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (sender, _) =>
        {
            if (sender is UIElement target && target.Visibility == Visibility.Collapsed) CloseWithin(target);
        });

    /// <summary>Closes the element's tooltip if it is open.</summary>
    /// <param name="element">The tooltip owner.</param>
    public static void Close(UIElement element)
    {
        if (ToolTipService.GetToolTip(element) is ToolTip owned) owned.IsOpen = false;
    }

    /// <summary>Closes the tooltips of <paramref name="root"/> and all its visual descendants.</summary>
    /// <param name="root">Subtree root.</param>
    public static void CloseWithin(DependencyObject root)
    {
        if (root is UIElement element) Close(element);
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < count; i++) CloseWithin(VisualTreeHelper.GetChild(root, i));
    }

    /// <summary>Sets <paramref name="element"/>'s tooltip text as an app-owned <see cref="ToolTip"/>, updating the
    /// existing owned tooltip's content rather than replacing it (a replaced open tooltip cannot be closed).</summary>
    /// <param name="element">The tooltip owner.</param>
    /// <param name="content">Tooltip content.</param>
    public static void Set(UIElement element, object content)
    {
        if (ToolTipService.GetToolTip(element) is ToolTip owned) owned.Content = content;
        else ToolTipService.SetToolTip(element, new ToolTip { Content = content });
    }

    /// <summary>Wraps plain tooltip content (e.g. a XAML string) in a <see cref="ToolTip"/> the app can close.</summary>
    /// <param name="element">The tooltip owner.</param>
    /// <remarks>ToolTipService keeps the ToolTip it builds for plain content internal, and clearing the value does
    /// not close one that is already open, so the app must own the ToolTip object.</remarks>
    public static void Own(UIElement element)
    {
        var tip = ToolTipService.GetToolTip(element);
        if (tip is null or ToolTip) return;
        ToolTipService.SetToolTip(element, new ToolTip { Content = tip });
    }
    #endregion
}
