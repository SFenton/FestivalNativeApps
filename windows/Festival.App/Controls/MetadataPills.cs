using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI.Text;

namespace Festival.App.Controls;

#region Metadata pills
/// <summary>
/// The one Windows season pill and percentile pill (pattern <c>metadata-pills</c>, issue #606; web <c>SeasonPill</c> /
/// <c>PercentilePill</c>, Apple <c>ScoreSeasonPill</c>). Songs rows, Suggestions, Song Detail, Score History, Player
/// History, song and band leaderboards, the Profile percentile table and the first-run demos all draw their season and
/// "Top N%" chips here, so every page shows the same size, colours and current-season highlight. Geometry and colour
/// roles come from <see cref="MetadataPillStyle"/>; each pill re-resolves its brushes when the contrast theme changes.
/// </summary>
public static class MetadataPills
{
    /// <summary>A season pill: <c>S9</c>, inverted when it is the catalogue's current season.</summary>
    /// <param name="season">Season number.</param>
    /// <param name="currentSeason">Catalogue season (<see cref="CatalogSeason"/>), or <see langword="null"/>.</param>
    /// <param name="automationId">Test ID, or <see langword="null"/>.</param>
    /// <param name="announcement">UIA name; defaults to <c>Season 9</c> / <c>Current season 9</c>.</param>
    /// <returns>Pill (one raw-view text element; its <c>ItemStatus</c> is <c>current</c> for the current season).</returns>
    public static MetadataPill Season(int season, int? currentSeason, string? automationId, string? announcement = null)
    {
        var current = MetadataPillStyle.IsCurrentSeason(season, currentSeason);
        var pill = Build(MetadataPillStyle.SeasonText(season), MetadataPillStyle.Season(current), MetadataPillStyle.SeasonMinWidth,
            automationId, announcement ?? MetadataPillStyle.SeasonAnnouncement(season, current));
        AutomationProperties.SetItemStatus(pill, current ? "current" : "");
        return pill;
    }

    /// <summary>A percentile pill: neutral, gold outline for the top 5%, and also italic and skewed for the top 1%.</summary>
    /// <param name="text">Visible text, e.g. <c>Top 3%</c>.</param>
    /// <param name="tier">Tier (<see cref="MetadataPillStyle.Tier"/> or <see cref="MetadataPillStyle.TierFor"/>).</param>
    /// <param name="automationId">Test ID, or <see langword="null"/>.</param>
    /// <param name="announcement">UIA name; defaults to <paramref name="text"/>.</param>
    /// <returns>Pill (one raw-view text element named with the announcement).</returns>
    public static MetadataPill Percentile(string text, PercentileTier tier, string? automationId, string? announcement = null) =>
        Build(text, MetadataPillStyle.Percentile(tier), MetadataPillStyle.PercentileMinWidth, automationId, announcement ?? text);

    /// <summary>The loaded catalogue's current season, which season pills highlight (web <c>FestivalContext.currentSeason</c>).</summary>
    public static int? CatalogSeason => App.Session?.Catalog?.CurrentSeason;

    /// <summary>Builds a pill host with one centred text run.</summary>
    /// <param name="text">Visible text.</param>
    /// <param name="roles">Colour roles and text treatment.</param>
    /// <param name="minWidth">Narrowest pill.</param>
    /// <param name="automationId">Test ID, or <see langword="null"/>.</param>
    /// <param name="announcement">UIA name and tooltip.</param>
    /// <returns>Pill.</returns>
    private static MetadataPill Build(string text, MetadataPillRoles roles, double minWidth, string? automationId, string announcement)
    {
        var block = new TextBlock
        {
            Text = text,
            FontSize = MetadataPillStyle.FontSize,
            FontWeight = roles.Bold ? FontWeights.Bold : FontWeights.SemiBold,
            FontStyle = roles.Italic ? FontStyle.Italic : FontStyle.Normal,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            // The roles are system colours under a contrast theme, so the automatic text backplate is not needed and
            // would cover the Highlight fill of a current-season or Top 1% pill.
            HighContrastAdjustment = ElementHighContrastAdjustment.None,
        };
        var pill = new MetadataPill
        {
            Padding = new Thickness(MetadataPillStyle.HorizontalPadding, 0, MetadataPillStyle.HorizontalPadding, 0),
            MinHeight = MetadataPillStyle.MinHeight,
            MinWidth = minWidth,
            CornerRadius = new CornerRadius(MetadataPillStyle.CornerRadius),
            BorderThickness = new Thickness(MetadataPillStyle.StrokeThickness),
            BackgroundSizing = BackgroundSizing.OuterBorderEdge,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (roles.Skew)
        {
            pill.RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5);
            pill.RenderTransform = new SkewTransform { AngleX = MetadataPillStyle.SkewDegrees };
        }
        pill.Children.Add(block);
        pill.Label(announcement, automationId);
        ToolTipService.SetToolTip(pill, announcement);
        pill.Restyle = p =>
        {
            p.Background = Brush(roles.Fill);
            p.BorderBrush = Brush(roles.Stroke);
            block.Foreground = Brush(roles.Text);
        };
        return pill;
    }

    /// <summary>Looks up a role brush at call time (brand colour, or a system colour under a contrast theme).</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Brush.</returns>
    private static Brush Brush(string key) => Services.ContrastTheme.Brush(key);
}
#endregion
