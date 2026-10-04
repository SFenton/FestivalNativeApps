using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI.ViewManagement;

namespace Festival.App.Controls;

#region Text-scaled uniform grids
/// <summary>
/// <c>controls:TextScaleLayout.ScaleWithText="True"</c> on an <see cref="ItemsRepeater"/> multiplies its
/// <see cref="UniformGridLayout"/>'s minimum item width and height by the Windows text size. A uniform grid gives every
/// item the first item's size, so at 150–225% text a tile whose label wraps to more lines than the first one is clipped;
/// scaling the minimums leaves room (and fewer, wider columns). Applied once when the repeater loads.
/// </summary>
public static class TextScaleLayout
{
    private static readonly ConditionalWeakTable<UniformGridLayout, object> Scaled = [];
    private static readonly Lazy<double> TextScale = new(() => new UISettings().TextScaleFactor);

    /// <summary>Windows text size factor (1–2.25), read once per launch like the layouts it scales.</summary>
    public static double Factor => TextScale.Value;

    /// <summary>Attached flag.</summary>
    public static readonly DependencyProperty ScaleWithTextProperty = DependencyProperty.RegisterAttached(
        "ScaleWithText", typeof(bool), typeof(TextScaleLayout), new PropertyMetadata(false, OnChanged));

    /// <summary>Gets the flag.</summary>
    /// <param name="element">Repeater.</param>
    /// <returns>Whether the layout scales with text.</returns>
    public static bool GetScaleWithText(DependencyObject element) => (bool)element.GetValue(ScaleWithTextProperty);

    /// <summary>Sets the flag.</summary>
    /// <param name="element">Repeater.</param>
    /// <param name="value">Whether the layout scales with text.</param>
    public static void SetScaleWithText(DependencyObject element, bool value) => element.SetValue(ScaleWithTextProperty, value);

    private static void OnChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not ItemsRepeater repeater || e.NewValue is not true) return;
        // The Layout property element is assigned after attributes are parsed, so apply once the repeater loads.
        repeater.Loaded += (_, _) => Apply(repeater);
    }

    private static void Apply(ItemsRepeater repeater)
    {
        var factor = Factor;
        if (repeater.Layout is not UniformGridLayout grid || factor <= 1 || Scaled.TryGetValue(grid, out _)) return;
        Scaled.Add(grid, true);
        grid.MinItemWidth *= factor;
        grid.MinItemHeight *= factor;
    }

    /// <summary>
    /// <c>controls:TextScaleLayout.ScaledMinWidth="72"</c>: a minimum width in epx at 100% text that grows with the Windows text
    /// size, so an Auto column sized for the longest label keeps rows aligned at 150–225% instead of clipping.
    /// </summary>
    public static readonly DependencyProperty ScaledMinWidthProperty = DependencyProperty.RegisterAttached(
        "ScaledMinWidth", typeof(double), typeof(TextScaleLayout), new PropertyMetadata(0d, OnScaledMinWidthChanged));

    /// <summary>Gets the unscaled minimum width.</summary>
    /// <param name="element">Element.</param>
    /// <returns>Minimum width at 100% text.</returns>
    public static double GetScaledMinWidth(DependencyObject element) => (double)element.GetValue(ScaledMinWidthProperty);

    /// <summary>Sets the unscaled minimum width.</summary>
    /// <param name="element">Element.</param>
    /// <param name="value">Minimum width at 100% text.</param>
    public static void SetScaledMinWidth(DependencyObject element, double value) => element.SetValue(ScaledMinWidthProperty, value);

    private static void OnScaledMinWidthChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is FrameworkElement element && e.NewValue is double width)
            element.MinWidth = Festival.Core.Domain.TextScaling.ScaledWidth(width, Factor);
    }
}
#endregion
