namespace Festival.Core.Domain;

#region Board footer edge fade
/// <summary>
/// The soft edge above a leaderboard's floating footer (the pinned "your score" row and the pager, issue #93). The web
/// ends the scroll viewport at the footer's top (<c>useLeaderboardFooterScrollMargin</c>) and masks its bottom
/// <see cref="Depth"/> px while more rows lie below (<c>useScrollMask</c>), so rows fade out just above the footer instead
/// of running on underneath it. The band eases out over the last <see cref="Depth"/> epx of scroll, so the last row is
/// fully clear at the end. Contrast themes, Windows transparency effects off and the in-app Increase Contrast / Less
/// Transparency settings keep the plain list under the footer's solid surfaces (<see cref="SongHeaderEdgeFade.IsEnabled"/>).
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
    /// pager) gets the same treatment whether or not the selected player has a pinned row (issue #305).
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
            : BoardFooterTreatment.None;
    }

    /// <summary>
    /// Mask stops for a gradient from <see cref="Depth"/> epx above the footer's top to 1 epx below it: opaque above the
    /// band, the reversed smoothstep through the band (scaled by <paramref name="strength"/>), then clear from the
    /// footer's top down so no row shows beneath the footer.
    /// </summary>
    /// <param name="strength">Fade strength from <see cref="Strength"/>.</param>
    /// <returns>Offsets along that gradient with their mask alpha.</returns>
    public static IReadOnlyList<(float Offset, float Alpha)> Stops(double strength)
    {
        var scale = (float)(Depth / (Depth + 1));
        var band = SongHeaderEdgeFade.Stops.Select(s => (s.Offset * scale, SongHeaderEdgeFade.MaskAlpha(1 - s.Alpha, strength)));
        return [.. band, (1f, 0f)];
    }
}

/// <summary>How a board's rows meet its floating footer (<see cref="BoardFooterEdgeFade.Treatment"/>).</summary>
public enum BoardFooterTreatment
{
    /// <summary>Plain rows: no footer on screen, or transparency is reduced and the footer's solid surfaces suffice.</summary>
    None,

    /// <summary>Rows fade out over <see cref="BoardFooterEdgeFade.Depth"/> epx above the footer and are hidden beneath it.</summary>
    Fade,

    /// <summary>Contrast theme: a window-colour plate the footer's height hides the rows behind it.</summary>
    Plate,
}
#endregion
