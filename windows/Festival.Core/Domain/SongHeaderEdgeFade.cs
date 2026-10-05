namespace Festival.Core.Domain;

#region Section header edge fade
/// <summary>
/// The soft edge under the Songs section header bar (issue #49, port of the iOS <c>SectionBarEdgeFade</c>, issue #10).
/// Rows scrolling up to the list's top edge, just below the pinned header, fade out over a short eased band instead of
/// being cut off hard. The band ramps in over the first <see cref="Depth"/> epx scrolled, so nothing fades while the
/// list is at its top. Contrast themes, Windows transparency effects off and the in-app Increase Contrast / Less
/// Transparency settings keep the solid, hard edge.
/// </summary>
public static class SongHeaderEdgeFade
{
    /// <summary>Band depth in epx (iOS <c>SectionBarEdgeFade</c>: 28 pt).</summary>
    public const double Depth = 28;

    /// <summary>Mask alpha stops through the band: smoothstep at 0, ¼, ½, ¾ and 1 (the iOS easing).</summary>
    public static readonly IReadOnlyList<(float Offset, float Alpha)> Stops =
        [.. new[] { 0f, 0.25f, 0.5f, 0.75f, 1f }.Select(t => (t, t * t * (3 - 2 * t)))];

    /// <summary>Whether the fade is drawn.</summary>
    /// <param name="contrastTheme">A Windows contrast theme is on.</param>
    /// <param name="transparencyEffects">Windows transparency effects are on.</param>
    /// <param name="lessTransparency">The in-app Less Transparency setting is on.</param>
    /// <param name="moreContrast">The in-app Increase Contrast setting is on.</param>
    /// <returns>Whether to fade.</returns>
    public static bool IsEnabled(bool contrastTheme, bool transparencyEffects, bool lessTransparency, bool moreContrast) =>
        !contrastTheme && transparencyEffects && !lessTransparency && !moreContrast;

    /// <summary>Fade strength for a scroll position: 0 at the top (hard edge, nothing is under it yet) to 1.</summary>
    /// <param name="verticalOffset">List scroll offset in epx.</param>
    /// <returns>Strength in [0, 1].</returns>
    public static double Strength(double verticalOffset) =>
        double.IsNaN(verticalOffset) ? 0 : Math.Clamp(verticalOffset / Depth, 0, 1);

    /// <summary>Mask alpha at a stop, scaled by the fade strength (1 = unchanged row).</summary>
    /// <param name="stopAlpha">Full-strength alpha at the stop.</param>
    /// <param name="strength">Fade strength.</param>
    /// <returns>Mask alpha.</returns>
    public static float MaskAlpha(float stopAlpha, double strength) => (float)(1 - Math.Clamp(strength, 0, 1) * (1 - stopAlpha));

    /// <summary>UIA ItemStatus while no section header is pinned (loading, empty, error or the jump index open).</summary>
    public const string StatusHidden = "hidden";

    /// <summary>UIA ItemStatus when a contrast or transparency setting keeps the solid, hard edge.</summary>
    public const string StatusHardEdge = "hard-edge";

    /// <summary>UIA ItemStatus at the list's top, where nothing is under the header yet.</summary>
    public const string StatusTop = "top";

    /// <summary>UIA ItemStatus while rows fade under the header.</summary>
    public const string StatusFading = "fading";

    /// <summary>The edge state UI tests read from the raw-view <c>fst.songs.edge-fade</c> element.</summary>
    /// <param name="headerShown">Whether the pinned section header shows.</param>
    /// <param name="enabled">Whether the settings allow the fade (<see cref="IsEnabled"/>).</param>
    /// <param name="strength">Current strength (<see cref="Strength"/>).</param>
    /// <returns>One of the <c>Status*</c> values.</returns>
    public static string Status(bool headerShown, bool enabled, double strength) =>
        !headerShown ? StatusHidden : !enabled ? StatusHardEdge : strength > 0 ? StatusFading : StatusTop;
}
#endregion
