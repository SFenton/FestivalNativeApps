using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Popup hosting
/// <summary>
/// Keeps a control's template popups inside the app window. A desktop WinUI popup defaults to windowed
/// (<c>ShouldConstrainToRootBounds="False"</c>): it opens in its own <c>PopupHost</c> bridge window whose input site is
/// exactly the bridge's size, which Axe.Windows reports as <c>BoundingRectangleCompletelyObscuresContainer</c> (issue
/// #534, windows-accessibility.md open item 8). Every app <see cref="FlyoutBase"/> sets
/// <c>ShouldConstrainToRootBounds="True"</c> directly; <c>PopupHosting.InWindow</c> does the same for a template popup
/// the app can't reach in markup, such as the <see cref="AutoSuggestBox"/> suggestions list
/// (<c>SuggestionsPopup</c>, windowed in the WinUI template). The platform only accepts the change before a popup first
/// opens windowed, so it runs on <c>Loaded</c>.
/// </summary>
public static class PopupHosting
{
    /// <summary>Constrain the control's template popups to the window.</summary>
    public static readonly DependencyProperty InWindowProperty = DependencyProperty.RegisterAttached(
        "InWindow", typeof(bool), typeof(PopupHosting), new PropertyMetadata(false, OnInWindowChanged));

    /// <summary>Gets <c>InWindow</c>.</summary>
    /// <param name="element">Control.</param>
    /// <returns>Whether enabled.</returns>
    public static bool GetInWindow(Control element) => (bool)element.GetValue(InWindowProperty);

    /// <summary>Sets <c>InWindow</c>.</summary>
    /// <param name="element">Control.</param>
    /// <param name="value">Whether enabled.</param>
    public static void SetInWindow(Control element, bool value) => element.SetValue(InWindowProperty, value);

    /// <summary>Hooks <c>Loaded</c> (the template is applied by then; it reloads with the control).</summary>
    /// <param name="d">Control.</param>
    /// <param name="e">New value.</param>
    private static void OnInWindowChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not Control control || e.NewValue is not true) return;
        control.Loaded += (_, _) => Constrain(control);
        if (control.IsLoaded) Constrain(control);
    }

    /// <summary>Sets <c>ShouldConstrainToRootBounds</c> on every closed popup in the control's visual tree.</summary>
    /// <param name="root">Control whose template popups to constrain.</param>
    private static void Constrain(DependencyObject root)
    {
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < count; i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is Popup { ShouldConstrainToRootBounds: false, IsOpen: false } popup)
            {
                try
                {
                    popup.ShouldConstrainToRootBounds = true;
                }
                catch (COMException)
                {
                    // Already opened windowed: WinUI rejects the change for the popup's lifetime.
                }
            }
            Constrain(child);
        }
    }
}
#endregion
