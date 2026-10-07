namespace Festival.Core.Domain;

#region Pager dimming
/// <summary>
/// How an unavailable board-pager arrow (First/Previous on page 1, Next/Last on the last page) looks
/// (surface-materials R1/R4, leaderboard-row R5; issue #319). By default the whole arrow host, card surface included, dims
/// to <see cref="DimmedOpacity"/> (web <c>Opacity.dimmed</c>). Under a Windows contrast theme the host stays fully opaque,
/// so its Window surface and WindowText rim stay solid like the rows' (R4), and the glyph alone turns GrayText, the
/// system's disabled cue.
/// </summary>
public static class PagerDimming
{
    /// <summary>Opacity of an unavailable arrow outside contrast themes (web <c>Opacity.dimmed</c>).</summary>
    public const double DimmedOpacity = 0.3;

    /// <summary>Opacity of an arrow's host (card surface + button).</summary>
    /// <param name="available">The arrow can page right now.</param>
    /// <param name="contrastTheme">A Windows contrast theme is on.</param>
    /// <returns>1, or <see cref="DimmedOpacity"/> for an unavailable arrow outside contrast themes.</returns>
    public static double HostOpacity(bool available, bool contrastTheme) =>
        available || contrastTheme ? 1 : DimmedOpacity;

    /// <summary>Whether the arrow's glyph takes the system GrayText colour (its disabled cue under a contrast theme).</summary>
    /// <param name="available">The arrow can page right now.</param>
    /// <param name="contrastTheme">A Windows contrast theme is on.</param>
    /// <returns>Whether to draw the glyph in GrayText.</returns>
    public static bool GrayTextGlyph(bool available, bool contrastTheme) => !available && contrastTheme;
}
#endregion
