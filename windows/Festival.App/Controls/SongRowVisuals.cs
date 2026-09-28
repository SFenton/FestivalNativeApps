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
    /// <param name="keyboard">Use the keys icon variant for Lead/Pro Lead.</param>
    /// <returns>Chip element.</returns>
    public static FrameworkElement Chip(SongInstrumentBadge badge, bool keyboard)
    {
        var (fill, stroke) = badge.Status switch
        {
            SongInstrumentStatus.FullCombo => ("FSTGoldBrush", "FSTGoldStrokeBrush"),
            SongInstrumentStatus.Scored => ("FSTStatusGreenBrush", "FSTStatusGreenStrokeBrush"),
            SongInstrumentStatus.NoScore => ("FSTStatusRedBrush", "FSTStatusRedStrokeBrush"),
            SongInstrumentStatus.InconsistentFullCombo => ("FSTStatusAmberBrush", "FSTStatusAmberStrokeBrush"),
            _ => ("FSTSurfaceMutedBrush", "FSTBorderSubtleBrush"),
        };
        var chip = new Border
        {
            Width = ChipSize,
            Height = ChipSize,
            CornerRadius = new CornerRadius(ChipSize / 2),
            Background = Brush(fill),
            BorderBrush = Brush(stroke),
            BorderThickness = new Thickness(1.5),
            Opacity = badge.Status == SongInstrumentStatus.Unavailable ? 0.45 : 1,
            Child = new Image
            {
                Source = InstrumentIcon.Bitmap(badge.Instrument.IconFile(keyboard)),
                Width = 21,
                Height = 21,
                Stretch = Stretch.Uniform,
            },
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
            MetadataField.Percentage when field.FullCombo => Box(Text(field.Text, 12, FontWeights.Bold, Brush("FSTGoldBrush")),
                background: null, border: Brush("FSTGoldBrush")),
            MetadataField.Percentage => Box(Text(field.Text, 12, FontWeights.SemiBold, null),
                background: field.Tint is { } t ? new SolidColorBrush(Color.FromArgb(0x40, t.R, t.G, t.B)) : Brush("FSTSurfaceMutedBrush"), border: null),
            MetadataField.Percentile => field.Percentile switch
            {
                SongPercentileTier.TopOne => Box(Text(field.Text, 12, FontWeights.Bold, new SolidColorBrush(Colors.Black)), Brush("FSTGoldBrush"), null),
                SongPercentileTier.TopFive => Box(Text(field.Text, 12, FontWeights.SemiBold, Brush("FSTGoldBrush")), null, Brush("FSTGoldBrush")),
                _ => Box(Text(field.Text, 12, FontWeights.SemiBold, null), Brush("FSTSurfaceMutedBrush"), null),
            },
            MetadataField.Stars => new StarRow { Stars = field.Stars.Gold ? StarRating.GoldValue : field.Stars.Count, StarSize = 14 },
            MetadataField.Season => field.CurrentSeason
                ? Box(Text(field.Text, 12, FontWeights.Bold, new SolidColorBrush(Colors.Black)), new SolidColorBrush(Colors.White), null)
                : Box(Text(field.Text, 12, FontWeights.SemiBold, null), null, Brush("FSTBorderSubtleBrush")),
            MetadataField.Intensity => new DifficultyMeter { Raw = field.IntensityRaw ?? 0, VerticalAlignment = VerticalAlignment.Center },
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

    /// <summary>Wraps content in a rounded pill.</summary>
    /// <param name="content">Content.</param>
    /// <param name="background">Fill, or none.</param>
    /// <param name="border">Outline, or none.</param>
    /// <returns>Border.</returns>
    private static Border Box(UIElement content, Brush? background, Brush? border) => new()
    {
        Child = content,
        Padding = new Thickness(6, 2, 6, 2),
        MinHeight = 22,
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
