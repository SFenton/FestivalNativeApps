using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Song band preview row
/// <summary>
/// One band row in a Song Detail band preview (<see cref="SongBandPreviewRow"/>): members with instrument icons, rank and
/// the team score footer; opens Band Detail. The selected player's band uses the purple player-row surface.
/// </summary>
public sealed partial class SongBandPreviewRowView : UserControl
{
    /// <summary>Row model.</summary>
    public static readonly DependencyProperty RowProperty = DependencyProperty.Register(
        nameof(Row), typeof(SongBandPreviewRow), typeof(SongBandPreviewRowView),
        new PropertyMetadata(null, (d, _) => ((SongBandPreviewRowView)d).OnRowChanged()));

    /// <summary>Creates the row.</summary>
    public SongBandPreviewRowView()
    {
        InitializeComponent();
        IsTabStop = false;
    }

    /// <summary>Row model.</summary>
    public SongBandPreviewRow? Row
    {
        get => (SongBandPreviewRow?)GetValue(RowProperty);
        set => SetValue(RowProperty, value);
    }

    /// <summary>Refreshes the bindings and the selected/plain surface.</summary>
    private void OnRowChanged()
    {
        Bindings.Update();
        var selected = Row?.IsSelected == true;
        var resources = Application.Current.Resources;
        Surface.Background = (Brush)resources[selected ? "FSTPlayerRowBrush" : "FSTCardSurfaceBrush"];
        Surface.BorderBrush = (Brush)resources[selected ? "FSTPlayerRowStrokeBrush" : "FSTCardStrokeBrush"];
        RankText.FontWeight = selected ? FontWeights.Bold : FontWeights.SemiBold;
        // Selected-row text follows the purple fill (HighlightText under a contrast theme).
        if (selected)
        {
            var text = (Brush)resources["FSTPlayerRowTextBrush"];
            RowButton.Foreground = RankText.Foreground = ScoreText.Foreground = Chevron.Foreground = text;
        }
        else
        {
            RowButton.ClearValue(Control.ForegroundProperty);
            RankText.ClearValue(TextBlock.ForegroundProperty);
            ScoreText.ClearValue(TextBlock.ForegroundProperty);
            Chevron.ClearValue(IconElement.ForegroundProperty);
        }
    }

    /// <summary>Opens Band Detail.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnClick(object sender, RoutedEventArgs e)
    {
        if (Row is { } row) MainWindow.Instance?.Navigate(row.Route);
    }
}
#endregion
