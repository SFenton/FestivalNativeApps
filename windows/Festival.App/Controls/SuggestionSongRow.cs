using Festival.App.Services;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Festival.App.Controls;

#region Suggestion song row
/// <summary>
/// One tappable suggestion row: album art, title/subtitle and the layout-specific right-side metadata
/// (<see cref="SuggestionRowLayout"/>). Narrow rows move the metadata under the title, like the web's two-row
/// layout. Art loads while the row is in the tree and is cancelled when it leaves.
/// </summary>
public sealed partial class SuggestionSongRow : Button
{
    /// <summary>Row data.</summary>
    public static readonly DependencyProperty ItemProperty = DependencyProperty.Register(
        nameof(Item), typeof(SuggestionRowItem), typeof(SuggestionSongRow), new PropertyMetadata(null, (d, _) => ((SuggestionSongRow)d).Build()));

    private const double ArtSize = 44;
    private static readonly SolidColorBrush RivalFill = new(Color.FromArgb(0x33, 0x42, 0x85, 0xF4));
    private static readonly SolidColorBrush RivalText = new(Color.FromArgb(0xFF, 0x6E, 0xA8, 0xFF));

    // RowSpacing follows SuggestionRowMetrics: none until the metadata takes a second line (issue #654).
    private readonly Grid root = new() { ColumnSpacing = 12, RowSpacing = 0, MinHeight = 64, Padding = new Thickness(24, 10, 24, 10) };
    private readonly Image art = new() { Stretch = Stretch.UniformToFill };
    private readonly MarqueeText title = new();
    private readonly MarqueeText subtitle = new();
    private readonly StackPanel metadata = new() { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
    private readonly Border artFrame;
    private readonly FontIcon chevron;
    private CancellationTokenSource? artLoad;
    private bool narrow;
    private bool listening;
    private bool? paintedContrast;

    /// <summary>Creates the row.</summary>
    public SuggestionSongRow()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        Padding = new Thickness(0);
        CornerRadius = new CornerRadius(0);
        Background = new SolidColorBrush(Colors.Transparent);
        BorderThickness = new Thickness(0, 1, 0, 0);

        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(ArtSize) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        artFrame = new Border
        {
            Width = ArtSize, Height = ArtSize, CornerRadius = new CornerRadius(6), Child = art, VerticalAlignment = VerticalAlignment.Center,
        };
        AutomationProperties.SetAccessibilityView(art, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        var text = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center, Children = { title, subtitle } };
        Grid.SetColumn(text, 1);
        root.Children.Add(artFrame);
        root.Children.Add(text);
        root.Children.Add(metadata);
        // In-card chevron: the row opens Song Detail (batch 7.3).
        chevron = new FontIcon
        {
            Glyph = "\uE76C", FontSize = 12, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0),
        };
        AutomationProperties.SetAccessibilityView(chevron, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        Grid.SetColumn(chevron, 3);
        Grid.SetRowSpan(chevron, 2);
        root.Children.Add(chevron);
        Content = root;

        title.TextStyle = TitleStyle;
        PaintChrome();
        Click += (_, _) => { if (Item is { } item) MainWindow.Instance?.Navigate(item.Route); };
        Loaded += (_, _) =>
        {
            Listen(true);
            // A contrast-theme switch while the row was off screen (a recycled or cached row) left stale brushes.
            if (paintedContrast != Services.ContrastTheme.IsOn) ApplyColors();
            LoadArt();
        };
        // WinUI can raise a stale Unloaded after the re-parented row's next Loaded; only cancel when really gone.
        Unloaded += (_, _) =>
        {
            if (IsLoaded) return;
            Listen(false);
            CancelArt();
        };
        SizeChanged += (_, e) => ApplyWidth(e.NewSize.Width);
    }

    /// <summary>Row data.</summary>
    public SuggestionRowItem? Item
    {
        get => (SuggestionRowItem?)GetValue(ItemProperty);
        set => SetValue(ItemProperty, value);
    }

    /// <summary>Shared semibold title style for the marquee copies.</summary>
    private static Style TitleStyle
    {
        get
        {
            if (titleStyle is not null) return titleStyle;
            titleStyle = new Style(typeof(TextBlock));
            titleStyle.Setters.Add(new Setter(TextBlock.FontWeightProperty, FontWeights.SemiBold));
            return titleStyle;
        }
    }

