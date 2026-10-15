using System.Globalization;

namespace Festival.Core.Domain;

#region Look
/// <summary>
/// Theme roles and type treatment of one metadata pill. The keys name brushes in <c>Themes/Styles.xaml</c>, which maps them
/// to brand colours by default and to system colours under a contrast theme.
/// </summary>
/// <param name="FillKey">Fill brush key.</param>
/// <param name="StrokeKey">Stroke brush key.</param>
/// <param name="TextKey">Label brush key.</param>
/// <param name="Bold">Bold label (gold tiers) instead of SemiBold.</param>
/// <param name="Italic">Italic label (Top 1%).</param>
/// <param name="Skewed">Skewed −8° like the web <c>goldOutlineSkew</c> (Top 1%).</param>
public sealed record MetadataPillLook(string FillKey, string StrokeKey, string TextKey, bool Bold, bool Italic, bool Skewed);
#endregion

#region Style
/// <summary>
/// The one season pill and one percentile ("Top N%") pill every Windows surface draws: Songs rows, Suggestions, leaderboard
/// and Score History rows, the Profile percentile table and the first-run demos (pattern <c>metadata-pills</c>, issue #606).
/// Sizes follow the web <c>SeasonPill</c>/<c>PercentilePill</c>; colours follow Apple <c>ScoreSeasonPill</c>, whose current
/// season is the inverted pill.
/// </summary>
public static class MetadataPillStyle
{
    /// <summary>Label size: Fluent Body (14 epx), the web pill's semibold label at native density.</summary>
    public const double FontSize = 14;

    /// <summary>Pill height in epx (web/Android 24).</summary>
    public const double Height = 24;

    /// <summary>Outline width in epx (web <c>border.thick</c>).</summary>
    public const double StrokeWidth = 2;

    /// <summary>Corner radius: the Fluent control radius (web/Android use 8; native chrome wins, agent decision #606).</summary>
    public const double CornerRadius = 4;

    /// <summary>Horizontal label inset inside the stroke (web <c>padding.xs</c>).</summary>
    public const double HorizontalPadding = 4;

    /// <summary>Season pill minimum width (web <c>SeasonPill</c> 48).</summary>
    public const double SeasonMinWidth = 48;

    /// <summary>Percentile pill minimum width: the web 5.5em at <see cref="FontSize"/>.</summary>
    public const double PercentileMinWidth = 5.5 * FontSize;

    /// <summary>Songs accuracy pill minimum width (graded and full combo): the web <c>accuracyPillMinWidth</c> 3.75em.</summary>
    public const double AccuracyMinWidth = 3.75 * FontSize;

    /// <summary>
    /// Edge of each star circle on a metadata row: the pill height, so stars line up with the pills (web <c>MiniStars</c>
    /// 24 px circles; Apple and Android draw stars at the pill height too, issue #644).
    /// </summary>
    public const double StarCircle = Height;

    /// <summary>Visible season label.</summary>
    /// <param name="season">Season number.</param>
    /// <returns><c>S9</c>.</returns>
    public static string SeasonText(int season) => "S" + season.ToString(CultureInfo.InvariantCulture);

    /// <summary>Whether a score's season is the catalogue's current season (the inverted pill).</summary>
    /// <param name="season">Score season.</param>
    /// <param name="currentSeason">Catalogue current season, if known.</param>
    /// <returns>True only for a known positive match.</returns>
    public static bool IsCurrent(int? season, int? currentSeason) => season is > 0 && season == currentSeason;

    /// <summary>
    /// Tier of a raw 0–1 placement fraction as its "Top N%" label shows it (two decimals under 1%, whole numbers above,
    /// like <see cref="BandFormatting.Percentile"/>), so the pill matches the text without parsing culture-formatted digits.
    /// </summary>
    /// <param name="rawPercentile">Placement fraction (0.04 = top 4%).</param>
    /// <returns>Tier; ordinary when not finite.</returns>
    public static SongPercentileTier TierOf(double rawPercentile)
    {
        if (!double.IsFinite(rawPercentile)) return SongPercentileTier.Ordinary;
        var top = Math.Clamp(rawPercentile * 100, 0.01, 100);
        var shown = top < 1 ? Math.Round(top, 2, MidpointRounding.AwayFromZero) : Math.Round(top, 0, MidpointRounding.AwayFromZero);
        return shown <= 1 ? SongPercentileTier.TopOne : shown <= 5 ? SongPercentileTier.TopFive : SongPercentileTier.Ordinary;
    }

