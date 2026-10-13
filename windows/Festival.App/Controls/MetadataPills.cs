using Festival.App.Services;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Shared metadata pills
/// <summary>Canonical season and Top X% pills for content rows and their first-run replicas.</summary>
public static class MetadataPills
{
    /// <summary>Creates a season pill with the ScoreSeasonPill contrast treatment.</summary>
    /// <param name="text">Short season label.</param>
    /// <param name="current">Whether the catalogue identifies this as the current season.</param>
    /// <returns>A decorative, non-focusable pill.</returns>
    public static MetadataPill Season(string text, bool current = false) =>
        Create(text, MetadataPillMetrics.SeasonWidth,
            current ? "FSTCurrentSeasonFillBrush" : "FSTSeasonFillBrush",
            current ? "FSTCurrentSeasonTextBrush" : "FSTSeasonTextBrush",
            current ? "FSTCurrentSeasonTextBrush" : "FSTSeasonStrokeBrush", false);

    /// <summary>Creates a percentile pill using the web's automatic gold-outline tiers.</summary>
    /// <param name="text">Top X% label.</param>
    /// <param name="tier">Explicit tier, or automatic detection.</param>
    /// <returns>A decorative, non-focusable pill.</returns>
    public static MetadataPill Percentile(string text, PercentileTier? tier = null)
    {
        var resolved = tier ?? SuggestionRowPresentation.TierFor(text);
        var gold = resolved != PercentileTier.Default;
        return Create(text, MetadataPillMetrics.PercentileWidth,
            gold ? "FSTGoldPillFillBrush" : "FSTNeutralPillFillBrush",
            gold ? "FSTEmphasisBrush" : "FSTSeasonTextBrush",
            gold ? "FSTEmphasisStrokeBrush" : "FSTNeutralPillStrokeBrush", resolved == PercentileTier.Top1);
    }

    /// <summary>Builds one shared pill; the host owns live theme repaint and its subscription lifecycle.</summary>
    /// <param name="text">Label.</param>
    /// <param name="width">Minimum width.</param>
    /// <param name="fill">Fill role.</param>
    /// <param name="foreground">Text role.</param>
    /// <param name="stroke">Outline role.</param>
    /// <param name="italic">Top 1% emphasis.</param>
    /// <returns>Pill.</returns>
    private static MetadataPill Create(string text, double width, string fill, string foreground, string stroke, bool italic)
    {
        var label = new TextBlock
        {
            Text = text, FontSize = MetadataPillMetrics.FontSize,
            FontWeight = italic ? FontWeights.Bold : FontWeights.SemiBold,
            FontStyle = italic ? Windows.UI.Text.FontStyle.Italic : Windows.UI.Text.FontStyle.Normal,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            HighContrastAdjustment = ElementHighContrastAdjustment.None,
        };
        var pill = new MetadataPill
        {
            MinWidth = width, MinHeight = MetadataPillMetrics.Height,
            CornerRadius = new CornerRadius(MetadataPillMetrics.Radius),
            Padding = new Thickness(8, 0, 8, 0),
            BorderThickness = new Thickness(MetadataPillMetrics.Stroke),
            VerticalAlignment = VerticalAlignment.Center,
            RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5),
            RenderTransform = italic ? new SkewTransform { AngleX = -10 } : null,
        };
        pill.Children.Add(label);
        pill.Label(text, null);
        pill.RefreshColors = () =>
        {
            pill.Background = ContrastTheme.Brush(fill);
            pill.BorderBrush = ContrastTheme.Brush(stroke);
            label.Foreground = ContrastTheme.Brush(foreground);
        };
        pill.RefreshColors();
        return pill;
    }
}
#endregion