    private static Style? titleStyle;

    /// <summary>
    /// 12 epx secondary style for the subtitle marquee copies, rebuilt when the contrast theme changes (its brush is resolved
    /// once, so a style cached across a switch would keep the old theme's colour).
    /// </summary>
    private static Style SubtitleStyle
    {
        get
        {
            var contrast = Services.ContrastTheme.IsOn;
            if (subtitleStyle is not null && subtitleStyleContrast == contrast) return subtitleStyle;
            subtitleStyle = new Style(typeof(TextBlock));
            subtitleStyle.Setters.Add(new Setter(TextBlock.FontSizeProperty, 12.0));
            subtitleStyle.Setters.Add(new Setter(TextBlock.ForegroundProperty, Role("FSTSecondaryTextBrush")));
            subtitleStyleContrast = contrast;
            return subtitleStyle;
        }
    }

    private static Style? subtitleStyle;
    private static bool subtitleStyleContrast;

    #region Contrast theme
    /// <summary>Resolves the row's own code-set brushes (separator, art placeholder, chevron, subtitle) for the current theme.</summary>
    private void PaintChrome()
    {
        BorderBrush = Role("FSTCardStrokeBrush");
        artFrame.Background = Role("FSTSurfaceMutedBrush");
        chevron.Foreground = Role("FSTSecondaryTextBrush");
        subtitle.TextStyle = SubtitleStyle;
        paintedContrast = Services.ContrastTheme.IsOn;
    }

    /// <summary>
    /// Re-resolves every brush the row set in code after a contrast-theme switch: its chrome and the metadata (the rival pill's
    /// brand or neutral role, the accuracy pill, delta text and instrument chips; issue #513). Art is not reloaded.
    /// </summary>
    private void ApplyColors()
    {
        PaintChrome();
        if (Item is { } item) BuildMetadata(item);
    }

    /// <summary>Subscribes to or unsubscribes from <see cref="Services.ContrastTheme.Changed"/> once.</summary>
    /// <param name="on">Whether to listen.</param>
    private void Listen(bool on)
    {
        if (on == listening) return;
        listening = on;
        if (on) Services.ContrastTheme.Changed += OnColorsChanged;
        else Services.ContrastTheme.Changed -= OnColorsChanged;
    }

    /// <summary>Re-applies the row's brushes on the UI thread after a system colour change (raised off the UI thread).</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(ApplyColors);
    #endregion

    #region Build
    /// <summary>Rebuilds text and metadata for the current item.</summary>
    private void Build()
    {
        CancelArt();
        art.Source = null;
        metadata.Children.Clear();
        if (Item is not { } item) return;
        var p = item.Presentation;
        title.Text = p.Title;
        subtitle.Text = p.Subtitle;
        AutomationProperties.SetName(this, p.AccessibleName);
        BorderThickness = new Thickness(0, item.IsFirst ? 0 : 1, 0, 0);
        AutomationProperties.SetAutomationId(this, item.AutomationId);
        // Raw-view test ID for the vertical-centre check (issue #654); Narrator still reads the row once.
        AutomationProperties.SetAutomationId(art, PillId(item, "art"));
        BuildMetadata(item);
        if (IsLoaded) LoadArt();
    }

