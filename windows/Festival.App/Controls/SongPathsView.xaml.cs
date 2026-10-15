using System.ComponentModel;
using System.Runtime.InteropServices.WindowsRuntime;
using Festival.App.Services;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
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
    private readonly Windows.UI.ViewManagement.UISettings scrollBarSettings = new();

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
        // The width swap collapses one selector set; its tooltips (the Instrument Selector circles') must close with it.
        CollapsedToolTip.CloseWhenCollapsed(Selectors);
        CollapsedToolTip.CloseWhenCollapsed(CompactSelectors);
        BuildHeader();
        viewModel.PropertyChanged += OnViewModelChanged;
        viewModel.AnimateSwaps = () => Motion.Allowed;
        viewModel.PrepareImageAsync = PrepareImageAsync;
        viewModel.Announced += (_, announcement) =>
        {
            if (IsLoaded) ScreenReader.Announce(this, announcement);
        };
        ApplySwapTransitions();
        ApplyScrollBars();
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
        scrollBarSettings.AutoHideScrollBarsChanged += OnAutoHideScrollBarsChanged;
    }

    /// <summary>Stops following system changes once the dialog has closed.</summary>
    private void Detach()
    {
        Motion.Changed -= OnMotionChanged;
        ContrastTheme.Changed -= OnColorsChanged;
        scrollBarSettings.AutoHideScrollBarsChanged -= OnAutoHideScrollBarsChanged;
    }

    /// <summary>
    /// Hides the chart's scroll bars, scroll modes and zoom unchanged, unless Windows always shows scroll bars
    /// (<see cref="SongPathsViewModel.ShowChartScrollBars"/>; issues #87, #279).
    /// </summary>
    private void ApplyScrollBars()
    {
        var visibility = SongPathsViewModel.ShowChartScrollBars(scrollBarSettings.AutoHideScrollBars)
            ? ScrollBarVisibility.Auto
            : ScrollBarVisibility.Hidden;
        ImageScroller.HorizontalScrollBarVisibility = visibility;
        ImageScroller.VerticalScrollBarVisibility = visibility;
    }

    /// <summary>Re-applies the chart's scroll bars when "Always show scrollbars" changes (raised off the UI thread).</summary>
    private void OnAutoHideScrollBarsChanged(Windows.UI.ViewManagement.UISettings sender, Windows.UI.ViewManagement.UISettingsAutoHideScrollBarsChangedEventArgs args) =>
        DispatcherQueue.TryEnqueue(ApplyScrollBars);

    /// <summary>Paths model.</summary>
    public SongPathsViewModel ViewModel { get; }

    #region Presentation
    /// <summary>
    /// Opens Paths as a modal dialog. The first opening per app session while Karaoke is visible shows the web's
    /// "Some Instruments Unavailable" alert as an inline InfoBar above the chart once the first read settles (issue #649;
    /// before, a separate dialog showed it ahead of the content).
    /// </summary>
    /// <param name="xamlRoot">Window root.</param>
    /// <param name="paths">Paths session.</param>
    /// <param name="title">Dialog title.</param>
    /// <returns>Completes when the dialog closes (reads are cancelled).</returns>
    public static async Task ShowAsync(XamlRoot xamlRoot, SongPathsViewModel paths, string title)
    {
        // Near full-window at compact sizes (the chart fills the sheet); never wider than the window. The content gets
        // the width explicitly: a dialog sizes to its content, and the layout picks its selectors from that width. The
        // content box is the dialog less its padding and border; a view wider than it is clipped on the right (#269).
        // Both follow the window while the dialog is open, so a resize crosses the selector breakpoint (#571).
        var bounds = DialogBoundsFor(xamlRoot.Size);
        var view = new SongPathsView(paths) { Width = bounds.MaxWidth - DialogChromeWidth() };
        var dialog = FestivalDialog.Create(xamlRoot, title, view, "fst.paths");
        dialog.FullSizeDesired = true;
        bounds.ApplyTo(dialog);
        DialogChrome.FollowWindow(dialog, window =>
        {
            bounds = DialogBoundsFor(window);
            view.Width = bounds.MaxWidth - DialogChromeWidth(dialog.BorderThickness);
            return bounds;
        });
        // A live contrast-theme switch re-resolves the dialog border (1 epx, 2 epx under a contrast theme); refit the
        // content so its right edge (the display selector's border) is not clipped (issue #515).
        var refit = dialog.RegisterPropertyChangedCallback(
            Control.BorderThicknessProperty, (_, _) => view.Width = bounds.MaxWidth - DialogChromeWidth(dialog.BorderThickness));
        view.Attach();
        try
        {
            _ = paths.LoadAsync();
            await FestivalDialog.ShowAsync(dialog);
        }
        finally
        {
            dialog.UnregisterPropertyChangedCallback(Control.BorderThicknessProperty, refit);
            view.Detach();
            paths.Close();
        }
    }

    /// <summary>The Paths dialog's bounds for a window size: <c>max(320, min(1200, window − 24))</c> wide (at least 548
    /// where it fits) and at most the window less 48 tall (never under 400).</summary>
    /// <param name="window">Window (XamlRoot) size in epx.</param>
    /// <returns>Surface bounds.</returns>
    private static DialogBounds DialogBoundsFor(Windows.Foundation.Size window)
    {
        var width = Math.Max(320, Math.Min(1200, window.Width - 24));
        return new DialogBounds(width, Math.Min(548, width), Math.Max(400, window.Height - 48));
    }

    /// <summary>The ContentDialog's horizontal chrome: its theme padding plus border, both sides (24 + 1 each by default).</summary>
    /// <param name="border">The dialog's resolved border, once styled; the theme resource before that.</param>
    /// <returns>The width, in epx, the dialog takes from its content box.</returns>
    private static double DialogChromeWidth(Thickness? border = null)
    {
        static Thickness Lookup(string key, double fallback) =>
            Application.Current.Resources.TryGetValue(key, out var value) && value is Thickness thickness ? thickness : new Thickness(fallback);
        var padding = Lookup("ContentDialogPadding", 24);
        var edge = border ?? Lookup("ContentDialogBorderWidth", 1);
        return padding.Left + padding.Right + edge.Left + edge.Right;
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

    /// <summary>Closes the Karaoke notice for this opening; focus moves to the chart region's first stop.</summary>
    /// <param name="sender">OK button.</param>
    /// <param name="e">Unused.</param>
    private void OnNoticeOk(object sender, RoutedEventArgs e) => DismissNotice(permanently: false);

    /// <summary>Closes the Karaoke notice and keeps it closed ("Don't show again").</summary>
    /// <param name="sender">Don't Show Again button.</param>
    /// <param name="e">Unused.</param>
    private void OnNoticeNeverAgain(object sender, RoutedEventArgs e) => DismissNotice(permanently: true);

    /// <summary>Dismisses the notice, handing keyboard focus on to the next stop rather than letting it fall out of the sheet.</summary>
    /// <param name="permanently">Persist "Don't show again".</param>
    private void DismissNotice(bool permanently)
    {
        var hadFocus = CollapsedToolTip.HasFocusWithin(PathNotice);
        ViewModel.DismissWarning(permanently);
        if (hadFocus && FocusManager.FindFirstFocusableElement(ChartArea) is Control next) next.Focus(FocusState.Programmatic);
    }

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
        // Focus on a picker follows the swap to its counterpart (programmatically, so it opens no keyboard tooltip)
        // instead of falling to the chart (#571).
        var replacement = compact ? WideToCompact() : CompactToWide();
        Selectors.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        CompactSelectors.Visibility = compact ? Visibility.Visible : Visibility.Collapsed;
        if (replacement is not null) CollapsedToolTip.HandFocusWith(this, replacement);
    }

    /// <summary>The compact picker that replaces the focused wide one, if focus is in the wide selectors.</summary>
    /// <returns>Focuses the replacement, or <see langword="null"/>.</returns>
    private Func<bool>? WideToCompact()
    {
        if (CollapsedToolTip.HasFocusWithin(InstrumentPicker)) return () => Programmatic(CompactInstrumentPicker);
        if (CollapsedToolTip.HasFocusWithin(DifficultyPicker)) return () => Programmatic(CompactDifficultyPicker);
        if (CollapsedToolTip.HasFocusWithin(DisplayPicker)) return () => Programmatic(CompactDisplayPicker);
        return null;
    }

    /// <summary>The wide picker that replaces the focused compact one, if focus is in the compact selectors.</summary>
    /// <returns>Focuses the replacement, or <see langword="null"/>.</returns>
    private Func<bool>? CompactToWide()
    {
        if (CollapsedToolTip.HasFocusWithin(CompactInstrumentPicker)) return InstrumentPicker.FocusCurrent;
        if (CollapsedToolTip.HasFocusWithin(CompactDifficultyPicker)) return () => Programmatic(SelectedOption(DifficultyPicker));
        if (CollapsedToolTip.HasFocusWithin(CompactDisplayPicker)) return () => Programmatic(SelectedOption(DisplayPicker));
        return null;
    }

    /// <summary>Focuses a replacement picker programmatically.</summary>
    /// <param name="target">Picker, or <see langword="null"/> before it is realized.</param>
    /// <returns>Whether it took focus.</returns>
    private static bool Programmatic(Control? target) => target?.Focus(FocusState.Programmatic) == true;

    /// <summary>The checked option of a wide picker (its focus stop), once realized.</summary>
    /// <param name="picker">Difficulty or display picker.</param>
    /// <returns>Radio button, or <see langword="null"/> before layout.</returns>
    private static Control? SelectedOption(RadioButtons picker) => picker.ContainerFromIndex(Math.Max(picker.SelectedIndex, 0)) as Control;

    /// <summary>Compact box widths: labelled for their longest options (instrument, difficulty, display) and icon-only
    /// (instrument, display); measured once per sheet.</summary>
    private (double Instrument, double Difficulty, double Display, double IconInstrument, double IconDisplay)? compactWidths;

    /// <summary>Current compact arrangement (labelled one line until the first measure).</summary>
    private PathSelectorArrangement compactArrangement = PathSelectorArrangement.Labelled;

    /// <summary>
    /// Sizes each compact ComboBox for its longest option and picks the row's arrangement: labelled on one line, else the
    /// instrument and display boxes icon-only with difficulty filling the rest (owner-approved, issue #612: "just show
    /// instrument icon and image/text icon in dropdowns like web"), else difficulty and display reflowed under a labelled
    /// instrument box (issue #280: "Pro Drums + Cymbals" and 200% text were clipped, and the instrument box changed width
    /// with the selection).
    /// </summary>
    /// <param name="sender">Compact selector grid.</param>
    /// <param name="e">Size change.</param>
    private void OnCompactSelectorsSizeChanged(object sender, SizeChangedEventArgs e)
    {
        var widths = compactWidths ??= MeasureCompactWidths();
        CompactDifficultyPicker.MinWidth = widths.Difficulty;
        var next = PathSelectorLayout.Plan(e.NewSize.Width, widths.Instrument, widths.Difficulty, widths.Display,
            widths.IconInstrument, widths.IconDisplay, CompactSelectors.ColumnSpacing);
        var iconOnly = next == PathSelectorArrangement.IconOnly;
        CompactDisplayPicker.Width = iconOnly ? widths.IconDisplay : widths.Display;
        // Stacked, the instrument box spans the row (its trimmed label is the last resort on the narrowest windows).
        CompactInstrumentPicker.Width = next switch
        {
            PathSelectorArrangement.Stacked => double.NaN,
            PathSelectorArrangement.IconOnly => widths.IconInstrument,
            _ => widths.Instrument,
        };
        if (next == compactArrangement) return;
        compactArrangement = next;
        ApplyCompactArrangement();
    }

    /// <summary>Places the compact boxes on one line, or the instrument above difficulty and display, and switches the
    /// instrument and display faces between icon + name and icon only.</summary>
    private void ApplyCompactArrangement()
    {
        var stacked = compactArrangement == PathSelectorArrangement.Stacked;
        Grid.SetColumnSpan(CompactInstrumentPicker, stacked ? 3 : 1);
        Grid.SetRow(CompactDifficultyPicker, stacked ? 1 : 0);
        Grid.SetColumn(CompactDifficultyPicker, stacked ? 0 : 1);
        Grid.SetColumnSpan(CompactDifficultyPicker, stacked ? 2 : 1);
        Grid.SetRow(CompactDisplayPicker, stacked ? 1 : 0);
        // An empty Auto row still adds RowSpacing, so the gap exists only while stacked.
        CompactSelectors.RowSpacing = stacked ? CompactSelectors.ColumnSpacing : 0;
        var iconOnly = compactArrangement == PathSelectorArrangement.IconOnly;
        foreach (var (box, key) in new[] { (CompactInstrumentPicker, "InstrumentTemplates"), (CompactDisplayPicker, "DisplayTemplates") })
        {
            var faces = (ComboBoxFaceTemplateSelector)Resources[key];
            faces.IconOnly = iconOnly;
            faces.Refresh(box);
        }
    }

    /// <summary>Measures every option at the current text scale (off-tree text blocks scale like FirstRunCarousel's).</summary>
    /// <returns>Box widths including the ComboBox template's padding and drop-down glyph column.</returns>
    private (double Instrument, double Difficulty, double Display, double IconInstrument, double IconDisplay) MeasureCompactWidths()
    {
        var padding = CompactDifficultyPicker.Padding;
        double Widest(IEnumerable<string> labels) => labels.Select(TextWidth).DefaultIfEmpty(0).Max();
        return (
            PathSelectorLayout.BoxWidth(Widest(ViewModel.InstrumentOptions.Select(o => o.Label)) + PathSelectorLayout.InstrumentIconSpace,
                padding.Left, padding.Right, PathSelectorLayout.InstrumentMinWidth),
            PathSelectorLayout.BoxWidth(Widest(ViewModel.DifficultyLabels), padding.Left, padding.Right, 0),
            PathSelectorLayout.BoxWidth(Widest(ViewModel.DisplayOptions.Select(o => o.Label)) + PathSelectorLayout.DisplayIconSpace,
                padding.Left, padding.Right, PathSelectorLayout.DisplayMinWidth),
            PathSelectorLayout.IconBoxWidth(PathSelectorLayout.InstrumentIconSize, padding.Left, padding.Right),
            PathSelectorLayout.IconBoxWidth(PathSelectorLayout.DisplayIconSize, padding.Left, padding.Right));
    }

    /// <summary>Desired width of an option label in the ComboBox content font.</summary>
    /// <param name="label">Option text.</param>
    /// <returns>Width in effective pixels.</returns>
    private double TextWidth(string label)
    {
        var block = new TextBlock { Text = label, FontSize = CompactDifficultyPicker.FontSize, FontFamily = CompactDifficultyPicker.FontFamily };
        block.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        return block.DesiredSize.Width;
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
        ViewModel.Zoom = SongPathsViewModel.NormalizeZoom(ImageScroller.ZoomFactor);
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
    private static TextBlock Caption(PathColumnKey key) => RawLeaf(new TextBlock
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
    });

    /// <summary>
    /// Hides a table caption or value from Narrator's control view; the card's name (<see cref="PathActivationRow.AccessibleName"/>)
    /// already speaks it, so each card stays one Narrator item. Raw is set on each leaf: a panel has no automation peer, so
    /// <c>AccessibilityView="Raw"</c> on it (the header row) leaves its text blocks exposed (issue #515).
    /// </summary>
    /// <param name="element">Caption or value.</param>
    /// <param name="automationId">Raw-view ID for layout tests, e.g. <c>fst.paths.activation.1.time</c>.</param>
    /// <returns>The element.</returns>
    private static T RawLeaf<T>(T element, string? automationId = null) where T : FrameworkElement
    {
        AutomationProperties.SetAccessibilityView(element, AccessibilityView.Raw);
        if (automationId is not null) AutomationProperties.SetAutomationId(element, automationId);
        return element;
    }

    /// <summary>Raw-view ID of one value in an activation card.</summary>
    /// <param name="row">Activation.</param>
    /// <param name="part">Value: <c>beat</c>, <c>time</c>, <c>od</c>, <c>score</c> or <c>open</c>.</param>
    /// <returns>AutomationId.</returns>
    private static string ValueId(PathActivationRow row, string part) => $"fst.paths.activation.{row.Number}.{part}";

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
                    frets.Children.Add(RawLeaf(new TextBlock { Text = "Open", FontSize = 11, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 0, 0) }, ValueId(row, "open")));
                return frets;
            case PathColumnKey.Beat:
                return Text(row.BeatText, ValueId(row, "beat"));
            case PathColumnKey.Time:
                return Text(row.TimeText, ValueId(row, "time"));
            case PathColumnKey.Od when row.OdFill is { } fill:
                var bar = new Grid { ColumnSpacing = 8 };
                bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = PathTableLayout.OdBarMinWidth });
                bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto, MinWidth = PathTableLayout.OdLabelMinWidth(TextScaleLayout.Factor) });
                var track = new Grid { Height = 8, CornerRadius = new CornerRadius(4), Background = ContrastTheme.Brush("FSTPathOdTrackBrush"), VerticalAlignment = VerticalAlignment.Center };
                track.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(fill, GridUnitType.Star) });
                track.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100 - fill, GridUnitType.Star) });
                track.Children.Add(new Border { Background = ContrastTheme.Brush("FSTPathOdFillBrush"), CornerRadius = new CornerRadius(4) });
                bar.Children.Add(track);
                var label = Text(row.OdText, ValueId(row, "od"));
                label.TextAlignment = TextAlignment.Right;
                Grid.SetColumn(label, 1);
                bar.Children.Add(label);
                return bar;
            case PathColumnKey.Od:
                return Text(row.OdText, ValueId(row, "od"), missing: true);
            default:
                return Text(row.ScoreText, ValueId(row, "score"), missing: row.ScoreBeforeActivation is null);
        }
    }

    /// <summary>Semibold 14 epx value text (muted for an unknown value), raw view only (<see cref="RawLeaf{T}"/>).</summary>
    /// <param name="text">Text.</param>
    /// <param name="automationId">Raw-view ID (<see cref="ValueId"/>).</param>
    /// <param name="missing">Whether it is the em-dash placeholder.</param>
    /// <returns>Text block.</returns>
    private static TextBlock Text(string text, string automationId, bool missing = false)
    {
        var block = RawLeaf(new TextBlock { Text = text, FontSize = 14, FontWeight = FontWeights.SemiBold }, automationId);
        if (missing) block.Foreground = ContrastTheme.Brush("FSTPathCaptionBrush");
        return block;
    }
    #endregion
}
#endregion
