using System.ComponentModel;
using System.Runtime.InteropServices.WindowsRuntime;
using Festival.App.Services;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Streams;
using Windows.UI;

namespace Festival.App.Controls;

#region Paths view
/// <summary>
/// CHOpt Paths content hosted in a modal <see cref="ContentDialog"/> (focus is contained and restored by the dialog):
/// the web Instrument Selector plus difficulty/display pickers, a zoomable image, and the web's activation table
/// (column header row + one card per activation in the saved column order: fret pills, beat, time, Overdrive bar, score).
/// </summary>
public sealed partial class SongPathsView : UserControl
{
    /// <summary>Web <c>FRET_COLORS</c> (the open-note chip is a native addition); a contrast theme uses role brushes.</summary>
    private static readonly (string Name, Color Color)[] Frets =
    [
        ("green", Color.FromArgb(255, 0x2E, 0xCC, 0x71)),
        ("red", Color.FromArgb(255, 0xE7, 0x4C, 0x3C)),
        ("yellow", Color.FromArgb(255, 0xF1, 0xC4, 0x0F)),
        ("blue", Color.FromArgb(255, 0x34, 0x98, 0xDB)),
        ("orange", Color.FromArgb(255, 0xE6, 0x7E, 0x22)),
    ];

    /// <summary>Width below which the chart fills the sheet and the pickers share one bottom row.</summary>
    private const double CompactWidth = 900;

    private bool applyingZoom;
    private bool stacked;
    private Festival.Core.Data.PathImage? preparedFor;
    private BitmapImage? prepared;

    /// <summary>Creates the view for a Paths session.</summary>
    /// <param name="viewModel">Paths model.</param>
    public SongPathsView(SongPathsViewModel viewModel)
    {
        ViewModel = viewModel;
        InitializeComponent();
        InstrumentPicker.KeyboardLead = viewModel.Song.UsesKeyboardIcon;
        InstrumentPicker.Hidden = new HashSet<Instrument> { Instrument.Karaoke };
        InstrumentPicker.Instruments = viewModel.Instruments;
        SyncInstrument();
        BuildHeader();
        viewModel.PropertyChanged += OnViewModelChanged;
        viewModel.AnimateSwaps = () => Motion.Allowed;
        viewModel.PrepareImageAsync = PrepareImageAsync;
        viewModel.Announced += (_, announcement) =>
        {
            if (IsLoaded) ScreenReader.Announce(this, announcement);
        };
        ApplySwapTransitions();
        Loaded += (_, _) => ApplySwapTransitions();
    }

    /// <summary>
    /// Follows system Motion and contrast-theme changes while the dialog is open. Hosted in a <c>ContentDialog</c>, the view
    /// gets one <c>Loaded</c> and then spurious <c>Unloaded</c> events while the dialog is still shown, so subscribing on
    /// Loaded/Unloaded would leave a contrast switch unobserved (issue #223); <see cref="ShowAsync"/> owns the lifetime.
    /// </summary>
    private void Attach()
    {
        Motion.Changed += OnMotionChanged;
        ContrastTheme.Changed += OnColorsChanged;
    }

    /// <summary>Stops following system changes once the dialog has closed.</summary>
    private void Detach()
    {
        Motion.Changed -= OnMotionChanged;
        ContrastTheme.Changed -= OnColorsChanged;
    }

    /// <summary>Paths model.</summary>
    public SongPathsViewModel ViewModel { get; }

