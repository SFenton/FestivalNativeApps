using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Applied button state
/// <summary>
/// Marks a page's Sort/Filter <see cref="DropDownButton"/> while a non-default choice is applied: gold text by default,
/// the system Highlight / HighlightText pair under a contrast theme (gold resolves to WindowText there, which would make
/// the applied state invisible), and an optional UI Automation item status so Narrator hears what the tint shows.
/// Shared by the Songs and Item Shop Filter buttons so both look and announce the same.
/// </summary>
public static class AppliedButtonState
{
    /// <summary>Applies or clears the applied marking. Call again after a contrast-theme change (inline brushes don't follow it).</summary>
    /// <param name="button">Sort or Filter button whose content is a panel (icon + label).</param>
    /// <param name="applied">Whether a non-default choice is applied.</param>
    /// <param name="status">UIA <c>ItemStatus</c> to report (e.g. "Filters applied", empty when off); <see langword="null"/> leaves it unchanged.</param>
    public static void Apply(ContentControl button, bool applied, string? status = null)
    {
        if (status is not null) AutomationProperties.SetItemStatus(button, status);
        button.ClearValue(Control.ForegroundProperty);
        button.ClearValue(Control.BackgroundProperty);
        var highlighted = applied && ContrastTheme.IsOn;
        // Only while the Highlight pair is drawn: WinUI's automatic text backplate would otherwise paint Window-coloured
        // boxes inside the Highlight fill.
        if (button.Content is Panel content)
        {
            foreach (var child in content.Children)
                child.HighContrastAdjustment = highlighted ? ElementHighContrastAdjustment.None : ElementHighContrastAdjustment.Application;
        }
        if (FindNamed(button, "ChevronIcon") is IconElement chevron)
        {
            chevron.ClearValue(IconElement.ForegroundProperty);
            if (highlighted) chevron.Foreground = ContrastTheme.Brush("SystemColorHighlightTextColorBrush");
        }
        if (!applied) return;
        if (highlighted)
        {
            button.Background = ContrastTheme.Brush("SystemColorHighlightColorBrush");
            button.Foreground = ContrastTheme.Brush("SystemColorHighlightTextColorBrush");
        }
        else
        {
            button.Foreground = ContrastTheme.Brush("FSTEmphasisBrush");
        }
    }

    /// <summary>Finds a named template part (e.g. the DropDownButton <c>ChevronIcon</c>) below an element.</summary>
    /// <param name="root">Element whose visual tree is searched.</param>
    /// <param name="name">Template part name.</param>
    /// <returns>The part, or <see langword="null"/> before the template applies.</returns>
    private static FrameworkElement? FindNamed(DependencyObject root, string name)
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is FrameworkElement { Name: var childName } element && childName == name) return element;
            if (FindNamed(child, name) is { } found) return found;
        }
        return null;
    }
}
#endregion
