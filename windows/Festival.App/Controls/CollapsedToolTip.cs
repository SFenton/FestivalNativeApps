using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

/// <summary>
/// The responsive-swap contract (issue #571): closes every tooltip inside an element that a layout collapses, and hands
/// keyboard focus from the collapsed element to its replacement.
/// </summary>
/// <remarks>
/// WinUI does not close the tooltip of an element that goes <see cref="Visibility.Collapsed"/>, or sits inside one that
/// does, while its pointer or keyboard tooltip is open: no PointerExited or LostFocus reaches it, so the tooltip floats
/// where the element was (e.g. the compact title-bar search button after the window widens, an Instrument Selector circle
/// after the row turns compact) and its windowed <c>PopupHost</c> stays in the UI Automation tree. Attach
/// <see cref="CloseWhenCollapsed"/> to every element (or container) that a width breakpoint swaps out, set the tooltips
/// inside it with <see cref="Set"/>, and when the swapped-out element had focus (<see cref="HasFocusWithin"/>) move it with
/// <see cref="HandFocus"/>.
/// </remarks>
public static class CollapsedToolTip
{
    #region Tooltips
    /// <summary>Closes the tooltips of <paramref name="element"/> and of everything inside it whenever its
    /// <see cref="UIElement.Visibility"/> becomes <see cref="Visibility.Collapsed"/>.</summary>
    /// <param name="element">An element or container that a layout collapses.</param>
    /// <remarks>Plain tooltip content already set inside it (e.g. a XAML string) is wrapped in an owned
    /// <see cref="ToolTip"/> now and again on <c>Loaded</c>; set tooltips added later with <see cref="Set"/>.</remarks>
    public static void CloseWhenCollapsed(UIElement element)
    {
        OwnWithin(element);
        if (element is FrameworkElement framework) framework.Loaded += (_, _) => OwnWithin(framework);
        element.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (sender, _) =>
        {
            if (sender is UIElement target && target.Visibility == Visibility.Collapsed) CloseWithin(target);
        });
    }

    /// <summary>Sets <paramref name="element"/>'s tooltip as a <see cref="ToolTip"/> the app owns (so it can be closed),
    /// updating the content of the one already there rather than replacing it.</summary>
    /// <param name="element">The tooltip owner.</param>
    /// <param name="content">Tooltip content, or <see langword="null"/> to remove the tooltip (closing it first).</param>
    /// <remarks>ToolTipService keeps the ToolTip it builds for plain content internal, and replacing or clearing the value
    /// does not close one that is already open.</remarks>
    public static void Set(UIElement element, object? content)
    {
        var current = ToolTipService.GetToolTip(element);
        if (content is null)
        {
            if (current is ToolTip open) open.IsOpen = false;
            if (current is not null) ToolTipService.SetToolTip(element, null);
            return;
        }
        if (content is ToolTip tip) ToolTipService.SetToolTip(element, tip);
        else if (current is ToolTip owned) owned.Content = content;
        else ToolTipService.SetToolTip(element, new ToolTip { Content = content });
    }

    /// <summary>Closes the owned tooltips of <paramref name="root"/> and of every element inside it.</summary>
    /// <param name="root">Collapsed element or container.</param>
    /// <remarks>A plain tooltip value (e.g. a string in an item template realized after <c>Loaded</c>) has no ToolTip the
    /// app can reach, so an open tooltip in the window showing an equal value is closed instead.</remarks>
    public static void CloseWithin(UIElement root)
    {
        List<object>? plain = null;
        foreach (var node in SelfAndDescendants(root))
        {
            if (node is not UIElement element) continue;
            switch (ToolTipService.GetToolTip(element))
            {
                case ToolTip { IsOpen: true } owned:
                    owned.IsOpen = false;
                    break;
                case ToolTip or null:
                    break;
                case var value:
                    (plain ??= []).Add(value);
                    break;
            }
        }
        if (plain is null || root.XamlRoot is not { } xamlRoot) return;
        foreach (var popup in VisualTreeHelper.GetOpenPopupsForXamlRoot(xamlRoot))
            if (popup.Child is ToolTip { IsOpen: true } open && plain.Any(value => Equals(value, open.Content))) open.IsOpen = false;
    }

    /// <summary>Wraps plain tooltip content in and under <paramref name="root"/> in owned <see cref="ToolTip"/>s.</summary>
    /// <param name="root">Container.</param>
    private static void OwnWithin(DependencyObject root)
    {
        foreach (var node in SelfAndDescendants(root))
        {
            if (node is UIElement element && ToolTipService.GetToolTip(element) is { } tip and not ToolTip)
                ToolTipService.SetToolTip(element, new ToolTip { Content = tip });
        }
    }

    /// <summary>The element and its visual descendants, depth first.</summary>
    /// <param name="root">Root.</param>
    /// <returns>Nodes.</returns>
    private static IEnumerable<DependencyObject> SelfAndDescendants(DependencyObject root)
    {
        var stack = new Stack<DependencyObject>();
        stack.Push(root);
        while (stack.Count > 0)
        {
            var node = stack.Pop();
            yield return node;
            for (var i = VisualTreeHelper.GetChildrenCount(node) - 1; i >= 0; i--) stack.Push(VisualTreeHelper.GetChild(node, i));
        }
    }
    #endregion

    #region Focus hand-off
    /// <summary>Whether keyboard focus is on <paramref name="element"/> or inside it (e.g. a search box's TextBox).</summary>
    /// <param name="element">Element about to be collapsed.</param>
    /// <returns><see langword="true"/> when the focused element is <paramref name="element"/> or a descendant.</returns>
    public static bool HasFocusWithin(UIElement element)
    {
        if (element.XamlRoot is null || element.Visibility != Visibility.Visible) return false;
        for (var node = FocusManager.GetFocusedElement(element.XamlRoot) as DependencyObject; node is not null;
             node = VisualTreeHelper.GetParent(node))
        {
            if (ReferenceEquals(node, element)) return true;
        }
        return false;
    }

    /// <summary>
    /// Moves focus to the replacement of a collapsed element with <see cref="FocusState.Programmatic"/>: the user resized,
    /// so the newcomer opens no keyboard tooltip, and focus doesn't fall to the next control (opening <em>its</em> tooltip).
    /// </summary>
    /// <param name="anchor">Element whose dispatcher retries once after layout when the target isn't focusable yet (a
    /// container that has just become visible realizes its items in the next layout pass).</param>
    /// <param name="target">Resolves the replacement; may return <see langword="null"/>.</param>
    public static void HandFocus(DependencyObject anchor, Func<Control?> target) =>
        HandFocusWith(anchor, () => target()?.Focus(FocusState.Programmatic) == true);

    /// <summary>As <see cref="HandFocus"/>, for a replacement that focuses itself (e.g.
    /// <see cref="InstrumentSelector.FocusCurrent"/>), which must use <see cref="FocusState.Programmatic"/>.</summary>
    /// <param name="anchor">Element whose dispatcher retries once after layout.</param>
    /// <param name="focus">Focuses the replacement; returns whether it took focus.</param>
    public static void HandFocusWith(DependencyObject anchor, Func<bool> focus)
    {
        if (focus()) return;
        anchor.DispatcherQueue?.TryEnqueue(DispatcherQueuePriority.Low, () => focus());
    }
    #endregion
}