    #region Presentation
    /// <summary>
    /// Opens Paths as a modal dialog. The first opening per app session while Karaoke is visible first shows the web's
    /// "Some Instruments Unavailable" alert as its own native dialog (OK, or "Don't show again" to persist the choice).
    /// </summary>
    /// <param name="xamlRoot">Window root.</param>
    /// <param name="paths">Paths session.</param>
    /// <param name="title">Dialog title.</param>
    /// <returns>Completes when the dialog closes (reads are cancelled).</returns>
    public static async Task ShowAsync(XamlRoot xamlRoot, SongPathsViewModel paths, string title)
    {
        if (paths.ShowWarning)
        {
            var notice = FestivalDialog.Create(
                xamlRoot,
                "Some Instruments Unavailable",
                "Karaoke is not available for path visualization yet.",
                "fst.paths.warning",
                closeText: "",
                primaryText: "OK",
                secondaryText: "Don't Show Again",
                defaultButton: ContentDialogButton.Primary);
            paths.DismissWarning(await FestivalDialog.ShowAsync(notice) == ContentDialogResult.Secondary);
        }
        // Near full-window at compact sizes (the chart fills the sheet); never wider than the window. The content gets
        // the width explicitly: a dialog sizes to its content, and the layout picks its selectors from that width.
        var dialogWidth = Math.Max(320, Math.Min(1200, xamlRoot.Size.Width - 24));
        var view = new SongPathsView(paths) { Width = dialogWidth - 48 };
        var dialog = FestivalDialog.Create(xamlRoot, title, view, "fst.paths");
        dialog.FullSizeDesired = true;
        dialog.Resources["ContentDialogMaxWidth"] = dialogWidth;
        dialog.Resources["ContentDialogMinWidth"] = Math.Min(548, dialogWidth);
        dialog.Resources["ContentDialogMaxHeight"] = Math.Max(400, xamlRoot.Size.Height - 48);
        view.Attach();
        try
        {
            _ = paths.LoadAsync();
            await FestivalDialog.ShowAsync(dialog);
        }
        finally
        {
            view.Detach();
            paths.Close();
        }
    }
    #endregion

    #region Swap
    /// <summary>300 ms opacity fades for the chart and spinner (web <c>FADE_MS</c>); none without motion.</summary>
    private void ApplySwapTransitions()
    {
        var allowed = Motion.Allowed;
        ChartContent.OpacityTransition = allowed ? new ScalarTransition { Duration = PathSwapTiming.Fade } : null;
        PathSpinner.OpacityTransition = allowed ? new ScalarTransition { Duration = PathSwapTiming.Fade } : null;
    }

    /// <summary>Follows a Reduce Motion / animation-setting change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnMotionChanged(object? sender, EventArgs e) => DispatcherQueue.TryEnqueue(ApplySwapTransitions);

    /// <summary>Rebuilds the code-built table so a contrast theme switched on or off re-resolves its role brushes.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(RebuildTable);

    /// <summary>Decodes a loaded image while the spinner is up so the new chart is ready when it fades in.</summary>
    /// <param name="picture">Loaded PNG.</param>
    /// <param name="token">Cancelled by a newer selection.</param>
    /// <returns>Completes when decoded (or undecodable: the view decodes again on presentation).</returns>
    private async Task PrepareImageAsync(Festival.Core.Data.PathImage picture, CancellationToken token)
    {
        try
        {
            var bitmap = await DecodeAsync(picture);
            token.ThrowIfCancellationRequested();
            (preparedFor, prepared) = (picture, bitmap);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            (preparedFor, prepared) = (null, null);
        }
    }

    /// <summary>Decodes a PNG to a bounded bitmap.</summary>
    /// <param name="picture">PNG.</param>
    /// <returns>Bitmap.</returns>
    private static async Task<BitmapImage> DecodeAsync(Festival.Core.Data.PathImage picture)
    {
        var bitmap = new BitmapImage { DecodePixelWidth = Math.Min(picture.Width, 4096), DecodePixelType = DecodePixelType.Physical };
        using var stream = new InMemoryRandomAccessStream();
        await stream.WriteAsync(picture.Bytes.AsBuffer());
        stream.Seek(0);
        await bitmap.SetSourceAsync(stream);
        return bitmap;
    }
    #endregion

