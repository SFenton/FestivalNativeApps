namespace Festival.Core.Domain;

#region Section header edge fade
/// <summary>
/// The one top-edge ramp for rows under a pinned section title (scroll-edge R2–R5, R7, R8; issues #49, #308). Rows
/// scrolling up to the list's top edge, just below the pinned header bar, are fully clear at that edge and fully opaque
/// <see cref="Depth"/> epx below it, a linear ramp like the web's <c>useScrollMask</c>. The ramp's depth follows the
/// web's <c>min(scrollTop, distance)</c> (<see cref="FadeDepth"/>): none at the top of the list, and none where a
/// section title has just pinned (a Jump pick lands its first row fully opaque) or is about to pin (the band never
/// reaches past an incoming title, which the bar draws undimmed). Contrast themes, Windows transparency effects off and
/// the in-app Increase Contrast / Less Transparency settings keep the solid, hard edge (<see cref="IsEnabled"/>, also the
/// R7 switch for <see cref="BoardFooterEdgeFade"/>).
/// </summary>
public static class SongHeaderEdgeFade
{
    /// <summary>Ramp depth in epx (web <c>useScrollMask</c> <c>DEFAULT_SIZE</c>: 40 px). The only top-ramp constant.</summary>
    public const double Depth = 40;

    /// <summary>
    /// Mask alpha stops across a ramp, from its clear edge (offset 0) to fully opaque (offset 1): linear, like the web's
    /// <c>linear-gradient(transparent, black)</c>. <see cref="BoardFooterEdgeFade"/> uses them reversed.
    /// </summary>
    public static readonly IReadOnlyList<(float Offset, float Alpha)> Stops = [(0f, 0f), (1f, 1f)];

    /// <summary>Stand-in title position for "no section title near the edge" in compositor expressions.</summary>
    public const double FarTitle = 1_000_000;

    /// <summary>Whether the ramp is drawn (scroll-edge R7).</summary>
    /// <param name="contrastTheme">A Windows contrast theme is on.</param>
    /// <param name="transparencyEffects">Windows transparency effects are on.</param>
    /// <param name="lessTransparency">The in-app Less Transparency setting is on.</param>
    /// <param name="moreContrast">The in-app Increase Contrast setting is on.</param>
    /// <returns>Whether to fade.</returns>
    public static bool IsEnabled(bool contrastTheme, bool transparencyEffects, bool lessTransparency, bool moreContrast) =>
        !contrastTheme && transparencyEffects && !lessTransparency && !moreContrast;

    /// <summary>
    /// How deep the ramp may reach because of one section title: the gap between the viewport top and the title's text
    /// top while the title is below the viewport top, none while the title crosses into the bar, then how far its
    /// section's rows have scrolled past the pin line (the title's text top <paramref name="barHeight"/> above the viewport
    /// top). Continuous, so the ramp never snaps at a hand-off.
    /// </summary>
    /// <param name="titleTop">Title text top relative to the viewport top, or <see langword="null"/> for none realized.</param>
    /// <param name="barHeight">The pinned bar's height.</param>
    /// <returns>Limit in epx (≥ 0; <see cref="FarTitle"/> without a title).</returns>
    public static double TitleLimit(double? titleTop, double barHeight)
    {
        if (titleTop is not { } top || double.IsNaN(top)) return FarTitle;
        return Math.Max(Math.Max(top, -top - Math.Max(0, barHeight)), 0);
    }

    /// <summary>
    /// The ramp's depth: <see cref="Depth"/>, cut to the scroll offset (nothing under the bar at the top) and to the
    /// nearest section title's <see cref="TitleLimit"/>. The Songs page drives the same formula on the compositor.
    /// </summary>
    /// <param name="verticalOffset">List scroll offset in epx.</param>
    /// <param name="ownTitleTop">Text top of the first visible row's section title, if realized.</param>
    /// <param name="nextTitleTop">Text top of the following section's title, if realized.</param>
    /// <param name="barHeight">The pinned bar's height.</param>
    /// <returns>Depth in [0, <see cref="Depth"/>].</returns>
    public static double FadeDepth(double verticalOffset, double? ownTitleTop, double? nextTitleTop, double barHeight)
    {
        if (double.IsNaN(verticalOffset)) return 0;
        var limit = Math.Min(TitleLimit(ownTitleTop, barHeight), TitleLimit(nextTitleTop, barHeight));
        return Math.Clamp(Math.Min(verticalOffset, limit), 0, Depth);
    }

    /// <summary>Mask alpha at a point <paramref name="distance"/> epx below the clear edge of a ramp <paramref name="depth"/> deep.</summary>
    /// <param name="distance">Distance from the clear edge.</param>
    /// <param name="depth">Ramp depth (0 = hard edge: opaque from the edge on).</param>
    /// <returns>Mask alpha in [0, 1].</returns>
    public static double MaskAlpha(double distance, double depth) =>
        distance < 0 ? 0 : depth <= 0 ? 1 : Math.Clamp(distance / depth, 0, 1);

    /// <summary>UIA ItemStatus while no section header is pinned (loading, empty, error or the jump index open).</summary>
    public const string StatusHidden = "hidden";

    /// <summary>UIA ItemStatus when a contrast or transparency setting keeps the solid, hard edge.</summary>
    public const string StatusHardEdge = "hard-edge";

    /// <summary>UIA ItemStatus at the list's top, where nothing is under the header yet.</summary>
    public const string StatusTop = "top";

    /// <summary>UIA ItemStatus while scrolled with no ramp: a section title has just pinned (a Jump landing), so its first row is fully opaque.</summary>
    public const string StatusClear = "clear";

    /// <summary>UIA ItemStatus while rows fade under the header.</summary>
    public const string StatusFading = "fading";

    /// <summary>The edge state UI tests read from the raw-view <c>fst.songs.edge-fade</c> element.</summary>
    /// <param name="headerShown">Whether the pinned section header shows.</param>
    /// <param name="enabled">Whether the settings allow the fade (<see cref="IsEnabled"/>).</param>
    /// <param name="verticalOffset">List scroll offset in epx.</param>
    /// <param name="depth">Current ramp depth (<see cref="FadeDepth"/>).</param>
    /// <returns>One of the <c>Status*</c> values.</returns>
    public static string Status(bool headerShown, bool enabled, double verticalOffset, double depth) =>
        !headerShown ? StatusHidden
        : !enabled ? StatusHardEdge
        : !(verticalOffset > 0) ? StatusTop
        : depth >= 1 ? StatusFading
        : StatusClear;
}
#endregion
