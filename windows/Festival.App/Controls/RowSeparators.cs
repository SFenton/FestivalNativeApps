using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Row separators
/// <summary>A row that draws a hairline above itself when it is not the first row of its card.</summary>
public interface ISeparatedRow
{
    /// <summary>Whether the top hairline shows.</summary>
    bool ShowSeparator { set; }
}

/// <summary>
/// Hairlines between the rows of a multi-row card (operator batch 6.5). <c>controls:RowSeparators.Enabled="True"</c> on an
/// <see cref="ItemsRepeater"/> shows each realized row's separator unless it is the first; ListView pages call
/// <see cref="Apply"/> from <c>ContainerContentChanging</c>. Rows opt in by implementing <see cref="ISeparatedRow"/> or by
/// naming an element <c>RowSeparator</c> in their template.
/// </summary>
public static class RowSeparators
{
    /// <summary>Attached switch for an <see cref="ItemsRepeater"/>.</summary>
    public static readonly DependencyProperty EnabledProperty = DependencyProperty.RegisterAttached(
        "Enabled", typeof(bool), typeof(RowSeparators), new PropertyMetadata(false, OnEnabledChanged));

    /// <summary>Reads the switch.</summary>
    /// <param name="element">Repeater.</param>
    /// <returns>Whether separators are managed.</returns>
    public static bool GetEnabled(DependencyObject element) => (bool)element.GetValue(EnabledProperty);

    /// <summary>Sets the switch.</summary>
    /// <param name="element">Repeater.</param>
    /// <param name="value">Whether separators are managed.</param>
    public static void SetEnabled(DependencyObject element, bool value) => element.SetValue(EnabledProperty, value);

    /// <summary>Shows or hides one row's separator for its position.</summary>
    /// <param name="row">Row element (template root or <see cref="ISeparatedRow"/>).</param>
    /// <param name="index">Row index in its card.</param>
    public static void Apply(UIElement row, int index)
    {
        var show = index > 0;
        if (row is ISeparatedRow separated) separated.ShowSeparator = show;
        else if (row is FrameworkElement element && element.FindName("RowSeparator") is UIElement line)
            line.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>Hooks a repeater's realization events.</summary>
    /// <param name="d">Repeater.</param>
    /// <param name="e">Change.</param>
    private static void OnEnabledChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not ItemsRepeater repeater) return;
        repeater.ElementPrepared -= OnPrepared;
        repeater.ElementIndexChanged -= OnIndexChanged;
        if (e.NewValue is not true) return;
        repeater.ElementPrepared += OnPrepared;
        repeater.ElementIndexChanged += OnIndexChanged;
    }

    /// <summary>Applies the separator to a realized row.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Row and index.</param>
    private static void OnPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args) => Apply(args.Element, args.Index);

    /// <summary>Re-applies when a row moves (insertions/removals above it).</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Row and new index.</param>
    private static void OnIndexChanged(ItemsRepeater sender, ItemsRepeaterElementIndexChangedEventArgs args) => Apply(args.Element, args.NewIndex);
}
#endregion
