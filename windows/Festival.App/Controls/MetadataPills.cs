using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI.Text;

namespace Festival.App.Controls;

#region Metadata pills
/// <summary>
/// The one season pill and one "Top N%" percentile pill (pattern <c>metadata-pills</c>, issue #606). Songs rows, Suggestions,
/// leaderboard and Score History rows, the Profile percentile table and the first-run demos all build them here, so they
/// share one size (<see cref="MetadataPillStyle"/>) and one set of contrast roles. Each pill is a
/// <see cref="MetadataPill"/>: one raw-view UIA element whose host row speaks the value.
/// </summary>
public static class MetadataPills
{
    /// <summary>A season pill (<c>S9</c>); the current season is the inverted pill.</summary>
    /// <param name="season">Season number.</param>
    /// <param name="current">Whether it is the catalogue's current season.</param>
    /// <returns>Pill.</returns>
    public static MetadataPill Season(int season, bool current) => Season(MetadataPillStyle.SeasonText(season), current);

    /// <summary>A season pill from an already formatted label.</summary>
    /// <param name="text">Label (<c>S9</c>).</param>
    /// <param name="current">Whether it is the catalogue's current season.</param>
    /// <returns>Pill.</returns>
    public static MetadataPill Season(string text, bool current)
    {
        var pill = Create();
        ApplySeason(pill, text, current);
        return pill;
    }

    /// <summary>A percentile pill (web <c>PercentilePill</c>).</summary>
    /// <param name="text">Label, e.g. <c>Top 3%</c>.</param>
    /// <param name="tier">Tier.</param>
    /// <param name="bold">Bold label for the ordinary tier.</param>
    /// <returns>Pill.</returns>
    public static MetadataPill Percentile(string text, SongPercentileTier tier, bool bold = false)
    {
        var pill = Create();
        ApplyPercentile(pill, text, tier, bold);
        return pill;
    }

    /// <summary>Restyles an existing pill (a re-rendered row) as a percentile.</summary>
    /// <param name="pill">Pill from <see cref="Create"/>.</param>
    /// <param name="text">Label, e.g. <c>Top 3%</c>.</param>
    /// <param name="tier">Tier.</param>
    /// <param name="bold">Bold label for the ordinary tier.</param>
    public static void ApplyPercentile(MetadataPill pill, string text, SongPercentileTier tier, bool bold = false) =>
        Apply(pill, text, MetadataPillStyle.Percentile(tier, bold), MetadataPillStyle.PercentileMinWidth);

    /// <summary>An empty pill with the shared chrome and a centred label, styled later with <see cref="ApplySeason"/>.</summary>
    /// <returns>Pill.</returns>
    public static MetadataPill Create()
    {
        var pill = new MetadataPill
        {
            // Minimum height: the pill grows with text scaling instead of clipping.
            MinHeight = MetadataPillStyle.Height,
            Padding = new Thickness(MetadataPillStyle.HorizontalPadding, 0, MetadataPillStyle.HorizontalPadding, 0),
            CornerRadius = new CornerRadius(MetadataPillStyle.CornerRadius),
            BorderThickness = new Thickness(MetadataPillStyle.StrokeWidth),
            VerticalAlignment = VerticalAlignment.Center,
            RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5),
        };
        // Raw even before MetadataPill.Label names it: the host row or card speaks the value.
        AutomationProperties.SetAccessibilityView(pill, AccessibilityView.Raw);
        pill.Children.Add(new TextBlock
        {
            FontSize = MetadataPillStyle.FontSize,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.NoWrap,
            // Every pill role maps to system colours under a contrast theme (Themes/Styles.xaml), so WinUI's automatic
            // adjustment would only repaint the label with a backplate inside the pill.
            HighContrastAdjustment = ElementHighContrastAdjustment.None,
        });
        return pill;
    }

    /// <summary>Restyles an existing pill (a recycled leaderboard row) as a season.</summary>
    /// <param name="pill">Pill from <see cref="Create"/>.</param>
    /// <param name="text">Season label (<c>S9</c>).</param>
    /// <param name="current">Current season.</param>
    public static void ApplySeason(MetadataPill pill, string text, bool current) =>
        Apply(pill, text, MetadataPillStyle.Season(current), MetadataPillStyle.SeasonMinWidth);

    /// <summary>The pill's label.</summary>
    /// <param name="pill">Pill from <see cref="Create"/>.</param>
    /// <returns>Label.</returns>
    public static TextBlock LabelOf(MetadataPill pill) => (TextBlock)pill.Children[0];

    /// <summary>Applies a look: fill, stroke, label brush, weight, italic and the −8° skew of the Top 1% badge.</summary>
    /// <param name="pill">Pill.</param>
    /// <param name="text">Label.</param>
    /// <param name="look">Theme roles.</param>
    /// <param name="minWidth">Minimum width.</param>
    private static void Apply(MetadataPill pill, string text, MetadataPillLook look, double minWidth)
    {
        pill.MinWidth = minWidth;
        pill.Background = Services.ContrastTheme.Brush(look.FillKey);
        pill.BorderBrush = Services.ContrastTheme.Brush(look.StrokeKey);
        pill.RenderTransform = look.Skewed ? new SkewTransform { AngleX = -8 } : null;
        var label = LabelOf(pill);
        label.Text = text;
        label.Foreground = Services.ContrastTheme.Brush(look.TextKey);
        label.FontWeight = look.Bold ? FontWeights.Bold : FontWeights.SemiBold;
        label.FontStyle = look.Italic ? FontStyle.Italic : FontStyle.Normal;
    }
}
#endregion
