using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Rival song row view
/// <summary>Renders a <see cref="RivalSongItem"/> in the compact (card) or full (Rivalry) layout.</summary>
public sealed partial class RivalSongRowView : UserControl
{
    /// <summary>Song row.</summary>
    public static readonly DependencyProperty ItemProperty = DependencyProperty.Register(
        nameof(Item), typeof(RivalSongItem), typeof(RivalSongRowView), new PropertyMetadata(null));

    /// <summary>Single-line layout.</summary>
    public static readonly DependencyProperty CompactProperty = DependencyProperty.Register(
        nameof(Compact), typeof(bool), typeof(RivalSongRowView), new PropertyMetadata(false, (d, _) => ((RivalSongRowView)d).UpdateLayoutMode()));

    /// <summary>Layout actually used: <see cref="Compact"/>, or forced by a narrow width.</summary>
    public static readonly DependencyProperty EffectiveCompactProperty = DependencyProperty.Register(
        nameof(EffectiveCompact), typeof(bool), typeof(RivalSongRowView), new PropertyMetadata(false));

    /// <summary>Below this width the full layout collapses to one line.</summary>
    private const double FullLayoutMinWidth = 380;

    /// <summary>Below this width art and instrument icons are hidden to keep the title readable.</summary>
    private const double DecorationMinWidth = 280;

    /// <summary>Creates the view.</summary>
    public RivalSongRowView()
    {
        InitializeComponent();
        SizeChanged += (_, _) => UpdateLayoutMode();
    }

    /// <summary>Layout actually used.</summary>
    public bool EffectiveCompact
    {
        get => (bool)GetValue(EffectiveCompactProperty);
        private set => SetValue(EffectiveCompactProperty, value);
    }

    /// <summary>Song row.</summary>
    public RivalSongItem? Item
    {
        get => (RivalSongItem?)GetValue(ItemProperty);
        set => SetValue(ItemProperty, value);
    }

    /// <summary>Single-line layout.</summary>
    public bool Compact
    {
        get => (bool)GetValue(CompactProperty);
        set => SetValue(CompactProperty, value);
    }

    /// <summary>Chooses compact/full and decoration visibility from the requested mode and current width.</summary>
    private void UpdateLayoutMode()
    {
        var width = ActualWidth;
        EffectiveCompact = Compact || (width > 0 && width < FullLayoutMinWidth);
        var decorate = width == 0 || width >= DecorationMinWidth ? Visibility.Visible : Visibility.Collapsed;
        Art.Visibility = decorate;
        Icons.Visibility = decorate;
    }
}
#endregion
