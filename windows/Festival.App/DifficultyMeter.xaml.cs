using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace Festival.App;

#region Branded geometry
/// <summary>Native, accessible seven-bar difficulty indicator in a 62 by 20 canvas.</summary>
public sealed partial class DifficultyMeter : UserControl
{
    /// <summary>Dependency property for difficulty from one to seven.</summary>
    public static readonly DependencyProperty ValueProperty =
        DependencyProperty.Register(nameof(Value), typeof(int), typeof(DifficultyMeter),
            new PropertyMetadata(1, OnValueChanged));

    /// <summary>Creates the meter.</summary>
    public DifficultyMeter()
    {
        InitializeComponent();
        UpdateBars();
    }

    /// <summary>Gets or sets the number of active bars.</summary>
    public int Value
    {
        get => (int)GetValue(ValueProperty);
        set => SetValue(ValueProperty, value);
    }

    /// <summary>Updates foreground and accessible text for a new difficulty.</summary>
    /// <param name="dependencyObject">Meter whose value changed.</param>
    /// <param name="args">Dependency property change details.</param>
    private static void OnValueChanged(DependencyObject dependencyObject, DependencyPropertyChangedEventArgs args) =>
        ((DifficultyMeter)dependencyObject).UpdateBars();

    /// <summary>Applies the semantic accent brush and a high-contrast-safe inactive brush.</summary>
    private void UpdateBars()
    {
        var active = (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
        var inactive = (Brush)Application.Current.Resources["TextFillColorDisabledBrush"];
        for (var index = 0; index < Bars.Children.Count; index++)
            ((Rectangle)Bars.Children[index]).Fill = index < Value ? active : inactive;
        AutomationProperties.SetName(this, $"Difficulty {Value} of 7");
    }
#endregion
}
