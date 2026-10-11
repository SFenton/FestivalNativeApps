using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Rival song row view
/// <summary>
/// Renders a <see cref="RivalSongItem"/> (pattern <c>rival-rows</c>): the one song comparison row of Rival Detail's cards
/// and Rivalry, in the Apple <c>RivalSongRowContent</c> design (issue #603).
/// </summary>
public sealed partial class RivalSongRowView : UserControl
{
    /// <summary>Song row.</summary>
    public static readonly DependencyProperty ItemProperty = DependencyProperty.Register(
        nameof(Item), typeof(RivalSongItem), typeof(RivalSongRowView), new PropertyMetadata(null));

    /// <summary>Below this width the art column is hidden to keep the title and pills readable.</summary>
    private const double DecorationMinWidth = 280;

    /// <summary>Creates the view.</summary>
    public RivalSongRowView()
    {
        InitializeComponent();
        SizeChanged += (_, _) => UpdateDecoration();
    }

    /// <summary>Song row.</summary>
    public RivalSongItem? Item
    {
        get => (RivalSongItem?)GetValue(ItemProperty);
        set => SetValue(ItemProperty, value);
    }

    /// <summary>Shows the art and chart column unless the row is too narrow for it.</summary>
    private void UpdateDecoration()
    {
        var width = ActualWidth;
        Leading.Visibility = width == 0 || width >= DecorationMinWidth ? Visibility.Visible : Visibility.Collapsed;
    }
}
#endregion
