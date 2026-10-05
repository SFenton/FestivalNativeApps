using Festival.App.Services;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

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
        // The surface and text brushes are set from code, so a contrast-theme switch while the page is open must
        // re-resolve them (as LeaderboardEntryRow, issue #242; inline brush assignments do not follow {ThemeResource}).
        Loaded += (_, _) =>
        {
            ContrastTheme.Changed -= OnColorsChanged;
            ContrastTheme.Changed += OnColorsChanged;
            ApplySurface();
        };
        Unloaded += (_, _) => ContrastTheme.Changed -= OnColorsChanged;
    }

    /// <summary>Row model.</summary>
    public SongBandPreviewRow? Row
    {
        get => (SongBandPreviewRow?)GetValue(RowProperty);
        set => SetValue(RowProperty, value);
    }

    /// <summary>Re-applies the row's brushes on the UI thread after a system colour change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(ApplySurface);

    /// <summary>Refreshes the bindings and the selected/plain surface.</summary>
    private void OnRowChanged()
    {
        Bindings.Update();
        ApplySurface();
    }

    /// <summary>Sets the selected (purple player-row) or plain card surface and text brushes for the current theme.</summary>
    private void ApplySurface()
    {
        var selected = Row?.IsSelected == true;
        Surface.Background = ContrastTheme.Brush(selected ? "FSTPlayerRowBrush" : "FSTCardSurfaceBrush");
        Surface.BorderBrush = ContrastTheme.Brush(selected ? "FSTPlayerRowStrokeBrush" : "FSTCardStrokeBrush");
        RankText.FontWeight = selected ? FontWeights.Bold : FontWeights.SemiBold;
        // Selected-row text follows the purple fill (HighlightText under a contrast theme).
        if (selected)
        {
            var text = ContrastTheme.Brush("FSTPlayerRowTextBrush");
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
