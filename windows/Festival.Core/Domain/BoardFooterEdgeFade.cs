namespace Festival.Core.Domain;

#region Board footer edge fade
/// <summary>
/// The soft edge above a leaderboard's floating footer (the pinned "your score" row and the pager, issue #93). The web
/// ends the scroll viewport at the footer's top (<c>useLeaderboardFooterScrollMargin</c>) and masks its bottom
/// <see cref="Depth"/> px while more rows lie below (<c>useScrollMask</c>), so rows fade out just above the footer instead
/// of running on underneath it. The band eases out over the last <see cref="Depth"/> epx of scroll, so the last row is
/// fully clear at the end. Windows transparency effects off and the in-app Increase Contrast / Less Transparency settings
/// turn the ramp into a hard cut at the footer's top; a contrast theme draws a window-colour plate behind the footer
/// (<see cref="Treatment"/>, scroll-edge R7). Depth is the board/page mask (web <c>Page.tsx</c> <c>useScrollMask</c>,
/// 40), not the 36-unit per-row <c>useScrollFade</c> (scroll-edge R3).
/// </summary>
public static class BoardFooterEdgeFade
{
    /// <summary>Band depth in epx (web <c>useScrollMask</c> <c>DEFAULT_SIZE</c>: 40 px).</summary>
    public const double Depth = 40;

    /// <summary>Fade strength for the scroll left below the viewport: 0 at the end (nothing more below) to 1.</summary>
    /// <param name="scrollableHeight">Scroll extent minus viewport, epx.</param>
    /// <param name="verticalOffset">Current offset, epx.</param>
    /// <returns>Strength in [0, 1].</returns>
    public static double Strength(double scrollableHeight, double verticalOffset)
    {
        var remaining = scrollableHeight - verticalOffset;
        return double.IsNaN(remaining) ? 0 : Math.Clamp(remaining / Depth, 0, 1);
    }

    /// <summary>
    /// What a board draws where its rows meet the floating footer. Every board with a floating footer (pinned row and/or
    /// pager) gets the same treatment whether or not the selected player has a pinned row (issue #305). Rows never show
    /// behind a shown footer (scroll-edge R7): reduced transparency or contrast cuts them hard at the footer's top, and a
    /// contrast theme draws a window-colour plate behind the footer.
    /// </summary>
    /// <param name="footerShown">The rows and a non-empty footer are on screen.</param>
    /// <param name="contrastTheme">A Windows contrast theme is on.</param>
    /// <param name="transparencyEffects">Windows transparency effects are on.</param>
    /// <param name="lessTransparency">The in-app Less Transparency setting is on.</param>
    /// <param name="moreContrast">The in-app Increase Contrast setting is on.</param>
    /// <returns>The treatment.</returns>
    public static BoardFooterTreatment Treatment(bool footerShown, bool contrastTheme, bool transparencyEffects, bool lessTransparency, bool moreContrast)
    {
        if (!footerShown) return BoardFooterTreatment.None;
        if (contrastTheme) return BoardFooterTreatment.Plate;
        return SongHeaderEdgeFade.IsEnabled(contrastTheme, transparencyEffects, lessTransparency, moreContrast)
            ? BoardFooterTreatment.Fade
            : BoardFooterTreatment.Cut;
    }

    /// <summary>Mask strength for a treatment: the scroll-driven <paramref name="strength"/> for the fade, 0 (a hard cut at
    /// the footer's top, <see cref="Stops"/>) for <see cref="BoardFooterTreatment.Cut"/>.</summary>
    /// <param name="treatment">Treatment.</param>
    /// <param name="strength">Scroll strength from <see cref="Strength"/>.</param>
    /// <returns>Mask strength in [0, 1].</returns>
    public static double MaskStrength(BoardFooterTreatment treatment, double strength) =>
        treatment == BoardFooterTreatment.Fade ? Math.Clamp(strength, 0, 1) : 0;

    /// <summary>UIA ItemStatus when the board shows no footer (loading, empty or error).</summary>
    public const string StatusHidden = SongHeaderEdgeFade.StatusHidden;

    /// <summary>UIA ItemStatus while rows fade out above the footer.</summary>
    public const string StatusFading = SongHeaderEdgeFade.StatusFading;

    /// <summary>UIA ItemStatus at the end of the list: the last row sits fully clear above the footer.</summary>
    public const string StatusEnd = "end";

    /// <summary>UIA ItemStatus when reduced transparency or contrast cuts rows hard at the footer's top.</summary>
    public const string StatusHardEdge = SongHeaderEdgeFade.StatusHardEdge;

    /// <summary>UIA ItemStatus when a contrast theme draws the window-colour plate behind the footer.</summary>
    public const string StatusPlate = "plate";

    /// <summary>The edge state UI tests read from a board's raw-view <c>fst.&lt;board&gt;.footer-edge</c> element.</summary>
    /// <param name="treatment">Current treatment.</param>
    /// <param name="strength">Scroll strength from <see cref="Strength"/>.</param>
    /// <returns>One of the <c>Status*</c> values.</returns>
    public static string Status(BoardFooterTreatment treatment, double strength) => treatment switch
    {
        BoardFooterTreatment.Fade => strength > 0 ? StatusFading : StatusEnd,
        BoardFooterTreatment.Cut => StatusHardEdge,
        BoardFooterTreatment.Plate => StatusPlate,
        _ => StatusHidden,
    };

    /// <summary>
    /// Mask stops for a gradient from <see cref="Depth"/> epx above the footer's top to 1 epx below it: opaque at the
    /// band's start, a linear ramp (web <c>useScrollMask</c>: <c>linear-gradient(black bottom-40px, transparent
    /// bottom)</c>) to <c>1 − strength</c> at the footer's top, then clear from the footer's top down so no row shows
    /// beneath the footer. Not the Songs header's smoothstep (<see cref="SongHeaderEdgeFade.Stops"/>, scroll-edge R3).
    /// </summary>
    /// <param name="strength">Fade strength from <see cref="Strength"/>.</param>
    /// <returns>Offsets along that gradient with their mask alpha.</returns>
    public static IReadOnlyList<(float Offset, float Alpha)> Stops(double strength)
    {
        var footerTop = (float)(Depth / (Depth + 1));
        return [(0f, 1f), (footerTop, (float)(1 - Math.Clamp(strength, 0, 1))), (1f, 0f)];
    }
}

/// <summary>How a board's rows meet its floating footer (<see cref="BoardFooterEdgeFade.Treatment"/>).</summary>
public enum BoardFooterTreatment
{
    /// <summary>Plain rows: no footer on screen.</summary>
    None,

    /// <summary>Rows fade out over <see cref="BoardFooterEdgeFade.Depth"/> epx above the footer and are hidden beneath it.</summary>
    Fade,

    /// <summary>Reduced transparency or contrast: rows stay opaque and are cut hard at the footer's top.</summary>
    Cut,

    /// <summary>Contrast theme: a window-colour plate the footer's height hides the rows behind it.</summary>
    Plate,
}
#endregion
