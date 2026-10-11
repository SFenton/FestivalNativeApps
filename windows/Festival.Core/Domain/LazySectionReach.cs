namespace Festival.Core.Domain;

#region Lazy section reads
/// <summary>
/// When a page section that reads on demand (Player Profile's per-instrument rank and history) starts its reads: once
/// it comes within one viewport height above or below the visible area. That matches an <c>ItemsRepeater</c>'s default
/// cache (<c>VerticalCacheLength</c> 2), which used to decide it while the sections virtualized (#533).
/// </summary>
public static class LazySectionReach
{
    /// <summary>Whether a section is within one viewport of the visible area.</summary>
    /// <param name="viewportTop">Top of the effective viewport, in the section's coordinates (negative above it).</param>
    /// <param name="viewportHeight">Viewport height.</param>
    /// <param name="sectionHeight">Section height.</param>
    /// <returns><see langword="true"/> when the section should start its reads.</returns>
    public static bool IsNear(double viewportTop, double viewportHeight, double sectionHeight)
    {
        if (!(viewportHeight > 0) || double.IsNaN(viewportTop) || double.IsInfinity(viewportTop)) return false;
        var height = double.IsNaN(sectionHeight) ? 0 : Math.Max(0, sectionHeight);
        return viewportTop + 2 * viewportHeight >= 0 && viewportTop - viewportHeight <= height;
    }
}
#endregion