    #region Selectors
    /// <summary>Shows a new image, applies zoom changes and mirrors the selected instrument.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private async void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(SongPathsViewModel.Image) when ViewModel.Image is { } picture:
                // Prepared during the spinner: assign synchronously so the old chart never shows under the new one.
                var bitmap = ReferenceEquals(picture, preparedFor) && prepared is not null ? prepared : await DecodeAsync(picture);
                (preparedFor, prepared) = (null, null);
                if (!ReferenceEquals(picture, ViewModel.Image)) return;
                PathImage.Source = bitmap;
                FitImage();
                break;
            case nameof(SongPathsViewModel.Zoom) when !applyingZoom:
                ImageScroller.ChangeView(null, null, (float)ViewModel.Zoom);
                break;
            case nameof(SongPathsViewModel.Instrument):
                SyncInstrument();
                break;
        }
    }

    /// <summary>Shows the current instrument in the wide Instrument Selector (the compact ComboBox binds the index).</summary>
    private void SyncInstrument() => InstrumentPicker.Selected = ViewModel.Instrument;

    /// <summary>A wide Instrument Selector pick (required: it never clears).</summary>
    /// <param name="sender">Selector.</param>
    /// <param name="instrument">Picked chart.</param>
    private void OnInstrumentPicked(object? sender, Instrument? instrument)
    {
        if (instrument is { } picked) ViewModel.SelectInstrument(picked);
    }

    /// <summary>Switches between the wide selector panel and the compact bottom row.</summary>
    /// <param name="sender">Root grid.</param>
    /// <param name="e">Size change.</param>
    private void OnRootSizeChanged(object sender, SizeChangedEventArgs e)
    {
        var compact = e.NewSize.Width < CompactWidth;
        Selectors.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        CompactSelectors.Visibility = compact ? Visibility.Visible : Visibility.Collapsed;
    }
    #endregion

    #region Image
    /// <summary>Fits the centred image to the viewport width (never upscaling past its pixel width).</summary>
    private void FitImage()
    {
        if (ViewModel.Image is not { } picture) return;
        PathImage.Width = SongPathsViewModel.FitImageWidth(ImageScroller.ViewportWidth is > 0 and var viewport ? viewport : ImageScroller.ActualWidth,
            picture.Width, XamlRoot?.RasterizationScale ?? 1);
    }

    /// <summary>Refits on resize.</summary>
    /// <param name="sender">Scroller.</param>
    /// <param name="e">Size change.</param>
    private void OnImageScrollerSizeChanged(object sender, SizeChangedEventArgs e) => FitImage();

    /// <summary>Mirrors pinch / Ctrl+wheel zoom into the model.</summary>
    /// <param name="sender">Scroller.</param>
    /// <param name="e">View change.</param>
    private void OnImageViewChanged(object? sender, ScrollViewerViewChangedEventArgs e)
    {
        if (e.IsIntermediate) return;
        applyingZoom = true;
        ViewModel.Zoom = Math.Clamp(ImageScroller.ZoomFactor, SongPathsViewModel.MinZoom, SongPathsViewModel.MaxZoom);
        applyingZoom = false;
    }

    /// <summary>Zoom in one step.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnZoomIn(object sender, RoutedEventArgs e) => ViewModel.ZoomInCommand.Execute(null);

    /// <summary>Zoom out one step.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnZoomOut(object sender, RoutedEventArgs e) => ViewModel.ZoomOutCommand.Execute(null);
    #endregion

    #region Table
    /// <summary>Web <c>COLUMN_WIDTHS</c> (note minmax(190, 1fr), beat 80, time 110, Overdrive 1fr, score 100), text columns scaled by text size.</summary>
    /// <param name="key">Column.</param>
    /// <returns>Column definition.</returns>
    private static ColumnDefinition Column(PathColumnKey key) => key switch
    {
        PathColumnKey.Note => new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = PathTableLayout.NoteMinWidth },
        PathColumnKey.Od => new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) },
        _ => new ColumnDefinition { Width = new GridLength(PathTableLayout.Width(key, TextScaleLayout.Factor) ?? 0) },
    };

    /// <summary>Uppercase muted column caption (web <c>paths.col*</c> header cells and mobile labels).</summary>
    /// <param name="key">Column.</param>
    /// <returns>Caption.</returns>
    private static TextBlock Caption(PathColumnKey key) => new()
    {
        Text = key switch
        {
            PathColumnKey.Note => "ACTIVATION",
            PathColumnKey.Od => "OVERDRIVE %",
            _ => key.Label().ToUpperInvariant(),
        },
        FontSize = 11,
        FontWeight = FontWeights.SemiBold,
        CharacterSpacing = 50,
        Foreground = ContrastTheme.Brush("FSTPathCaptionBrush"),
    };

    /// <summary>Builds the column header row in the saved order (hidden while cards stack).</summary>
    private void BuildHeader()
    {
        TableHeader.Children.Clear();
        TableHeader.ColumnDefinitions.Clear();
        var columns = ViewModel.Columns;
        for (var i = 0; i < columns.Count; i++)
        {
            TableHeader.ColumnDefinitions.Add(Column(columns[i]));
            var caption = Caption(columns[i]);
            caption.HorizontalAlignment = HorizontalAlignment.Center;
            Grid.SetColumn(caption, i);
            TableHeader.Children.Add(caption);
        }
        TableHeader.Visibility = stacked ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>Switches between the grid rows and stacked cards when the table crosses the breakpoint.</summary>
    /// <param name="sender">Table grid.</param>
    /// <param name="e">Size change.</param>
    private void OnTableSizeChanged(object sender, SizeChangedEventArgs e)
    {
        var next = PathTableLayout.Stacks(e.NewSize.Width, TextScaleLayout.Factor);
        if (next == stacked) return;
        stacked = next;
        RebuildTable();
    }

    /// <summary>Rebuilds the header and re-prepares every realized card (layout or theme change).</summary>
    private void RebuildTable()
    {
        BuildHeader();
        Activations.ItemsSource = null;
        Activations.ItemsSource = ViewModel.Rows;
    }

    /// <summary>Fills one activation card in the saved column order (or stacked on narrow sheets).</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Prepared element.</param>
    private void OnActivationPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (args.Element is not Border card || sender.ItemsSourceView?.GetAt(args.Index) is not PathActivationRow row) return;
        AutomationProperties.SetAutomationId(card, $"fst.paths.activation.{row.Number}");
        AutomationProperties.SetName(card, row.AccessibleName);
        card.Child = stacked ? StackedCard(row) : GridCard(row, ViewModel.Columns);
    }

    /// <summary>Desktop row: one grid cell per column.</summary>
    /// <param name="row">Activation.</param>
    /// <param name="columns">Saved order.</param>
    /// <returns>Row content.</returns>
    private static Grid GridCard(PathActivationRow row, IReadOnlyList<PathColumnKey> columns)
    {
        var grid = new Grid { ColumnSpacing = 10, MinHeight = 28 };
        for (var i = 0; i < columns.Count; i++)
        {
            grid.ColumnDefinitions.Add(Column(columns[i]));
            var cell = Value(columns[i], row);
            cell.HorizontalAlignment = columns[i] == PathColumnKey.Od ? HorizontalAlignment.Stretch : HorizontalAlignment.Center;
            cell.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(cell, i);
            grid.Children.Add(cell);
        }
        return grid;
    }

    /// <summary>Web mobile row: note pills, then beat/time/score, then the Overdrive bar, each under a caption.</summary>
    /// <param name="row">Activation.</param>
    /// <returns>Row content.</returns>
    private static StackPanel StackedCard(PathActivationRow row)
    {
        var panel = new StackPanel { Spacing = 12 };
        panel.Children.Add(Labeled(PathColumnKey.Note, row));
        var numbers = new Grid { ColumnSpacing = 8 };
        PathColumnKey[] middle = [PathColumnKey.Beat, PathColumnKey.Time, PathColumnKey.Score];
        for (var i = 0; i < middle.Length; i++)
        {
            numbers.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var cell = Labeled(middle[i], row);
            Grid.SetColumn(cell, i);
            numbers.Children.Add(cell);
        }
        panel.Children.Add(numbers);
        panel.Children.Add(Labeled(PathColumnKey.Od, row));
        return panel;
    }

    /// <summary>A caption above a value (stacked cards).</summary>
    /// <param name="key">Column.</param>
    /// <param name="row">Activation.</param>
    /// <returns>Cell.</returns>
    private static StackPanel Labeled(PathColumnKey key, PathActivationRow row)
    {
        var cell = new StackPanel { Spacing = 4 };
        cell.Children.Add(Caption(key));
        var value = Value(key, row);
        value.HorizontalAlignment = key == PathColumnKey.Od ? HorizontalAlignment.Stretch : HorizontalAlignment.Left;
        cell.Children.Add(value);
        return cell;
    }

    /// <summary>One value: fret pills, beat, time, Overdrive bar or score; unknown values show a muted em dash.</summary>
    /// <param name="key">Column.</param>
    /// <param name="row">Activation.</param>
    /// <returns>Value element.</returns>
    private static FrameworkElement Value(PathColumnKey key, PathActivationRow row)
    {
        switch (key)
        {
            case PathColumnKey.Note:
                var frets = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2 };
                var contrast = ContrastTheme.IsOn;
                foreach (var (name, color) in Frets)
                {
                    var on = row.HasFret(name);
                    frets.Children.Add(new Border
                    {
                        Width = 22, Height = 22, CornerRadius = new CornerRadius(4), BorderThickness = new Thickness(2),
                        BorderBrush = ContrastTheme.Brush(on ? "FSTPathFretOnStrokeBrush" : "FSTPathFretOffStrokeBrush"),
                        Background = !on ? ContrastTheme.Brush("FSTPathFretOffBrush")
                            : contrast ? ContrastTheme.Brush("FSTPathFretOnBrush") : new SolidColorBrush(color),
                    });
                }
                if (row.HasFret("open"))
                    frets.Children.Add(new TextBlock { Text = "Open", FontSize = 11, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 0, 0) });
                return frets;
            case PathColumnKey.Beat:
                return Text(row.BeatText);
            case PathColumnKey.Time:
                return Text(row.TimeText);
            case PathColumnKey.Od when row.OdFill is { } fill:
                var bar = new Grid { ColumnSpacing = 8 };
                bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = PathTableLayout.OdBarMinWidth });
                bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto, MinWidth = PathTableLayout.OdLabelMinWidth(TextScaleLayout.Factor) });
                var track = new Grid { Height = 8, CornerRadius = new CornerRadius(4), Background = ContrastTheme.Brush("FSTPathOdTrackBrush"), VerticalAlignment = VerticalAlignment.Center };
                track.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(fill, GridUnitType.Star) });
                track.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100 - fill, GridUnitType.Star) });
                track.Children.Add(new Border { Background = ContrastTheme.Brush("FSTPathOdFillBrush"), CornerRadius = new CornerRadius(4) });
                bar.Children.Add(track);
                var label = Text(row.OdText);
                label.TextAlignment = TextAlignment.Right;
                Grid.SetColumn(label, 1);
                bar.Children.Add(label);
                return bar;
            case PathColumnKey.Od:
                return Text(row.OdText, missing: true);
            default:
                return Text(row.ScoreText, missing: row.ScoreBeforeActivation is null);
        }
    }

    /// <summary>Semibold 14 epx value text (muted for an unknown value).</summary>
    /// <param name="text">Text.</param>
    /// <param name="missing">Whether it is the em-dash placeholder.</param>
    /// <returns>Text block.</returns>
    private static TextBlock Text(string text, bool missing = false)
    {
        var block = new TextBlock { Text = text, FontSize = 14, FontWeight = FontWeights.SemiBold };
        if (missing) block.Foreground = ContrastTheme.Brush("FSTPathCaptionBrush");
        return block;
    }
    #endregion
}
#endregion
