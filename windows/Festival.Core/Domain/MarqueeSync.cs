namespace Festival.Core.Domain;

#region Marquee sync
/// <summary>
/// Shared scroll distance for a group of marquee lines that move together (pattern <c>song-header</c> R2), like the web
/// <c>useMarqueeSync</c>: when two or more lines overflow, each translates <c>max(overflowing widths) + gap</c>, so the
/// lines move the same pixel distance at the same speed from the shared epoch; with fewer than two overflowing lines
/// there is no shared distance and an overflowing line scrolls its own width plus the gap.
/// </summary>
public static class MarqueeSync
{
    /// <summary>Gap between a marquee's two copies in epx (web <c>MarqueeText</c> default 28).</summary>
    public const double Gap = 28;

    /// <summary>Shared translate distance for a group of lines.</summary>
    /// <param name="overflowWidths">Each line's natural text width when it overflows its column, else 0.</param>
    /// <param name="gap">Gap between the copies in epx.</param>
    /// <returns><c>max(widths) + gap</c> (rounded like the web) when two or more lines overflow; otherwise <see langword="null"/>.</returns>
    public static double? Distance(IEnumerable<double> overflowWidths, double gap = Gap)
    {
        var overflowing = overflowWidths.Where(w => w > 0).ToList();
        return overflowing.Count >= 2 ? Math.Round(overflowing.Max() + gap) : null;
    }

    /// <summary>Gap between a line's two copies so the copy lands exactly one translate distance to the right (web <c>adjustedGap</c>).</summary>
    /// <param name="distance">Translate distance (shared, or the line's own width plus <see cref="Gap"/>).</param>
    /// <param name="textWidth">The line's natural text width.</param>
    /// <returns>Non-negative gap in epx.</returns>
    public static double TrackGap(double distance, double textWidth) => Math.Max(0, distance - textWidth);
}
#endregion
