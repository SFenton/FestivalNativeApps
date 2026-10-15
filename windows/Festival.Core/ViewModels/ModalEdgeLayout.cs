namespace Festival.Core.ViewModels;

#region Modal edge layout
/// <summary>Where an edge-docked modal sits in the window (issue #638).</summary>
public enum ModalEdge
{
    /// <summary>A full-height panel at the window's trailing edge, below the title bar (web <c>ModalShell</c> <c>rightDrawer</c>).</summary>
    TrailingPanel,

    /// <summary>A full-width sheet rising from the window's bottom edge (web mobile modal; iOS/Android Notifications sheet).</summary>
    BottomSheet,
}

/// <summary>
/// An edge-docked modal surface's frame in effective pixels: its edge, size and top inset from the window's top edge.
/// </summary>
/// <param name="Edge">Edge it docks to.</param>
/// <param name="Width">Surface width.</param>
/// <param name="Height">Surface height.</param>
/// <param name="Top">Distance from the window's top edge to the surface's top edge.</param>
public readonly record struct ModalEdgeFrame(ModalEdge Edge, double Width, double Height, double Top)
{
    /// <summary>
    /// The off-screen offset the surface slides in from: its width toward the trailing edge for a panel, its height
    /// downward for a sheet.
    /// </summary>
    public (double X, double Y) SlideFrom => Edge == ModalEdge.TrailingPanel ? (Width, 0) : (0, Height);
}

/// <summary>
/// Owner-approved Windows Notifications presentation (issue #638, modal-shell R17): the shared modal docks to the
/// window's trailing edge as a full-height panel like the web's desktop drawer, and becomes a bottom sheet like the
/// mobile apps once the window is narrow enough that navigation collapses to the hamburger menu.
/// </summary>
public static class ModalEdgeLayout
{
    /// <summary>Panel width (web <c>NOTIFICATION_DESKTOP_DRAWER.width</c>).</summary>
    public const double PanelWidth = 460;

    /// <summary>Largest share of the window width the panel takes (web <c>NOTIFICATION_DESKTOP_DRAWER.maxWidth</c> 92vw).</summary>
    public const double PanelMaxWidthFraction = 0.92;

    /// <summary>Share of the window height the sheet leaves above it (web mobile modal <c>top: 20%</c>).</summary>
    public const double SheetTopFraction = 0.2;

    /// <summary>
    /// Window width below which <c>NavigationView</c> in <c>PaneDisplayMode="Auto"</c> collapses to the hamburger menu
    /// (its default <c>CompactModeThresholdWidth</c>).
    /// </summary>
    public const double MinimalNavigationBelow = 641;

    /// <summary>Slide-in duration (web <c>MODAL_TRANSITION_MS</c>).</summary>
    public static readonly TimeSpan SlideDuration = TimeSpan.FromMilliseconds(250);

    /// <summary>Slide-in easing control points (the web panel's CSS <c>ease</c>).</summary>
    public static readonly (float X1, float Y1, float X2, float Y2) SlideEase = (0.25f, 0.1f, 0.25f, 1f);

    /// <summary>The edge the modal docks to for a window width.</summary>
    /// <param name="windowWidth">Window width in epx.</param>
    /// <param name="minimalBelow">Width below which navigation is in hamburger (Minimal) mode.</param>
    /// <returns><see cref="ModalEdge.BottomSheet"/> in a narrow window, else <see cref="ModalEdge.TrailingPanel"/>.</returns>
    public static ModalEdge EdgeFor(double windowWidth, double minimalBelow = MinimalNavigationBelow) =>
        windowWidth < minimalBelow ? ModalEdge.BottomSheet : ModalEdge.TrailingPanel;

    /// <summary>The surface frame for a window.</summary>
    /// <param name="windowWidth">Window width in epx.</param>
    /// <param name="windowHeight">Window height in epx.</param>
    /// <param name="captionHeight">Title bar height in epx; the surface never rises into it (issue #244).</param>
    /// <param name="minimalBelow">Width below which navigation is in hamburger (Minimal) mode.</param>
    /// <returns>Frame; empty sizes clamp to zero.</returns>
    public static ModalEdgeFrame Frame(double windowWidth, double windowHeight, double captionHeight,
        double minimalBelow = MinimalNavigationBelow)
    {
        var width = Math.Max(0, windowWidth);
        var height = Math.Max(0, windowHeight);
        var caption = Math.Clamp(captionHeight, 0, height);
        if (EdgeFor(width, minimalBelow) == ModalEdge.TrailingPanel)
            return new(ModalEdge.TrailingPanel, Math.Min(PanelWidth, width * PanelMaxWidthFraction), height - caption, caption);
        var sheet = Math.Min(height * (1 - SheetTopFraction), height - caption);
        return new(ModalEdge.BottomSheet, width, sheet, height - sheet);
    }
}
#endregion