    /// <summary>
    /// A score row's spoken name with its season clause (<c>, season 40</c>) read as <c>, current season 40</c> when the pill
    /// shows the inverted current season, so the inversion has a spoken equivalent (pattern R5).
    /// </summary>
    /// <param name="announcement">Row name that already reads the shown season.</param>
    /// <param name="season">Score season.</param>
    /// <param name="currentSeason">Catalogue current season, if known.</param>
    /// <returns>The name, with "current" added for the current season.</returns>
    public static string WithCurrentSeason(string announcement, int? season, int? currentSeason)
    {
        if (!IsCurrent(season, currentSeason)) return announcement;
        var clause = ", season " + season!.Value.ToString(CultureInfo.InvariantCulture);
        for (var at = announcement.IndexOf(clause, StringComparison.Ordinal); at >= 0;
             at = announcement.IndexOf(clause, at + 1, StringComparison.Ordinal))
        {
            var end = at + clause.Length;
            if (end == announcement.Length || announcement[end] == ',') return announcement.Insert(at + 2, "current ");
        }
        return announcement;
    }

    /// <summary>Spoken season.</summary>
    /// <param name="season">Season number.</param>
    /// <param name="current">Whether it is the current season.</param>
    /// <returns><c>Season 9</c> or <c>Current season 9</c>.</returns>
    public static string SeasonAnnouncement(int season, bool current) =>
        (current ? "Current season " : "Season ") + season.ToString(CultureInfo.CurrentCulture);

    /// <summary>Maps the Suggestions tier onto the shared percentile tier.</summary>
    /// <param name="tier">Suggestion row tier.</param>
    /// <returns>Shared tier.</returns>
    public static SongPercentileTier Tier(PercentileTier tier) => tier switch
    {
        PercentileTier.Top1 => SongPercentileTier.TopOne,
        PercentileTier.Top5 => SongPercentileTier.TopFive,
        _ => SongPercentileTier.Ordinary,
    };

    /// <summary>Season pill look: textSecondary on surfaceSubtle, inverted for the current season.</summary>
    /// <param name="current">Current season.</param>
    /// <returns>Look.</returns>
    public static MetadataPillLook Season(bool current) => current
        ? new("FSTCurrentSeasonFillBrush", "FSTCurrentSeasonStrokeBrush", "FSTCurrentSeasonTextBrush", false, false, false)
        : new("FSTSeasonPillFillBrush", "FSTSeasonPillStrokeBrush", "FSTSeasonPillTextBrush", false, false, false);

    /// <summary>
    /// Percentile pill look (web <c>PercentilePill</c>): Top 1% a skewed bold italic gold outline, Top 5% a bold gold outline,
    /// otherwise textSecondary on surfaceWhiteSubtle.
    /// </summary>
    /// <param name="tier">Tier.</param>
    /// <param name="bold">Bold label for the ordinary tier (web <c>bold</c> prop).</param>
    /// <returns>Look.</returns>
    public static MetadataPillLook Percentile(SongPercentileTier tier, bool bold = false) => tier switch
    {
        SongPercentileTier.TopOne => new("FSTGoldPillFillBrush", "FSTEmphasisStrokeBrush", "FSTEmphasisBrush", true, true, true),
        SongPercentileTier.TopFive => new("FSTGoldPillFillBrush", "FSTEmphasisStrokeBrush", "FSTEmphasisBrush", true, false, false),
        _ => new("FSTPercentileNeutralFillBrush", "FSTPercentileNeutralStrokeBrush", "FSTPercentileNeutralTextBrush", bold, false, false),
    };

    /// <summary>
    /// Full-combo accuracy look on Songs rows (web <c>AccuracyDisplay</c> <c>fcBadge</c>: <c>goldOutlineSkew</c>, the same
    /// skewed bold italic gold outline as Top 1%; issue #644).
    /// </summary>
    public static MetadataPillLook FullCombo { get; } = Percentile(SongPercentileTier.TopOne);

    /// <summary>Width a season pill takes for a label of <paramref name="chars"/> characters at text scale 1.</summary>
    /// <param name="chars">Label length.</param>
    /// <param name="charWidth">Average glyph advance in epx.</param>
    /// <returns>Width in epx.</returns>
    public static double SeasonWidth(int chars, double charWidth) =>
        Math.Max(SeasonMinWidth, Math.Ceiling(chars * charWidth) + 2 * (HorizontalPadding + StrokeWidth));
}
#endregion
