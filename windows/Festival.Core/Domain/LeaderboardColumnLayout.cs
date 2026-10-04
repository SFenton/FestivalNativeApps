namespace Festival.Core.Domain;

#region Section content
/// <summary>Which kind of row a leaderboard section holds.</summary>
public enum LeaderboardRowKind
{
    /// <summary>Score rows (web <c>LeaderboardEntry</c>): rank · name · season · score · accuracy · stars.</summary>
    Score,

    /// <summary>Rankings rows (web <c>RankingEntry</c>): rank · name · songs label · rating.</summary>
    Ranking,
}

/// <summary>
/// What every row of one leaderboard section holds (issue #37; web <c>computeRankWidth</c>, the score <c>ch</c> width and
/// <c>topScoresLayout</c>), measured once over all of the section's rows <em>and</em> its pinned selected-player row, so
/// every row gets the same columns at the same widths.
/// </summary>
/// <param name="Kind">Row kind.</param>
/// <param name="RankChars">Longest rank text (<c>#1,234</c>); 0 for labelled rows without ranks.</param>
/// <param name="MetaChars">Longest season (<c>S15</c>) or songs label (<c>123 / 456</c>); 0 when no row has one.</param>
/// <param name="ValueChars">Longest score or rating text.</param>
/// <param name="HasAccuracy">Whether any score row has an accuracy badge.</param>
/// <param name="HasStars">Whether any score row has stars.</param>
public sealed record LeaderboardSection(LeaderboardRowKind Kind, int RankChars, int MetaChars, int ValueChars, bool HasAccuracy, bool HasStars)
{
    /// <summary>Whether any row has a season (score sections) or songs label (rankings sections).</summary>
    public bool HasMeta => MetaChars > 0;
}
#endregion

#region Column plan
/// <summary>
/// The columns every row of a section shows and their shared widths, in effective pixels. A shown column keeps its width
/// on a row without a value (a blank badge or star slot), so values line up vertically down the section like the web's
/// <c>visibility: hidden</c> placeholders.
/// </summary>
/// <param name="Gap">Spacing between columns (8 below 420 epx, else 12; web <c>NARROW_BREAKPOINT</c>).</param>
/// <param name="RankWidth">Rank column width (0 for labelled rows).</param>
/// <param name="ShowMeta">Whether the season or songs column shows.</param>
/// <param name="MetaWidth">Season or songs column width (0 when hidden).</param>
/// <param name="ValueWidth">Score or rating column width.</param>
/// <param name="ShowAccuracy">Whether the accuracy column is reserved.</param>
/// <param name="AccuracyWidth">Accuracy column width (0 when hidden).</param>
/// <param name="ShowStars">Whether the stars column shows.</param>
/// <param name="StarsWidth">Stars column width (0 when hidden).</param>
/// <param name="MetaBelowName">
/// Whether a rankings row's songs label moves under the name instead of taking its own column, because the column would
/// squeeze the name below its minimum (large text in a narrow row; issue #208).
/// </param>
/// <param name="ValueBelowName">
/// Whether a rankings row still squeezes the name without the songs column, so it stacks on two lines: rank and name
/// (spanning the rating's column) on the first, the songs label (from the rank's edge) and the rating on the second
/// (issue #208: five-digit ranks and eleven-character ratings at 200% text).
/// </param>
/// <param name="Stacked">
/// Whether a score row's value columns move to a second line under the name (issue #207): the name keeps the first
/// line's width when even the reduced columns would leave it less than <see cref="LeaderboardColumnLayout.MinNameWidth"/>.
/// </param>
/// <param name="SplitValues">
/// When a score row is stacked, whether its pinned season and the score don't fit side by side under the name either, so
/// the score (with its badge and stars) takes a third line.
/// </param>
public sealed record LeaderboardColumnPlan(
    double Gap, double RankWidth, bool ShowMeta, double MetaWidth, double ValueWidth,
    bool ShowAccuracy, double AccuracyWidth, bool ShowStars, double StarsWidth, bool MetaBelowName = false,
    bool ValueBelowName = false, bool Stacked = false, bool SplitValues = false)
{
    /// <summary>Whether the narrow (8 epx gap) layout applies.</summary>
    public bool Compact => Gap < LeaderboardColumnLayout.WideGap;
}
#endregion

#region Fitting
/// <summary>
/// The one per-section column fitter for Windows leaderboard rows (issue #37). Ports the web's rules: the season column
/// from a 520 epx row (<c>MEDIUM_BREAKPOINT</c>), stars from 700 epx (<c>MOBILE_BREAKPOINT</c> 768 less the page chrome),
/// tighter gaps below 420 epx, the accuracy column always reserved in a section that has accuracy, and the rankings songs
/// label never dropped. When the fixed columns would squeeze the name below its minimum (narrow rows or large text),
/// stars go first, then the season; a rankings songs label moves under the name instead, and if the name is still
/// squeezed the rankings row stacks on two lines with the rating on the second, while a score row stacks its value
/// columns under the name (Windows text scaling has no web equivalent, and an all-ellipsis name hides whose row it is).
/// </summary>
public static class LeaderboardColumnLayout
{
    /// <summary>Horizontal row padding (12 epx each side).</summary>
    public const double RowPadding = 24;

