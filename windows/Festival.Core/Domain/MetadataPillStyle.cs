using System.Globalization;

namespace Festival.Core.Domain;

#region Tier
/// <summary>Visual tier of a percentile pill (web <c>PercentilePill</c>).</summary>
public enum PercentileTier
{
    /// <summary>Neutral pill (web <c>textSecondary</c> on <c>surfaceWhiteSubtle</c>).</summary>
    Default,
    /// <summary>Top 5% (web <c>goldOutline</c>).</summary>
    Top5,
    /// <summary>Top 1% (web <c>goldOutlineSkew</c>: the gold outline, italic and skewed).</summary>
    Top1,
}
#endregion

#region Roles
/// <summary>
/// The resource keys and text treatment one metadata pill draws with. Keys name role brushes in
/// <c>Themes/Styles.xaml</c>: brand colours by default, system colours under a contrast theme.
/// </summary>
/// <param name="Fill">Fill brush key.</param>
/// <param name="Text">Text brush key.</param>
/// <param name="Stroke">2 epx outline brush key.</param>
/// <param name="Bold">Bold rather than semibold text.</param>
/// <param name="Italic">Italic text.</param>
/// <param name="Skew">Skewed −8° like the web's <c>GOLD_SKEW</c>.</param>
public readonly record struct MetadataPillRoles(string Fill, string Text, string Stroke, bool Bold = false, bool Italic = false, bool Skew = false);
#endregion

#region Style
/// <summary>
/// The one Windows season and percentile pill (pattern <c>metadata-pills</c>; issue #606): geometry, text and colour
/// roles shared by Songs rows, Suggestions, Song Detail, Score History, Player History, song and band leaderboards, the
/// Profile percentile table and the first-run demos. Ports web <c>SeasonPill</c> / <c>PercentilePill</c> and Apple
/// <c>ScoreSeasonPill</c>: the season pill is <c>textSecondary</c> on <c>surfaceSubtle</c> with a <c>borderSubtle</c>
/// outline and inverts for the current season; the percentile pill is gold-outlined for the top 5% and also italic and
/// skewed for the top 1%.
/// </summary>
public static class MetadataPillStyle
{
    /// <summary>Text size in epx (Fluent Caption, the accuracy badge's size).</summary>
    public const double FontSize = 12;

    /// <summary>Pill height before text scaling grows it.</summary>
    public const double MinHeight = 22;

    /// <summary>Horizontal text inset.</summary>
    public const double HorizontalPadding = 6;

    /// <summary>Corner radius (Fluent <c>ControlCornerRadius</c>).</summary>
    public const double CornerRadius = 4;

    /// <summary>Outline thickness (web <c>Border.thick</c>).</summary>
    public const double StrokeThickness = 2;

    /// <summary>Narrowest season pill: the web's 48 px pill at 16 px text is 3 em, here 36 epx at 12 epx.</summary>
    public const double SeasonMinWidth = 36;

    /// <summary>Narrowest percentile pill (web <c>MetadataSize.percentilePillMinWidth</c> 5.5 em at 12 epx).</summary>
    public const double PercentileMinWidth = 66;

    /// <summary>Width per character of 12 epx semibold digits, for column planning before layout.</summary>
    public const double CharWidth = 7.5;

    /// <summary>Skew of the top-1% pill in degrees (web <c>GOLD_SKEW</c>).</summary>
    public const double SkewDegrees = -8;

    /// <summary>Visible season text (web <c>format.seasonShort</c>).</summary>
    /// <param name="season">Season number.</param>
    /// <returns>e.g. <c>S9</c>.</returns>
    public static string SeasonText(int season) => "S" + season.ToString(CultureInfo.InvariantCulture);

    /// <summary>Spoken season (Apple <c>ScoreSeasonPill</c>).</summary>
    /// <param name="season">Season number.</param>
    /// <param name="current">Whether it is the catalogue's current season.</param>
    /// <returns><c>Current season 9</c> or <c>Season 9</c>.</returns>
    public static string SeasonAnnouncement(int season, bool current) =>
        (current ? "Current season " : "Season ") + season.ToString(CultureInfo.InvariantCulture);

    /// <summary>Whether a season is the catalogue's current season (web <c>SeasonPill</c> reads it from context).</summary>
    /// <param name="season">Season number.</param>
    /// <param name="currentSeason">Catalogue season, if known.</param>
    /// <returns>True only for a known, positive, equal season.</returns>
    public static bool IsCurrentSeason(int season, int? currentSeason) => currentSeason is > 0 && season == currentSeason;

    /// <summary>Tier of a percentage (web <c>PercentilePill</c> thresholds).</summary>
    /// <param name="percent">Percent, e.g. 3 for "Top 3%".</param>
    /// <returns>Top 1% at or under 1, top 5% at or under 5, else default (also for a non-finite value).</returns>
    public static PercentileTier Tier(double percent) =>
        !double.IsFinite(percent) ? PercentileTier.Default
        : percent <= 1 ? PercentileTier.Top1
        : percent <= 5 ? PercentileTier.Top5
        : PercentileTier.Default;

    /// <summary>Tier of a "Top N%" label (web <c>/^Top\s+([\d.]+)%$/</c>).</summary>
    /// <param name="display">Label.</param>
    /// <returns>Tier (default for an unparsable label).</returns>
    public static PercentileTier TierFor(string? display)
    {
        if (display is null || !display.StartsWith("Top ", StringComparison.Ordinal) || !display.EndsWith('%') ||
            !double.TryParse(display[4..^1].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var pct))
            return PercentileTier.Default;
        return Tier(pct);
    }

    /// <summary>Colour roles of a season pill.</summary>
    /// <param name="current">Current season (inverted pill).</param>
    /// <returns>Roles.</returns>
    public static MetadataPillRoles Season(bool current) => current
        ? new("FSTCurrentSeasonFillBrush", "FSTCurrentSeasonTextBrush", "FSTCurrentSeasonStrokeBrush")
        : new("FSTSeasonPillFillBrush", "FSTSeasonPillTextBrush", "FSTSeasonPillStrokeBrush");

    /// <summary>Colour roles of a percentile pill.</summary>
    /// <param name="tier">Tier.</param>
    /// <returns>Roles.</returns>
    public static MetadataPillRoles Percentile(PercentileTier tier) => tier switch
    {
        PercentileTier.Top1 => new("FSTTopOneFillBrush", "FSTTopOneTextBrush", "FSTTopOneStrokeBrush", Bold: true, Italic: true, Skew: true),
        PercentileTier.Top5 => new("FSTGoldPillFillBrush", "FSTEmphasisBrush", "FSTEmphasisStrokeBrush", Bold: true),
        _ => new("FSTMetadataPillFillBrush", "FSTMetadataPillTextBrush", "FSTNeutralPillStrokeBrush"),
    };

    /// <summary>
    /// Width a season column reserves for its longest pill before layout (leaderboard sections share one width so every
    /// row's season pill lines up, like the web's fixed 48 px pill).
    /// </summary>
    /// <param name="chars">Longest season text, e.g. 3 for <c>S12</c>; 0 when no row has a season.</param>
    /// <returns>Width in epx at 100% text, or 0.</returns>
    public static double SeasonWidth(int chars) => chars <= 0 ? 0
        : Math.Max(SeasonMinWidth, Math.Ceiling(chars * CharWidth) + 2 * (HorizontalPadding + StrokeThickness));
}
#endregion
