using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Festival.App.Controls;

#region Song row visuals
/// <summary>
/// Lightweight elements for Songs rows (built in the phase-1 realization pass): instrument status chips and
/// selected-player metadata pills. Each is decorative for UIA; the row's name carries the full announcement.
/// </summary>
public static class SongRowVisuals
{
    /// <summary>Chip diameter in epx (web 34 px chip with a 24 px icon ≈ 70%).</summary>
    public const double ChipSize = 30;

    /// <summary>A status chip: status-colored circle with the instrument icon.</summary>
    /// <param name="badge">Chart and status.</param>
    /// <param name="songId">Row song (for the chip's test ID).</param>
    /// <param name="keyboard">Use the keys icon variant for Lead/Pro Lead.</param>
    /// <returns>Chip element.</returns>
    public static FrameworkElement Chip(SongInstrumentBadge badge, string songId, bool keyboard)
    {
        var (fill, stroke) = badge.Status switch
        {
            // Contrast roles: brand hues, or Highlight fill (FC) / WindowText ring (scored) / Highlight ring (inconsistent
            // FC) / GrayText ring (missing); not charted has no ring (SongInstrumentBadge.Ring).
            SongInstrumentStatus.FullCombo => ("FSTStatusFcFillBrush", "FSTStatusFcStrokeBrush"),
            SongInstrumentStatus.Scored => ("FSTStatusScoredFillBrush", "FSTStatusScoredStrokeBrush"),
            SongInstrumentStatus.NoScore => ("FSTStatusMissingFillBrush", "FSTStatusMissingStrokeBrush"),
            SongInstrumentStatus.InconsistentFullCombo => ("FSTStatusAmberFillBrush", "FSTStatusAmberStrokeBrush"),
            _ => ("FSTStatusNoneFillBrush", "FSTStatusNoneStrokeBrush"),
        };
        var (ring, opacity) = badge.Ring(Services.ContrastTheme.IsOn);
        var icon = new Image
        {
            Source = InstrumentIcon.Bitmap(badge.Instrument.IconFile(keyboard)),
            Width = 21,
            Height = 21,
            Stretch = Stretch.Uniform,
        };
        // Raw view: tests and inspectors can find the chip, Narrator reads the row's name instead (no duplicate stops).
        AutomationProperties.SetAutomationId(icon, badge.AutomationId(songId));
        AutomationProperties.SetName(icon, badge.Announcement);
        AutomationProperties.SetAccessibilityView(icon, AccessibilityView.Raw);
        var chip = new Border
        {
            Width = ChipSize,
            Height = ChipSize,
            CornerRadius = new CornerRadius(ChipSize / 2),
            Background = Brush(fill),
            BorderBrush = Brush(stroke),
            BorderThickness = new Thickness(ring),
            Opacity = opacity,
            Child = icon,
        };
        ToolTipService.SetToolTip(chip, badge.Announcement);
        AutomationProperties.SetAccessibilityView(chip, AccessibilityView.Raw);
        return chip;
    }

