using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Percentile XAML adapter
/// <summary>XAML adapter for the canonical percentile factory, with no independent styling.</summary>
public sealed partial class PercentilePillView : ContentControl
{
    /// <summary>Percentile label.</summary>
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(
        nameof(Text), typeof(string), typeof(PercentilePillView),
        new PropertyMetadata("", (d, _) => ((PercentilePillView)d).Render()));

    /// <summary>Creates a non-interactive metadata host.</summary>
    public PercentilePillView() => IsTabStop = false;

    /// <summary>Percentile label.</summary>
    public string Text
    {
        get => (string)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }

    /// <summary>Rebuilds the shared pill when the label changes.</summary>
    private void Render() => Content = string.IsNullOrEmpty(Text) ? null : MetadataPills.Percentile(Text);
}
#endregion
