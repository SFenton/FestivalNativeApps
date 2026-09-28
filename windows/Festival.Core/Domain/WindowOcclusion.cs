namespace Festival.Core.Domain;

#region Geometry
/// <summary>A screen rectangle in physical pixels (right/bottom exclusive).</summary>
/// <param name="Left">Left edge.</param>
/// <param name="Top">Top edge.</param>
/// <param name="Right">Right edge (exclusive).</param>
/// <param name="Bottom">Bottom edge (exclusive).</param>
public readonly record struct PixelRect(int Left, int Top, int Right, int Bottom)
{
    /// <summary>Whether the rectangle has no area.</summary>
    public bool IsEmpty => Right <= Left || Bottom <= Top;

    /// <summary>Intersection (empty when disjoint).</summary>
    /// <param name="other">Other rectangle.</param>
    /// <returns>Overlap.</returns>
    public PixelRect Intersect(PixelRect other) =>
        new(Math.Max(Left, other.Left), Math.Max(Top, other.Top), Math.Min(Right, other.Right), Math.Min(Bottom, other.Bottom));
}
#endregion

#region Window snapshot
/// <summary>What the occlusion check needs to know about one top-level window above the app.</summary>
/// <param name="Bounds">Visible frame (DWM extended frame bounds, no invisible resize borders).</param>
/// <param name="Visible">WS_VISIBLE.</param>
/// <param name="Minimized">Iconic.</param>
/// <param name="Cloaked">DWM-cloaked (another virtual desktop, suspended UWP frame, shell-hidden).</param>
/// <param name="ClickThrough">WS_EX_TRANSPARENT (overlays such as FPS counters draw over content without hiding it).</param>
/// <param name="Layered">WS_EX_LAYERED.</param>
/// <param name="LayeredOpaque">For a layered window: uses constant alpha 255 and no colour key (per-pixel alpha is not opaque).</param>
/// <param name="HasRegion">Shaped by a window region (treated as non-rectangular, so not occluding).</param>
public readonly record struct WindowSnapshot(
    PixelRect Bounds, bool Visible = true, bool Minimized = false, bool Cloaked = false, bool ClickThrough = false,
    bool Layered = false, bool LayeredOpaque = false, bool HasRegion = false);
#endregion

#region Occlusion
/// <summary>
/// Decides whether the app window is fully covered by opaque windows above it in Z-order (Chromium's native window
/// occlusion rules, simplified): only visible, unminimized, uncloaked, rectangular, opaque windows count, and the app
/// is occluded only when their union covers every pixel of its visible frame. Unknown shapes keep the app visible.
/// </summary>
public static class WindowOcclusion
{
    /// <summary>Largest fragment count tracked before giving up (and reporting visible).</summary>
    public const int MaxFragments = 256;

    /// <summary>Whether a window hides whatever is beneath it.</summary>
    /// <param name="window">Window above the app.</param>
    /// <returns><see langword="true"/> for an opaque, shown, rectangular window.</returns>
    public static bool IsOpaqueOccluder(WindowSnapshot window) =>
        window.Visible && !window.Minimized && !window.Cloaked && !window.ClickThrough && !window.HasRegion &&
        (!window.Layered || window.LayeredOpaque) && !window.Bounds.IsEmpty;

    /// <summary>Whether the target is fully covered by the opaque windows among <paramref name="above"/>.</summary>
    /// <param name="target">App window's visible frame.</param>
    /// <param name="above">Windows above it in Z-order.</param>
    /// <returns><see langword="true"/> when no pixel of the target is visible.</returns>
    public static bool IsOccluded(PixelRect target, IEnumerable<WindowSnapshot> above) =>
        IsCovered(target, above.Where(IsOpaqueOccluder).Select(w => w.Bounds));

    /// <summary>Whether the union of <paramref name="covers"/> contains <paramref name="target"/>.</summary>
    /// <param name="target">Rectangle to cover.</param>
    /// <param name="covers">Covering rectangles.</param>
    /// <returns><see langword="true"/> when fully covered; an empty target is never covered.</returns>
    public static bool IsCovered(PixelRect target, IEnumerable<PixelRect> covers)
    {
        if (target.IsEmpty) return false;
        List<PixelRect> uncovered = [target];
        foreach (var cover in covers)
        {
            var next = new List<PixelRect>(uncovered.Count + 3);
            foreach (var piece in uncovered) Subtract(piece, cover, next);
            if (next.Count == 0) return true;
            if (next.Count > MaxFragments) return false;
            uncovered = next;
        }
        return false;
    }

    /// <summary>Adds the parts of <paramref name="piece"/> outside <paramref name="cover"/> (at most four bands).</summary>
    /// <param name="piece">Rectangle.</param>
    /// <param name="cover">Rectangle removed from it.</param>
    /// <param name="output">Receives the remainder.</param>
    private static void Subtract(PixelRect piece, PixelRect cover, List<PixelRect> output)
    {
        var overlap = piece.Intersect(cover);
        if (overlap.IsEmpty)
        {
            output.Add(piece);
            return;
        }
        if (piece.Top < overlap.Top) output.Add(piece with { Bottom = overlap.Top });
        if (overlap.Bottom < piece.Bottom) output.Add(piece with { Top = overlap.Bottom });
        if (piece.Left < overlap.Left) output.Add(new PixelRect(piece.Left, overlap.Top, overlap.Left, overlap.Bottom));
        if (overlap.Right < piece.Right) output.Add(new PixelRect(overlap.Right, overlap.Top, piece.Right, overlap.Bottom));
    }
}
#endregion
