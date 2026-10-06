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
}
#endregion
