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

    /// <summary>A metadata pill for one field.</summary>
    /// <param name="field">Field.</param>
    /// <returns>Pill element.</returns>
    public static FrameworkElement Pill(SongMetadataField field)
    {
        FrameworkElement element = field.Kind switch
        {
            MetadataField.Score => Text(field.Text, 14, FontWeights.SemiBold, null),
            MetadataField.Percentage when field.FullCombo => Box(Text(field.Text, 12, FontWeights.Bold, Brush("FSTEmphasisBrush")),
                background: null, border: Brush("FSTEmphasisBrush")),
            MetadataField.Percentage when Services.ContrastTheme.IsOn => Neutral(field.Text),
            MetadataField.Percentage => Box(Text(field.Text, 12, FontWeights.SemiBold, null),
                background: field.Tint is { } t ? new SolidColorBrush(Color.FromArgb(0x40, t.R, t.G, t.B)) : Brush("FSTSurfaceMutedBrush"), border: null),
            MetadataField.Percentile => field.Percentile switch
            {
                SongPercentileTier.TopOne => Box(Text(field.Text, 12, FontWeights.Bold, Brush("FSTTopOneTextBrush")), Brush("FSTTopOneFillBrush"), null),
                SongPercentileTier.TopFive => Box(Text(field.Text, 12, FontWeights.SemiBold, Brush("FSTEmphasisBrush")), null, Brush("FSTEmphasisBrush")),
                _ when Services.ContrastTheme.IsOn => Neutral(field.Text),
                _ => Box(Text(field.Text, 12, FontWeights.SemiBold, null), Brush("FSTSurfaceMutedBrush"), null),
            },
            // Stars and intensity sit in the same 22 epx slot as the text pills so every pill lines up (operator batch 7.18).
            MetadataField.Stars => Slot(new StarRow { Stars = field.Stars.Gold ? StarRating.GoldValue : field.Stars.Count, StarSize = 14 }),
            MetadataField.Season => field.CurrentSeason
                ? Box(Text(field.Text, 12, FontWeights.Bold, Brush("FSTCurrentSeasonTextBrush")), Brush("FSTCurrentSeasonFillBrush"), null)
                : Box(Text(field.Text, 12, FontWeights.SemiBold, null), null, Brush("FSTBorderSubtleBrush")),
            MetadataField.Intensity => Slot(new DifficultyMeter { Raw = field.IntensityRaw ?? 0, VerticalAlignment = VerticalAlignment.Center }),
            MetadataField.Difficulty when Services.ContrastTheme.IsOn => Neutral(field.Text),
            MetadataField.Difficulty => Box(
                Text(field.Text, 12, FontWeights.Bold, new SolidColorBrush(field.GameDifficulty is 0 or 2 ? Colors.Black : Colors.White)),
                Brush(field.GameDifficulty switch { 0 => "FSTDiffPillEasyBrush", 1 => "FSTDiffPillMediumBrush", 2 => "FSTDiffPillHardBrush", _ => "FSTDiffPillExpertBrush" }),
                null),
            _ => Text(field.Text, 12, FontWeights.Normal, Brush("FSTSecondaryTextBrush")),
        };
        element.VerticalAlignment = VerticalAlignment.Center;
        ToolTipService.SetToolTip(element, field.Announcement);
        AutomationProperties.SetAccessibilityView(element, AccessibilityView.Raw);
        return element;
    }

    /// <summary>A contrast-theme pill: ButtonFace fill, ButtonText text and outline (the value is in the text).</summary>
    /// <param name="text">Pill text.</param>
    /// <returns>Pill.</returns>
    private static Border Neutral(string text) =>
        Box(Text(text, 12, FontWeights.SemiBold, Brush("FSTNeutralPillTextBrush")), Brush("FSTNeutralPillFillBrush"), Brush("FSTNeutralPillStrokeBrush"));

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

    /// <summary>Height of every metadata pill.</summary>
    private const double PillHeight = 22;

    /// <summary>Centres unboxed content (stars, the intensity meter) in a pill-height slot.</summary>
    /// <param name="content">Content.</param>
    /// <returns>Slot.</returns>
    private static Border Slot(FrameworkElement content)
    {
        content.VerticalAlignment = VerticalAlignment.Center;
        return new Border { Child = content, Height = PillHeight };
    }

    /// <summary>Wraps content in a rounded pill.</summary>
    /// <param name="content">Content.</param>
    /// <param name="background">Fill, or none.</param>
    /// <param name="border">Outline, or none.</param>
    /// <returns>Border.</returns>
    private static Border Box(UIElement content, Brush? background, Brush? border) => new()
    {
        Child = content,
        Padding = new Thickness(6, 0, 6, 0),
        Height = PillHeight,
        CornerRadius = new CornerRadius(4),
        Background = background ?? new SolidColorBrush(Colors.Transparent),
        BorderBrush = border,
        BorderThickness = new Thickness(border is null ? 0 : 1.5),
    };

    /// <summary>Looks up an app brush.</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Brush.</returns>
    private static Brush Brush(string key) => (Brush)Application.Current.Resources[key];
}
#endregion
