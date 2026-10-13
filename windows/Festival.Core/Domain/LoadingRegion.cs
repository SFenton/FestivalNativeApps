namespace Festival.Core.Domain;

#region Loading region
/// <summary>The usable portion of a loading viewport between a retained header and floating footer.</summary>
public static class LoadingRegion
{
    /// <summary>Resolves top and bottom insets, clipping chrome outside the viewport.</summary>
    /// <param name="height">Viewport height.</param>
    /// <param name="headerBottom">Retained header's lower edge, or null when no header is visible.</param>
    /// <param name="footerTop">Floating footer's upper edge, or null when no footer is visible.</param>
    /// <param name="minHeight">Smallest region (the indicator's height); a tighter gap gives way into the header first.</param>
    /// <returns>Insets whose remaining region avoids visible chrome whenever at least <paramref name="minHeight"/> fits.</returns>
    public static (double Top, double Bottom) Insets(double height, double? headerBottom, double? footerTop, double minHeight = 0)
    {
        height = Math.Max(height, 0);
        // The floating footer is fixed, interactive chrome; the retained header is scroll content and gives way first.
        var end = Math.Clamp(footerTop ?? height, 0, height);
        var top = Math.Clamp(headerBottom ?? 0, 0, end);
        if (end - top < minHeight) top = Math.Max(0, end - minHeight);
        if (end - top < minHeight) end = Math.Min(height, top + minHeight);
        return (top, height - end);
    }
}
#endregion