    /// <summary>Builds the layout-specific metadata for the current theme.</summary>
    /// <param name="item">Row.</param>
    private void BuildMetadata(SuggestionRowItem item)
    {
        metadata.Children.Clear();
        var p = item.Presentation;
        switch (p.Layout)
        {
            case SuggestionRowLayout.Rival:
                // Contrast theme: the rival name is a plain pill (ButtonFace / ButtonText with an outline), not brand blue.
                if (p.RivalName is { } rival)
                    metadata.Children.Add(Services.ContrastTheme.IsOn
                        ? NeutralPill(rival, PillId(item, "rival"))
                        : Pill(rival, RivalFill, null, RivalText, PillId(item, "rival")));
                // Rivals' win/lose text roles: the web's #C62828 measured 3.0:1 on the card (issue #259); contrast themes use WindowText.
                if (p.RivalDeltaText is { } delta)
                    metadata.Children.Add(new TextBlock
                    {
                        Text = delta, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center,
                        Foreground = Role(p.RivalDeltaSign > 0 ? "FSTRivalWinTextBrush" : "FSTRivalLoseTextBrush"),
                    });
                break;
            case SuggestionRowLayout.UnfcAccuracy when p.AccuracyExpanded is { } accuracy:
                var (r, g, b) = ScoreFormatting.AccuracyTint(accuracy);
                metadata.Children.Add(Services.ContrastTheme.IsOn
                    ? NeutralPill(p.AccuracyText!)
                    : Pill(p.AccuracyText!, new SolidColorBrush(Color.FromArgb(0x40, r, g, b)), null, null));
                break;
            // The shared season and percentile pills (pattern metadata-pills, issue #606): the same size as Songs rows and
            // leaderboards, and the current season is the inverted pill. The row's name already speaks the value.
            case SuggestionRowLayout.Season when p.SeasonText is { } season:
                var current = MetadataPillStyle.IsCurrent(p.SeasonNumber, App.Session.Catalog?.CurrentSeason);
                var seasonPill = MetadataPills.Season(season, current);
                seasonPill.Label(p.SeasonNumber is { } n ? MetadataPillStyle.SeasonAnnouncement(n, current) : season, PillId(item, "season"));
                metadata.Children.Add(seasonPill);
                break;
            case SuggestionRowLayout.Percentile when p.PercentileText is { } percentile:
                var percentilePill = MetadataPills.Percentile(percentile, MetadataPillStyle.Tier(p.PercentileTier));
                percentilePill.Label(percentile, PillId(item, "percentile"));
                metadata.Children.Add(percentilePill);
                break;
            case SuggestionRowLayout.SingleInstrument when p.StarCount > 0:
                metadata.Children.Add(new StarRow { Stars = p.GoldStars ? StarRating.GoldValue : p.StarCount, StarSize = 20 });
                break;
            case SuggestionRowLayout.InstrumentChips:
                foreach (var chip in p.Chips)
                {
                    // Contrast roles, like the Songs chips (brand hues, or Highlight / WindowText / GrayText under a contrast theme).
                    var (fill, stroke) = chip.IsFullCombo ? (Role("FSTStatusFcFillBrush"), Role("FSTStatusFcStrokeBrush"))
                        : chip.HasScore ? (Role("FSTStatusScoredFillBrush"), Role("FSTStatusScoredStrokeBrush"))
                        : (Role("FSTStatusMissingFillBrush"), Role("FSTStatusMissingStrokeBrush"));
                    // Web instrumentChip: 34 epx circle, 2 epx status stroke, 20 epx icon.
                    metadata.Children.Add(new Border
                    {
                        Width = 34, Height = 34, CornerRadius = new CornerRadius(17), Background = fill, BorderBrush = stroke,
                        BorderThickness = new Thickness(2), Padding = new Thickness(5),
                        Child = new InstrumentIcon { File = chip.Instrument.IconFile(item.UsesKeyboardIcon), Label = chip.Instrument.Label(), Width = 20, Height = 20 },
                    });
                }
                break;
        }
        if (p.Instrument is { } instrument && p.Layout != SuggestionRowLayout.InstrumentChips)
            metadata.Children.Add(new InstrumentIcon { File = instrument.IconFile(item.UsesKeyboardIcon), Label = instrument.Label(), Width = 28, Height = 28 });
        metadata.Visibility = metadata.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        ApplyWidth(ActualWidth);
    }

    /// <summary>Contrast role brush (<see cref="Services.ContrastTheme"/>).</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Brush.</returns>
    private static Brush Role(string key) => Services.ContrastTheme.Brush(key);

    /// <summary>
    /// Raw-view test ID of a row's shared pill, <c>fst.suggestions.row.&lt;song&gt;.&lt;instrument&gt;.&lt;kind&gt;</c>: the row
    /// ID with its <c>|</c> made a dot, so a UI step (which splits on <c>|</c>) can select it.
    /// </summary>
    /// <param name="item">Row.</param>
    /// <param name="kind"><c>season</c>, <c>percentile</c>, <c>rival</c> or <c>art</c>.</param>
    /// <returns>Automation ID.</returns>
    private static string PillId(SuggestionRowItem item, string kind) => $"{item.AutomationId.Replace('|', '.')}.{kind}";