    /// <summary>Rank width per character (web <c>Layout.rankCharWidth</c>).</summary>
    public const double RankCharWidth = 8.5;

    /// <summary>Narrowest rank column ("#1" to "#10" share it).</summary>
    public const double MinRankWidth = 28;

    /// <summary>Score width per character (semibold body digits).</summary>
    public const double ScoreCharWidth = 9;

    /// <summary>Rating width per character (wider than a bold digit, so a bold selected rating keeps its place).</summary>
    public const double RatingCharWidth = 9.5;

    /// <summary>Season width per character (body text, <c>S15</c>).</summary>
    public const double SeasonCharWidth = 8.5;

    /// <summary>Songs-label width per character (12 epx caption, bold on the selected row).</summary>
    public const double SongsCharWidth = 7;

    /// <summary>Accuracy badge width, sized for "XX.X%" (operator batch 7.1).</summary>
    public const double AccuracyWidth = 58;

    /// <summary>Five 18 epx star circles 2 epx apart (14 epx star images).</summary>
    public const double StarsWidth = 98;

    /// <summary>In-row chevron width.</summary>
    public const double ChevronWidth = 12;

    /// <summary>Narrowest name before optional columns drop.</summary>
    public const double MinNameWidth = 72;

    /// <summary>Row width below which gaps tighten (web <c>NARROW_BREAKPOINT</c>).</summary>
    public const double CompactBreakpoint = 420;

    /// <summary>Row width from which the season shows (web <c>MEDIUM_BREAKPOINT</c>).</summary>
    public const double SeasonBreakpoint = 520;

    /// <summary>Row width from which stars show (web <c>MOBILE_BREAKPOINT</c> less the page chrome).</summary>
    public const double StarsBreakpoint = 700;

    /// <summary>Normal column gap.</summary>
    public const double WideGap = 12;

    /// <summary>Compact column gap.</summary>
    public const double CompactGap = 8;

    /// <summary>Column gaps in a row: the row grid spaces all seven columns, shown or not.</summary>
    private const int GapCount = 6;

    /// <summary>Fits a section's columns into a row width.</summary>
    /// <param name="section">Section content (every row plus the pinned row).</param>
    /// <param name="rowWidth">Row width in epx, including padding; NaN or 0 before the first layout (no optional columns).</param>
    /// <param name="textScale">Windows text size factor (1–2.25); text widths grow with it.</param>
    /// <param name="pinSeason">
    /// Show a score section's season at any width and never drop it for space: the Score History tapped-bar detail row
    /// (web <c>renderDetailCard</c> passes <c>showSeason</c> whenever the point has one; issue #32/#62).
    /// </param>
    /// <returns>Columns and widths for every row of the section.</returns>
    public static LeaderboardColumnPlan Fit(LeaderboardSection section, double rowWidth, double textScale = 1, bool pinSeason = false)
    {
        var known = double.IsFinite(rowWidth) && rowWidth > 0;
        var scale = double.IsFinite(textScale) ? Math.Max(1, textScale) : 1;
        var score = section.Kind == LeaderboardRowKind.Score;
        var gap = known && rowWidth < CompactBreakpoint ? CompactGap : WideGap;
        var rank = section.RankChars == 0 ? 0 : Math.Max(MinRankWidth, Math.Ceiling(section.RankChars * RankCharWidth)) * scale;
        var value = Math.Ceiling(section.ValueChars * (score ? ScoreCharWidth : RatingCharWidth)) * scale;
        var meta = Math.Ceiling(section.MetaChars * (score ? SeasonCharWidth : SongsCharWidth)) * scale;
        var accuracy = score && section.HasAccuracy ? AccuracyWidth * scale : 0;
        var pinned = score && pinSeason;
        var showMeta = section.HasMeta && (!score || pinned || (known && rowWidth >= SeasonBreakpoint));
        var showStars = score && section.HasStars && known && rowWidth >= StarsBreakpoint;

        double Required() => RowPadding + rank + (showMeta ? meta : 0) + value + accuracy + (showStars ? StarsWidth : 0) +
                             ChevronWidth * scale + GapCount * gap + MinNameWidth * scale;

        if (showStars && Required() > rowWidth) showStars = false;
        if (score && showMeta && !pinned && Required() > rowWidth) showMeta = false;
        // Rankings never drop the songs label (web parity); it moves under the name rather than truncate the name away.
        var metaBelow = !score && showMeta && known && Required() > rowWidth;
        if (metaBelow) showMeta = false;
        var valueBelow = !score && known && Required() > rowWidth;
        var stacked = score && known && Required() > rowWidth;
        // Stacked, the season and score share the name's columns on the next line: everything but the rank, the badge,
        // stars, chevron and the four gaps outside that span.
        var under = rowWidth - RowPadding - rank - 4 * gap - accuracy - (showStars ? StarsWidth : 0) - ChevronWidth * scale;
        var split = stacked && showMeta && meta + gap + value > under;
        return new LeaderboardColumnPlan(
            gap, rank, showMeta, showMeta ? meta : 0, value,
            accuracy > 0, accuracy, showStars, showStars ? StarsWidth : 0, metaBelow, valueBelow, stacked, split);
    }
}
#endregion