    /// <summary>A metadata pill for one field: one raw-view UIA element named with the field's spoken text.</summary>
    /// <param name="field">Field.</param>
    /// <param name="songId">Row song for the <c>fst.songs.metadata.*</c> test ID, or <see langword="null"/> (measuring).</param>
    /// <param name="keyboard">Use the keys icon variant for an unfiltered Last Played entry's Lead/Pro Lead icon.</param>
    /// <returns>Pill element.</returns>
    public static FrameworkElement Pill(SongMetadataField field, string? songId = null, bool keyboard = false)
    {
        var element = field.Kind switch
        {
            MetadataField.Score => Plain(Text(field.Text, 14, FontWeights.SemiBold, null)),
            // A full combo is the web AccuracyDisplay fcBadge: "100%" in the shared skewed gold outline (issue #644).
            MetadataField.Percentage when field.FullCombo => MetadataPills.FullCombo(field.Text),
            MetadataField.Percentage when Services.ContrastTheme.IsOn => Accuracy(Neutral(field.Text)),
            MetadataField.Percentage => Accuracy(Box(Text(field.Text, PillFont, FontWeights.SemiBold, null),
                background: field.Tint is { } t ? new SolidColorBrush(Color.FromArgb(0x40, t.R, t.G, t.B)) : Brush("FSTSurfaceMutedBrush"), border: null)),
            // The shared percentile and season pills (pattern metadata-pills, issue #606).
            MetadataField.Percentile => MetadataPills.Percentile(field.Text, field.Percentile),
            // Stars and intensity fill the pill height so they line up with the text pills (operator batch 7.18, issue
            // #644): 24-epx star circles (web MiniStars) and the meter scaled from 20 to 24 epx (Apple Songs rows).
            MetadataField.Stars => Slot(new StarRow { Stars = field.Stars.Gold ? StarRating.GoldValue : field.Stars.Count, StarSize = RowStarSize }),
            MetadataField.Season => MetadataPills.Season(field.Text, field.CurrentSeason),
            MetadataField.Intensity => Slot(new Viewbox
            {
                Height = PillHeight,
                Stretch = Stretch.Uniform,
                Child = new DifficultyMeter { Raw = field.IntensityRaw ?? 0 },
            }),
            MetadataField.Difficulty when Services.ContrastTheme.IsOn => Neutral(field.Text),
            MetadataField.Difficulty => Box(
                Text(field.Text, PillFont, FontWeights.Bold, new SolidColorBrush(field.GameDifficulty is 0 or 2 ? Colors.Black : Colors.White)),
                Brush(field.GameDifficulty switch { 0 => "FSTDiffPillEasyBrush", 1 => "FSTDiffPillMediumBrush", 2 => "FSTDiffPillHardBrush", _ => "FSTDiffPillExpertBrush" }),
                null),
            // Web SongRow unfiltered Last Played: the most recently played chart's icon, then the date.
            MetadataField.LastPlayed when field.PlayedChart is { } played => Plain(new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 6,
                Children =
                {
                    new InstrumentIcon { File = played.IconFile(keyboard), Label = played.Label(), Width = 20, Height = 20, VerticalAlignment = VerticalAlignment.Center }
                        .Raw(),
                    Text(field.Text, 12, FontWeights.Normal, Brush("FSTSecondaryTextBrush")),
                },
            }),
            _ => Plain(Text(field.Text, 12, FontWeights.Normal, Brush("FSTSecondaryTextBrush"))),
        };
        element.VerticalAlignment = VerticalAlignment.Center;
        if (field.Kind is MetadataField.Stars or MetadataField.Intensity) element.ControlType = AutomationControlType.Image;
        element.Label(field.Announcement, songId is null ? null : SongMetadataLayout.AutomationId(field.Kind, songId));
        if (field.Announcement.Length > 0) ToolTipService.SetToolTip(element, field.Announcement);
        return element;
    }

    /// <summary>A contrast-theme pill: ButtonFace fill, ButtonText text and outline (the value is in the text).</summary>
    /// <param name="text">Pill text.</param>
    /// <returns>Pill.</returns>
    private static MetadataPill Neutral(string text) =>
        Box(Text(text, PillFont, FontWeights.SemiBold, Brush("FSTNeutralPillTextBrush")), Brush("FSTNeutralPillFillBrush"), Brush("FSTNeutralPillStrokeBrush"));

    /// <summary>Creates a text run.</summary>
    /// <param name="text">Text.</param>
    /// <param name="size">Font size.</param>
    /// <param name="weight">Weight.</param>
    /// <param name="foreground">Brush, or the default.</param>
    /// <returns>TextBlock.</returns>
    private static TextBlock Text(string text, double size, Windows.UI.Text.FontWeight weight, Brush? foreground)
    {
        var block = new TextBlock { Text = text, FontSize = size, FontWeight = weight, VerticalAlignment = VerticalAlignment.Center };
        if (foreground is not null) block.Foreground = foreground;
        return block;
    }

    /// <summary>Height of every metadata pill: the shared pill height (pattern metadata-pills).</summary>
    private const double PillHeight = MetadataPillStyle.Height;

    /// <summary>Boxed pill label size: the shared pill label, so accuracy and difficulty match the season and percentile.</summary>
    private const double PillFont = MetadataPillStyle.FontSize;

    /// <summary>Star image edge: <see cref="StarRow"/> rings it in a 1.25× circle, so the circle is the pill height.</summary>
    private const double RowStarSize = MetadataPillStyle.StarCircle / 1.25;

    /// <summary>Gives a graded accuracy pill the web accuracy minimum width, so it lines up with the full-combo pill.</summary>
    /// <param name="pill">Pill.</param>
    /// <returns>The pill.</returns>
    private static MetadataPill Accuracy(MetadataPill pill)
    {
        pill.MinWidth = MetadataPillStyle.AccuracyMinWidth;
        if (pill.Children.Count == 1 && pill.Children[0] is TextBlock label) label.HorizontalAlignment = HorizontalAlignment.Center;
        return pill;
    }

    /// <summary>Centres unboxed content (stars, the intensity meter) in a pill-height slot.</summary>
    /// <param name="content">Content.</param>
    /// <returns>Slot.</returns>
    private static MetadataPill Slot(FrameworkElement content)
    {
        content.VerticalAlignment = VerticalAlignment.Center;
        return Host(content, new MetadataPill { MinHeight = PillHeight });
    }

    /// <summary>Unboxed text (score, Last Played) at pill height.</summary>
    /// <param name="content">Text.</param>
    /// <returns>Pill.</returns>
    private static MetadataPill Plain(UIElement content) => Host(content, new MetadataPill { MinHeight = PillHeight });

    /// <summary>
    /// Wraps content in a rounded pill. The height is a minimum so the pill grows with text scaling instead of clipping
    /// (spec: "grow rather than clip at large text"). A pill without an outline pads by the outline width instead, so it
    /// has the shared pills' insets (<see cref="MetadataPills"/>) and the same height when the text grows (issue #644).
    /// </summary>
    /// <param name="content">Content.</param>
    /// <param name="background">Fill, or none.</param>
    /// <param name="border">Outline, or none.</param>
    /// <returns>Pill.</returns>
    private static MetadataPill Box(UIElement content, Brush? background, Brush? border)
    {
        const double stroke = MetadataPillStyle.StrokeWidth, inset = MetadataPillStyle.HorizontalPadding;
        return Host(content, new MetadataPill
        {
            Padding = border is null ? new Thickness(inset + stroke, stroke, inset + stroke, stroke) : new Thickness(inset, 0, inset, 0),
            MinHeight = PillHeight,
            CornerRadius = new CornerRadius(MetadataPillStyle.CornerRadius),
            Background = background ?? new SolidColorBrush(Colors.Transparent),
            BorderBrush = border,
            BorderThickness = new Thickness(border is null ? 0 : stroke),
        });
    }

    /// <summary>Puts content in a pill host.</summary>
    /// <param name="content">Content.</param>
    /// <param name="pill">Host.</param>
    /// <returns>The host.</returns>
    private static MetadataPill Host(UIElement content, MetadataPill pill)
    {
        pill.Children.Add(content);
        return pill;
    }

    /// <summary>Hides an element from the UIA control view (the pill and row already speak it).</summary>
    /// <param name="element">Element.</param>
    /// <returns>The element.</returns>
    private static UIElement Raw(this UIElement element)
    {
        AutomationProperties.SetAccessibilityView(element, AccessibilityView.Raw);
        return element;
    }

    /// <summary>Looks up an app brush.</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Brush.</returns>
    private static Brush Brush(string key) => (Brush)Application.Current.Resources[key];
}
#endregion