    /// <summary>A plain pill in the contrast-theme role (ButtonFace fill, ButtonText text and outline; design/windows.md).</summary>
    /// <param name="text">Text.</param>
    /// <param name="automationId">Optional test ID for the pill's label.</param>
    /// <returns>Pill.</returns>
    private static Border NeutralPill(string text, string? automationId = null) =>
        Pill(text, Role("FSTNeutralPillFillBrush"), Role("FSTNeutralPillStrokeBrush"), Role("FSTNeutralPillTextBrush"), automationId);

    /// <summary>A rounded metadata pill.</summary>
    /// <param name="text">Text.</param>
    /// <param name="fill">Fill, or none.</param>
    /// <param name="stroke">Outline, or none.</param>
    /// <param name="foreground">Text brush, or the default.</param>
    /// <param name="automationId">
    /// Optional test ID for the label (a <see cref="Border"/> has no UIA peer), e.g.
    /// <c>fst.suggestions.row.s034.Solo_Guitar.rival</c> for the contrast paint check (issue #513). Narrator is unchanged.
    /// </param>
    /// <returns>Pill.</returns>
    private static Border Pill(string text, Brush? fill, Brush? stroke, Brush? foreground, string? automationId = null)
    {
        var label = new TextBlock { Text = text, FontWeight = FontWeights.SemiBold, FontSize = 14, HorizontalAlignment = HorizontalAlignment.Center };
        if (foreground is not null) label.Foreground = foreground;
        if (automationId is not null) AutomationProperties.SetAutomationId(label, automationId);
        return new Border
        {
            Child = label, Background = fill, BorderBrush = stroke, BorderThickness = new Thickness(stroke is null ? 0 : 2),
            CornerRadius = new CornerRadius(4), Padding = new Thickness(8, 2, 8, 2), MinWidth = 48, VerticalAlignment = VerticalAlignment.Center,
        };
    }

    /// <summary>
    /// Places metadata beside the title, or under it on a narrow row (<see cref="SuggestionRowMetrics"/>). A one-line row
    /// has no row spacing, so its art, text, metadata and chevron share the row's vertical centre (issue #654).
    /// </summary>
    /// <param name="width">Row width (epx).</param>
    private void ApplyWidth(double width)
    {
        var shouldBeNarrow = SuggestionRowMetrics.StacksMetadata(Item?.Presentation.Layout, width, metadata.Children.Count > 0);
        root.RowSpacing = SuggestionRowMetrics.RowSpacing(shouldBeNarrow);
        if (shouldBeNarrow == narrow && metadata.Parent is not null && (Grid.GetRow(metadata) == 1) == narrow) return;
        narrow = shouldBeNarrow;
        Grid.SetRow(metadata, narrow ? 1 : 0);
        Grid.SetColumn(metadata, narrow ? 1 : 2);
        Grid.SetColumnSpan(metadata, narrow ? 2 : 1);
        metadata.HorizontalAlignment = narrow ? HorizontalAlignment.Left : HorizontalAlignment.Right;
    }
    #endregion

    #region Art
    private void LoadArt()
    {
        if (Item is not { AlbumArt: { } raw } || art.Source is not null || artLoad is not null) return;
        if (App.Session.Settings.SaveData || App.Options.NoArt) return;
        _ = LoadArtAsync(raw);
    }

    private async Task LoadArtAsync(string raw)
    {
        var cancellation = artLoad = new CancellationTokenSource();
        var pixels = (int)Math.Ceiling(ArtSize * (XamlRoot?.RasterizationScale ?? 1));
        var bitmap = await ArtworkImages.LoadAsync(raw, pixels, cancellation.Token);
        // One retry for a transient fetch/decode failure; a second failure leaves the placeholder tile.
        if (bitmap is null && !cancellation.IsCancellationRequested)
            bitmap = await ArtworkImages.LoadAsync(raw, pixels, cancellation.Token);
        if (cancellation.IsCancellationRequested) return;
        art.Source = bitmap;
        if (ReferenceEquals(artLoad, cancellation)) artLoad = null;
    }

    private void CancelArt()
    {
        artLoad?.Cancel();
        artLoad = null;
    }
    #endregion
}
#endregion
