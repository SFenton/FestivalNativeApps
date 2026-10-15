using Festival.App.Services;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Song band preview row
/// <summary>
/// One band row in a Song Detail band preview (<see cref="SongBandPreviewRow"/>): members with instrument icons, rank and
/// the team score footer. Activation navigates to <see cref="SongBandPreviewRow.Route"/>: the selected band appended after
/// the top rows jumps to the full band leaderboard's page containing its rank and reveals that row (pattern
/// <c>leaderboard-row</c> R7, issue #307, the same rule as the solo spotlight row); every other row, including the selected
/// band ranked in the top rows, opens Band Detail. The selected player's band uses the purple player-row surface.
/// In the preview's one card (<see cref="GroupedRows"/> in-card slices, issue #643) the row drops its own surface.
/// </summary>
public sealed partial class SongBandPreviewRowView : UserControl, IGroupedRow
{
    /// <summary>The row's slice of the preview card, or <see langword="null"/> for a standalone row card.</summary>
    private GroupedRowSlice? slice;

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

    /// <summary>
    /// The row's slice of the preview's one card (issue #643), or <see langword="null"/> for a standalone row card. An
    /// in-card slice drops the row's own surface so the card's shows through and draws the hairline above the row; the
    /// focus ring draws inside the row's bounds, because the next row touches it.
    /// </summary>
    public GroupedRowSlice? Slice
    {
        set
        {
            if (slice == value) return;
            slice = value;
            var radius = value is { } s ? GroupedRows.Radius(s) : new CornerRadius(GroupedRowSlice.CornerRadius);
            Surface.CornerRadius = RowButton.CornerRadius = radius;
            Surface.BorderThickness = value is { } t ? GroupedRows.Outline(t) : new Thickness(GroupedRowSlice.Stroke);
            Separator.Visibility = value is { ShowSeparator: true } ? Visibility.Visible : Visibility.Collapsed;
            if (value is null) RowButton.ClearValue(FocusVisualMarginProperty);
            else RowButton.FocusVisualMargin = new Thickness(0);
            ApplySurface();
        }
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
        // In the preview card (in-card slice) only the selected band adds a fill (surface-materials R6).
        Surface.Background = selected ? ContrastTheme.Brush("FSTPlayerRowBrush")
            : slice is { InCard: true } ? null : ContrastTheme.Brush("FSTCardSurfaceBrush");
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
        // The FC badge has no fill, so on the selected row under a contrast theme its outline follows the HighlightText
        // text instead of disappearing into the Highlight fill (as LeaderboardEntryRow's badge).
        FcBadge.BorderBrush = ContrastTheme.Brush(selected && ContrastTheme.IsOn ? "FSTPlayerRowTextBrush" : "FSTEmphasisStrokeBrush");
        // The selected row's text is already the system HighlightText-on-Highlight pair under a contrast theme; without
        // this, WinUI's automatic adjustment paints Window backplate boxes inside the fill (issue #264, as LeaderboardEntryRow).
        var adjustment = Adjustment;
        RankText.HighContrastAdjustment = ScoreText.HighContrastAdjustment = FcText.HighContrastAdjustment =
            Chevron.HighContrastAdjustment = adjustment;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(MembersRepeater); i++)
            SetAdjustment(VisualTreeHelper.GetChild(MembersRepeater, i), adjustment);
    }

    /// <summary>Backplate setting for the row's text: none on the selected (Highlight) row, the app default otherwise.</summary>
    private ElementHighContrastAdjustment Adjustment =>
        Row?.IsSelected == true ? ElementHighContrastAdjustment.None : ElementHighContrastAdjustment.Application;

    /// <summary>Applies the row's backplate setting to a member line as the repeater realizes or recycles it.</summary>
    /// <param name="sender">Members repeater.</param>
    /// <param name="args">Prepared element.</param>
    private void OnMemberPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args) =>
        SetAdjustment(args.Element, Adjustment);

    /// <summary>Sets <paramref name="value"/> on an element and every descendant (the property is not inherited).</summary>
    /// <param name="element">Root element.</param>
    /// <param name="value">Adjustment.</param>
    private static void SetAdjustment(DependencyObject element, ElementHighContrastAdjustment value)
    {
        if (element is UIElement ui) ui.HighContrastAdjustment = value;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(element); i++) SetAdjustment(VisualTreeHelper.GetChild(element, i), value);
    }

    /// <summary>Navigates to the row's route: the full band board at its page for the appended selected band, else Band Detail.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnClick(object sender, RoutedEventArgs e)
    {
        if (Row is { } row) MainWindow.Instance?.Navigate(row.Route);
    }
}
#endregion
