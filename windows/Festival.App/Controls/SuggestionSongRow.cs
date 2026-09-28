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
    private const double NarrowWidth = 440;
    private static readonly SolidColorBrush Gold = new(Color.FromArgb(0xFF, 0xFF, 0xD7, 0x00));
    private static readonly SolidColorBrush GoldStroke = new(Color.FromArgb(0xFF, 0xCF, 0xA5, 0x00));
    private static readonly SolidColorBrush GoldBackground = new(Color.FromArgb(0xFF, 0x33, 0x29, 0x15));
    private static readonly SolidColorBrush Green = new(Color.FromArgb(0xFF, 0x2E, 0xCC, 0x71));
    private static readonly SolidColorBrush GreenStroke = new(Color.FromArgb(0xFF, 0x1E, 0x7F, 0x46));
    private static readonly SolidColorBrush Red = new(Color.FromArgb(0xFF, 0xC6, 0x28, 0x28));
    private static readonly SolidColorBrush RedStroke = new(Color.FromArgb(0xFF, 0x8B, 0x00, 0x00));
    private static readonly SolidColorBrush SubtleFill = new(Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF));
    private static readonly SolidColorBrush RivalFill = new(Color.FromArgb(0x33, 0x42, 0x85, 0xF4));
    private static readonly SolidColorBrush RivalText = new(Color.FromArgb(0xFF, 0x6E, 0xA8, 0xFF));

    private readonly Grid root = new() { ColumnSpacing = 12, RowSpacing = 6, MinHeight = 64, Padding = new Thickness(24, 10, 24, 10) };
    private readonly Image art = new() { Stretch = Stretch.UniformToFill };
    private readonly MarqueeText title = new();
    private readonly TextBlock subtitle = new() { TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap, FontSize = 12 };
    private readonly StackPanel metadata = new() { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
    private CancellationTokenSource? artLoad;
    private bool narrow;

    /// <summary>Creates the row.</summary>
    public SuggestionSongRow()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        Padding = new Thickness(0);
        CornerRadius = new CornerRadius(0);
        Background = new SolidColorBrush(Colors.Transparent);
        BorderThickness = new Thickness(0, 1, 0, 0);
        BorderBrush = (Brush)Application.Current.Resources["FSTCardStrokeBrush"];
        subtitle.Foreground = (Brush)Application.Current.Resources["FSTSecondaryTextBrush"];

        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(ArtSize) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var artFrame = new Border
        {
            Width = ArtSize, Height = ArtSize, CornerRadius = new CornerRadius(6), Child = art,
            Background = (Brush)Application.Current.Resources["FSTSurfaceMutedBrush"], VerticalAlignment = VerticalAlignment.Center,
        };
        AutomationProperties.SetAccessibilityView(art, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        var text = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center, Children = { title, subtitle } };
        Grid.SetColumn(text, 1);
        root.Children.Add(artFrame);
        root.Children.Add(text);
        root.Children.Add(metadata);
        Content = root;

        title.TextStyle = TitleStyle;
        Click += (_, _) => { if (Item is { } item) MainWindow.Instance?.Navigate(item.Route); };
        // Long titles scroll while the row is hovered or keyboard-focused (web/Apple MarqueeText).
        PointerEntered += (_, _) => SetMarquee(true);
        PointerExited += (_, _) => SetMarquee(false);
        PointerCanceled += (_, _) => SetMarquee(false);
        GotFocus += (_, _) => SetMarquee(FocusState == FocusState.Keyboard);
        LostFocus += (_, _) => SetMarquee(false);
        Loaded += (_, _) => LoadArt();
        // WinUI can raise a stale Unloaded after the re-parented row's next Loaded; only cancel when really gone.
        Unloaded += (_, _) => { if (!IsLoaded) CancelArt(); };
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

    /// <summary>Starts or stops the title marquee (motion permitting).</summary>
    /// <param name="play">Whether to play.</param>
    private void SetMarquee(bool play)
    {
        MarqueeText.MotionAllowed = Motion.Allowed;
        if (play) title.Play();
        else title.Stop();
    }

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
        switch (p.Layout)
        {
            case SuggestionRowLayout.Rival:
                if (p.RivalName is { } rival) metadata.Children.Add(Pill(rival, RivalFill, null, RivalText));
                if (p.RivalDeltaText is { } delta)
                    metadata.Children.Add(new TextBlock
                    {
                        Text = delta, FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center,
                        Foreground = p.RivalDeltaSign > 0 ? Green : Red,
                    });
                break;
            case SuggestionRowLayout.UnfcAccuracy when p.AccuracyExpanded is { } accuracy:
                var (r, g, b) = ScoreFormatting.AccuracyTint(accuracy);
                metadata.Children.Add(Pill(p.AccuracyText!, new SolidColorBrush(Color.FromArgb(0x40, r, g, b)), null, null));
                break;
            case SuggestionRowLayout.Season when p.SeasonText is { } season:
                metadata.Children.Add(Pill(season, (Brush)Application.Current.Resources["FSTSurfaceMutedBrush"], null, null));
                break;
            case SuggestionRowLayout.Percentile when p.PercentileText is { } percentile:
                metadata.Children.Add(p.PercentileTier switch
                {
                    PercentileTier.Top1 => Pill(percentile, GoldBackground, GoldStroke, Gold, italic: true),
                    PercentileTier.Top5 => Pill(percentile, null, GoldStroke, Gold),
                    _ => Pill(percentile, SubtleFill, null, null),
                });
                break;
            case SuggestionRowLayout.SingleInstrument when p.StarCount > 0:
                metadata.Children.Add(new StarRow { Stars = p.GoldStars ? StarRating.GoldValue : p.StarCount, StarSize = 20 });
                break;
            case SuggestionRowLayout.InstrumentChips:
                foreach (var chip in p.Chips)
                {
                    var (fill, stroke) = chip.IsFullCombo ? (Gold, GoldStroke) : chip.HasScore ? (Green, GreenStroke) : (Red, RedStroke);
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
        if (IsLoaded) LoadArt();
    }

    /// <summary>A rounded metadata pill.</summary>
    private static Border Pill(string text, Brush? fill, Brush? stroke, Brush? foreground, bool italic = false)
    {
        var label = new TextBlock { Text = text, FontWeight = FontWeights.SemiBold, FontSize = 14, HorizontalAlignment = HorizontalAlignment.Center };
        if (foreground is not null) label.Foreground = foreground;
        if (italic) label.FontStyle = Windows.UI.Text.FontStyle.Italic;
        return new Border
        {
            Child = label, Background = fill, BorderBrush = stroke, BorderThickness = new Thickness(stroke is null ? 0 : 2),
            CornerRadius = new CornerRadius(4), Padding = new Thickness(8, 2, 8, 2), MinWidth = 48, VerticalAlignment = VerticalAlignment.Center,
        };
    }

    /// <summary>Places metadata beside the title, or under it on a narrow row.</summary>
    private void ApplyWidth(double width)
    {
        var shouldBeNarrow = width > 0 && width < NarrowWidth && Item?.Presentation.Layout is SuggestionRowLayout.InstrumentChips or SuggestionRowLayout.Rival;
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
