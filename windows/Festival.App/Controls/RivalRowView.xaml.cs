using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Rival row view
/// <summary>Renders a <see cref="RivalRowItem"/> (hosted by a row button or list item that owns the UIA name).</summary>
public sealed partial class RivalRowView : UserControl
{
    /// <summary>Row.</summary>
    public static readonly DependencyProperty ItemProperty = DependencyProperty.Register(
        nameof(Item), typeof(RivalRowItem), typeof(RivalRowView), new PropertyMetadata(null));

    /// <summary>Creates the view.</summary>
    public RivalRowView() => InitializeComponent();

    /// <summary>Row.</summary>
    public RivalRowItem? Item
    {
        get => (RivalRowItem?)GetValue(ItemProperty);
        set => SetValue(ItemProperty, value);
    }
}
#endregion
