using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Instrument icon row
/// <summary>
/// A combo board's decorative row of instrument icons (web <c>CompeteScopeHeader</c> / combo <c>FullRankingsPage</c>
/// title): one <see cref="InstrumentIcon"/> per file, left to right with 8 epx between them. Hidden from UI Automation; the
/// adjacent title names the combo ("Lead + Bass + Drums + Tap Vocals"). Collapsed while it has no files.
/// </summary>
public sealed partial class InstrumentIconRow : StackPanel
{
    /// <summary>
    /// Icon files in service order (an <see cref="IEnumerable{T}"/> of strings). Typed <see cref="object"/> like
    /// <c>NotificationRowVisuals.IconFiles</c> so NativeAOT boxes the view model's list without a projected collection type.
    /// </summary>
    public static readonly DependencyProperty FilesProperty = DependencyProperty.Register(
        nameof(Files), typeof(object), typeof(InstrumentIconRow), new PropertyMetadata(null, (d, _) => ((InstrumentIconRow)d).Update()));

    /// <summary>Icon edge in epx (default 36, the card header's icon size).</summary>
    public static readonly DependencyProperty IconSizeProperty = DependencyProperty.Register(
        nameof(IconSize), typeof(double), typeof(InstrumentIconRow), new PropertyMetadata(36d, (d, _) => ((InstrumentIconRow)d).Update()));

    /// <summary>Creates an empty row.</summary>
    public InstrumentIconRow()
    {
        Orientation = Orientation.Horizontal;
        Spacing = 8;
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        Update();
    }

    /// <summary>Icon files in service order.</summary>
    public object? Files
    {
        get => GetValue(FilesProperty);
        set => SetValue(FilesProperty, value);
    }

    /// <summary>Icon edge in epx.</summary>
    public double IconSize
    {
        get => (double)GetValue(IconSizeProperty);
        set => SetValue(IconSizeProperty, value);
    }

    /// <summary>Rebuilds the icons for the current files and size.</summary>
    private void Update()
    {
        Children.Clear();
        foreach (var file in Files as IEnumerable<string> ?? [])
        {
            var icon = new InstrumentIcon { File = file, Width = IconSize, Height = IconSize };
            AutomationProperties.SetAccessibilityView(icon, AccessibilityView.Raw);
            Children.Add(icon);
        }
        Visibility = Children.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }
}
#endregion
