namespace Festival.Core.Domain;

#region Board footer edge fade
/// <summary>
/// The one bottom-chrome ramp above a leaderboard's floating footer (the pinned "your score" row and the pager; issues
/// #93, #308). Like the web's <c>useScrollFade</c>, rows are fully clear at the footer's top and fully opaque
/// <see cref="Depth"/> epx above it, linear (<see cref="SongHeaderEdgeFade.Stops"/> reversed), and nothing shows beneath
/// the footer. The ramp's depth is <c>min(scroll left, Depth)</c> (<see cref="FadeDepth"/>), so at the end of the list
/// the last row is fully opaque. Contrast themes, Windows transparency effects off and the in-app Increase Contrast /
/// Less Transparency settings (<see cref="SongHeaderEdgeFade.IsEnabled"/>) get depth 0: a hard cut at the footer's top,
/// with no row text between or behind the footer's controls (scroll-edge R7).
/// </summary>
public static class BoardFooterEdgeFade
{
    /// <summary>Ramp depth in epx (web <c>useScrollFade</c> <c>DEFAULT_DISTANCE</c>: 36 px). The only bottom-ramp constant.</summary>
    public const double Depth = 36;

    /// <summary>The ramp's depth for the scroll left below the viewport: 0 at the end (nothing more below) up to <see cref="Depth"/>.</summary>
    /// <param name="scrollableHeight">Scroll extent minus viewport, epx.</param>
    /// <param name="verticalOffset">Current offset, epx.</param>
    /// <param name="enabled">Whether the settings allow the ramp; <see langword="false"/> gives the hard cut (0).</param>
    /// <returns>Depth in [0, <see cref="Depth"/>].</returns>
    public static double FadeDepth(double scrollableHeight, double verticalOffset, bool enabled = true)
    {
        var remaining = scrollableHeight - verticalOffset;
        return !enabled || double.IsNaN(remaining) ? 0 : Math.Clamp(remaining, 0, Depth);
    }

    /// <summary>
    /// Mask stops for a gradient from <c>depth</c> epx above the footer's top to the footer's top (clamped beyond both
    /// ends): opaque above the ramp, clear from the footer's top down.
    /// </summary>
    public static IReadOnlyList<(float Offset, float Alpha)> Stops { get; } =
        [.. SongHeaderEdgeFade.Stops.Select(s => (s.Offset, 1 - s.Alpha))];

    #region UI Automation state
    /// <summary>UIA ItemStatus while no mask is drawn: no rows (loading, empty, error) or no floating footer.</summary>
    public const string StatusHidden = "hidden";

    /// <summary>UIA ItemStatus for the accessibility hard cut at the footer's top (R7).</summary>
    public const string StatusHardEdge = "hard-edge";

    /// <summary>UIA ItemStatus with nothing left below (the end of the list, or rows that fit): nothing is dimmed (R4).</summary>
    public const string StatusEnd = "end";

    /// <summary>Prefix of the UIA ItemStatus while rows fade above the footer; the drawn ramp depth in whole epx follows.</summary>
    public const string StatusFadingPrefix = "fading:";

    /// <summary>
    /// The board footer edge state that the fade layer publishes to UI Automation, from the mask actually drawn, so a
    /// UI test can tell the 36 epx ramp, the end state and the R7 hard cut apart without reading pixels.
    /// </summary>
    /// <param name="drawn">Whether the mask is drawn (rows and a floating footer are shown).</param>
    /// <param name="enabled">Whether the settings allow the ramp (<see cref="SongHeaderEdgeFade.IsEnabled"/>).</param>
    /// <param name="drawnDepth">The drawn gradient's span above the footer's top, epx.</param>
    /// <returns><see cref="StatusHidden"/>, <see cref="StatusHardEdge"/>, <see cref="StatusEnd"/> or <c>fading:&lt;epx&gt;</c>.</returns>
    public static string Status(bool drawn, bool enabled, double drawnDepth) =>
        !drawn ? StatusHidden
        : !enabled ? StatusHardEdge
        : !(drawnDepth >= 1) ? StatusEnd
        : StatusFadingPrefix + Math.Round(drawnDepth).ToString(System.Globalization.CultureInfo.InvariantCulture);
    #endregion
}
#endregion
