namespace Festival.Core.Domain;

#region Section model
/// <summary>
/// One jump target on a page (web <c>PageQuickLinkItem</c>). <see cref="Glyph"/> is a Segoe Fluent Icons glyph;
/// <see cref="Instrument"/> shows that chart's icon instead.
/// </summary>
/// <param name="Id">Stable anchor ID reused from the web config (e.g. <c>app-settings</c>).</param>
/// <param name="Title">Visible label.</param>
/// <param name="Glyph">Optional Segoe Fluent Icons glyph.</param>
/// <param name="Instrument">Optional instrument icon.</param>
/// <param name="Depth">Indentation (negative clamps to 0).</param>
/// <param name="SpokenTitle">Fuller Narrator name for a short, context-dependent title.</param>
public sealed record QuickLinkSection(
    string Id, string Title, string? Glyph = null, Instrument? Instrument = null, int Depth = 0, string? SpokenTitle = null)
{
    /// <summary>Indentation level, never negative.</summary>
    public int Depth { get; init; } = Math.Max(0, Depth);

    /// <summary>Narrator name: <see cref="SpokenTitle"/>, else <see cref="Title"/>.</summary>
    public string AccessibleTitle => SpokenTitle ?? Title;

    /// <summary>Automation ID (<c>fst.quick-links.item.&lt;id&gt;</c>).</summary>
    public string AutomationId => "fst.quick-links.item." + Id;
}

/// <summary>A section's vertical extent relative to the viewport top (positive is below).</summary>
public readonly record struct QuickLinkFrame
{
    /// <summary>Creates a frame (<paramref name="maxY"/> is raised to <paramref name="minY"/>).</summary>
    /// <param name="minY">Top edge.</param>
    /// <param name="maxY">Bottom edge.</param>
    public QuickLinkFrame(double minY, double maxY)
    {
        MinY = minY;
        MaxY = Math.Max(minY, maxY);
    }

    /// <summary>Top edge relative to the viewport top.</summary>
    public double MinY { get; }

    /// <summary>Bottom edge relative to the viewport top.</summary>
    public double MaxY { get; }
}
#endregion

#region Pure rules
/// <summary>Visibility, ordering and natural active-section rules (web <c>usePageQuickLinks.ts</c>; Apple <c>QuickLinks</c>).</summary>
public static class QuickLinks
{
    /// <summary>Fewer sections hide the entry point (a one-item jump list does nothing).</summary>
    public const int MinimumSectionCount = 2;

    /// <summary>
    /// A jump lands the section's top this many epx below the viewport top (the web's default 32 px offset), so its
    /// title sits fully visible under the title bar rather than flush with it (#51).
    /// </summary>
    public const double LandingOffset = 32;

    /// <summary>
    /// A section is naturally active once its top is within this many epx of the viewport top. It matches
    /// <see cref="LandingOffset"/> so the section a jump lands is the highlighted one.
    /// </summary>
    public const double DefaultActivationOffset = LandingOffset;

    /// <summary>After a jump the target stays active while its top is within this band of the landing line.</summary>
    public const double ReachableBand = 96;

    /// <summary>Scroll drift tolerated before a settled jump releases ownership.</summary>
    public const double CompleteThreshold = 8;

    /// <summary>
    /// Tops within this many epx count as one row of a multi-column layout: the 12-epx fade-in rise
    /// (<see cref="FadeInTiming.OffsetY"/>) is staggered per card, so cards on the same row measure apart while it plays.
    /// </summary>
    public const double RowTolerance = FadeInTiming.OffsetY + 4;

    /// <summary>
    /// Page-area width (epx) at which the persistent jump pane replaces the menu: the web rail appears at a 1440 px
    /// viewport; beside the 240 epx navigation pane that leaves about 1150 epx of page area.
    /// </summary>
    public const double PaneMinimumWidth = 1150;

    /// <summary>Offset difference (epx) below which a jump counts as landed.</summary>
    public const double LandingTolerance = 0.5;

    /// <summary>
    /// Re-aims allowed after a jump settles: anchors below a virtualizing list move once the cards around the new
    /// viewport are realized and replace the list's estimated heights.
    /// </summary>
    public const int MaxJumpCorrections = 4;

    /// <summary>
    /// Layout passes a jump waits for its section's first focusable control to be realized (a virtualizing list far
    /// below the viewport) before it stops trying to move keyboard focus there.
    /// </summary>
    public const int MaxFocusRetries = 30;

    /// <summary>
    /// <c>BringIntoViewOptions.VerticalOffset</c> for a jump to a repeater-realized section with
    /// <c>VerticalAlignmentRatio = 0</c>. WinUI scrolls so the target's top rests this far below the viewport top, so it
    /// is the positive landing gap: a negative value (the #51 port) parked the section 32 epx under the title bar until
    /// the binder's correction pass re-aimed it (#251).
    /// </summary>
    public const double BringIntoViewOffset = LandingOffset;

    /// <summary>Scroll offset that puts an anchor <paramref name="landingMargin"/> below the viewport top.</summary>
    /// <param name="verticalOffset">Current scroll offset.</param>
    /// <param name="anchorTop">Anchor top relative to the viewport.</param>
    /// <param name="scrollableHeight">Largest reachable offset.</param>
    /// <param name="landingMargin">Gap kept above the anchor (default <see cref="LandingOffset"/>).</param>
    /// <returns>Target offset clamped to <c>[0, scrollableHeight]</c>.</returns>
    public static double JumpOffset(
        double verticalOffset, double anchorTop, double scrollableHeight, double landingMargin = LandingOffset) =>
        LandingTarget(verticalOffset + anchorTop, scrollableHeight, landingMargin);

    /// <summary>Whether the scroller already rests at a jump target.</summary>
    /// <param name="verticalOffset">Current scroll offset.</param>
    /// <param name="target">Target offset from <see cref="JumpOffset"/>.</param>
    /// <returns><see langword="true"/> within <see cref="LandingTolerance"/>.</returns>
    public static bool IsLanded(double verticalOffset, double target) => Math.Abs(target - verticalOffset) < LandingTolerance;

    /// <summary>Whether a page shows its entry point.</summary>
    /// <param name="sectionCount">Section count.</param>
    /// <returns><see langword="true"/> for two or more.</returns>
    public static bool IsAvailable(int sectionCount) => sectionCount >= MinimumSectionCount;

    /// <summary>Whether the wide persistent pane is used rather than the menu.</summary>
    /// <param name="pageWidth">Page-area width in epx.</param>
    /// <returns><see langword="true"/> at <see cref="PaneMinimumWidth"/> and wider.</returns>
    public static bool UsesPane(double pageWidth) => pageWidth >= PaneMinimumWidth;

    /// <summary>Ordered, de-duplicated sections: an explicit list wins over discovered ones.</summary>
    /// <param name="explicitSections">Page-declared sections, or <see langword="null"/>.</param>
    /// <param name="discovered">Sections found in visual-tree order.</param>
    /// <returns>Sections in display order, first occurrence of each ID.</returns>
    public static IReadOnlyList<QuickLinkSection> Ordered(IEnumerable<QuickLinkSection>? explicitSections, IEnumerable<QuickLinkSection> discovered)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        return [.. (explicitSections ?? discovered).Where(s => seen.Add(s.Id))];
    }

    /// <summary>Whether any part of a section intersects <c>[0, viewportHeight)</c>.</summary>
    /// <param name="frame">Frame, or <see langword="null"/> when not laid out.</param>
    /// <param name="viewportHeight">Viewport height.</param>
    /// <returns>Visibility.</returns>
    public static bool IsVisible(QuickLinkFrame? frame, double viewportHeight) =>
        frame is { } f && f.MaxY > 0 && f.MinY < viewportHeight;

    /// <summary>Whether a jump target sits close enough to its landing line to keep ownership.</summary>
    /// <param name="frame">Target frame.</param>
    /// <param name="activationOffset">Page activation offset.</param>
    /// <returns><see langword="true"/> within the reachable band.</returns>
    public static bool IsReachable(QuickLinkFrame frame, double activationOffset) =>
        frame.MinY >= -ReachableBand && frame.MinY <= activationOffset + ReachableBand;

    /// <summary>The scroll offset that lands a section's top on the landing line, clamped to the scrollable range.</summary>
    /// <param name="contentTop">Section top in scroll-content coordinates (current offset plus its viewport top).</param>
    /// <param name="scrollableHeight">Maximum scroll offset.</param>
    /// <param name="landingOffset">Landing line below the viewport top.</param>
    /// <returns>Vertical offset; sections near either end land as close as the content allows.</returns>
    public static double LandingTarget(double contentTop, double scrollableHeight, double landingOffset = LandingOffset) =>
        Math.Clamp(contentTop - landingOffset, 0, Math.Max(0, scrollableHeight));

    /// <summary>
    /// Scroll offset that lands a section <see cref="LandingOffset"/> below page chrome pinned over the viewport top at
    /// that offset (Song Detail's compact song header, #251). When the plain landing would pin chrome over the section,
    /// the section lands that much lower; it stays there even if the lower offset no longer pins the chrome.
    /// </summary>
    /// <param name="contentTop">Section top in content coordinates.</param>
    /// <param name="scrollableHeight">Largest reachable offset.</param>
    /// <param name="obscuredTop">Height (epx) covered at the viewport top when scrolled to a given offset.</param>
    /// <returns>Target offset clamped to <c>[0, scrollableHeight]</c>.</returns>
    public static double LandingTarget(double contentTop, double scrollableHeight, Func<double, double> obscuredTop)
    {
        var target = LandingTarget(contentTop, scrollableHeight);
        var inset = ObscuredHeight(obscuredTop, target);
        return inset > 0 ? LandingTarget(contentTop, scrollableHeight, LandingOffset + inset) : target;
    }

    /// <summary>Reads a chrome height, treating negative or non-finite values as none.</summary>
    /// <param name="obscuredTop">Height covered at the viewport top for an offset, or <see langword="null"/>.</param>
    /// <param name="verticalOffset">Scroll offset.</param>
    /// <returns>Height in epx, at least 0.</returns>
    public static double ObscuredHeight(Func<double, double>? obscuredTop, double verticalOffset)
    {
        var height = obscuredTop?.Invoke(verticalOffset) ?? 0;
        return height > 0 && double.IsFinite(height) ? height : 0;
    }

    /// <summary>
    /// The section a reader is "in": the row whose top crossed the activation line most recently (greatest top at or
    /// above the line), and in that row the earliest section in display order; unknown frames are skipped; with none
    /// past the line, the first.
    /// </summary>
    /// <remarks>
    /// In a single column tops grow in display order, so this is the web's "last past the line" rule. Multi-column
    /// masonry pages (Rivals, Leaderboards) put several sections on one row (tops within <see cref="RowTolerance"/>);
    /// the row rule keeps the first card of the row current instead of its right-hand neighbour (#213).
    /// </remarks>
    /// <param name="sections">Display-ordered sections.</param>
    /// <param name="frames">Known frames by ID.</param>
    /// <param name="activationOffset">Activation line below the viewport top.</param>
    /// <returns>Active ID, or <see langword="null"/> with no sections.</returns>
    public static string? NaturalActive(
        IReadOnlyList<QuickLinkSection> sections, IReadOnlyDictionary<string, QuickLinkFrame> frames, double activationOffset = DefaultActivationOffset)
    {
        if (sections.Count == 0) return null;
        var threshold = activationOffset + 1;
        var rowTop = double.NegativeInfinity;
        foreach (var section in sections)
            if (frames.TryGetValue(section.Id, out var frame) && frame.MinY <= threshold && frame.MinY > rowTop) rowTop = frame.MinY;
        if (double.IsNegativeInfinity(rowTop)) return sections[0].Id;
        foreach (var section in sections)
            if (frames.TryGetValue(section.Id, out var frame) && frame.MinY <= threshold && frame.MinY >= rowTop - RowTolerance) return section.Id;
        return sections[0].Id;
    }
}
#endregion

#region Tracker
/// <summary>Jump phase.</summary>
public enum QuickLinkPhase
{
    /// <summary>Active follows scroll position.</summary>
    Idle,
    /// <summary>A jump's scroll is animating.</summary>
    Scrolling,
    /// <summary>The jump landed; the target owns "active" until the reader scrolls away.</summary>
    Owned,
}

/// <summary>
/// Active-section state machine: natural tracking plus jump ownership, so a target stays highlighted while the scroll
/// animates and after it lands, even near the end of the content (web <c>usePageQuickLinks.ts:281-493</c>).
/// </summary>
public sealed class QuickLinkTracker
{
    /// <summary>Current phase.</summary>
    public QuickLinkPhase Phase { get; private set; }

    /// <summary>Jump target while scrolling or owned.</summary>
    public string? Target { get; private set; }

    /// <summary>Landing top of an owned target.</summary>
    public double AnchorMinY { get; private set; }

    /// <summary>Whether an owned target that could not reach the top stays active while visible.</summary>
    public bool LockWhileVisible { get; private set; }

    /// <summary>The section to highlight.</summary>
    public string? ActiveId { get; private set; }

    /// <summary>Begins a jump; the target is active immediately.</summary>
    /// <param name="id">Target.</param>
    public void BeginJump(string id)
    {
        Phase = QuickLinkPhase.Scrolling;
        Target = id;
        ActiveId = id;
    }

    /// <summary>The jump's scroll finished (or Reduce Motion skipped the animation).</summary>
    /// <param name="sections">Sections.</param>
    /// <param name="frames">Frames.</param>
    /// <param name="viewportHeight">Viewport height.</param>
    /// <param name="activationOffset">Activation offset.</param>
    public void Settle(IReadOnlyList<QuickLinkSection> sections, IReadOnlyDictionary<string, QuickLinkFrame> frames, double viewportHeight,
        double activationOffset = QuickLinks.DefaultActivationOffset)
    {
        if (Phase != QuickLinkPhase.Scrolling || Target is not { } target) return;
        if (!sections.Any(s => s.Id == target) || !frames.TryGetValue(target, out var frame) || !QuickLinks.IsVisible(frame, viewportHeight))
        {
            Release(QuickLinks.NaturalActive(sections, frames, activationOffset));
            return;
        }
        Phase = QuickLinkPhase.Owned;
        AnchorMinY = frame.MinY;
        LockWhileVisible = frame.MinY > activationOffset + QuickLinks.CompleteThreshold;
        ActiveId = target;
    }

    /// <summary>Re-resolves the active section after scrolling or a section change.</summary>
    /// <param name="sections">Sections.</param>
    /// <param name="frames">Frames.</param>
    /// <param name="viewportHeight">Viewport height.</param>
    /// <param name="activationOffset">Activation offset.</param>
    public void Update(IReadOnlyList<QuickLinkSection> sections, IReadOnlyDictionary<string, QuickLinkFrame> frames, double viewportHeight,
        double activationOffset = QuickLinks.DefaultActivationOffset)
    {
        var natural = QuickLinks.NaturalActive(sections, frames, activationOffset);
        var target = Target;
        switch (Phase)
        {
            case QuickLinkPhase.Scrolling:
                if (sections.Any(s => s.Id == target)) ActiveId = target;
                else Release(natural);
                return;
            case QuickLinkPhase.Owned:
                if (!sections.Any(s => s.Id == target) || !frames.TryGetValue(target!, out var frame))
                {
                    Release(natural);
                    return;
                }
                var visible = QuickLinks.IsVisible(frame, viewportHeight);
                if (LockWhileVisible)
                {
                    if (visible) ActiveId = target;
                    else Release(natural);
                }
                else if ((visible && Math.Abs(frame.MinY - AnchorMinY) <= QuickLinks.CompleteThreshold) ||
                         QuickLinks.IsReachable(frame, activationOffset))
                {
                    ActiveId = target;
                }
                else
                {
                    Release(natural);
                }
                return;
            default:
                ActiveId = natural;
                return;
        }
    }

    /// <summary>Drops ownership, falling back to the natural section.</summary>
    /// <param name="natural">Natural active ID.</param>
    private void Release(string? natural)
    {
        Phase = QuickLinkPhase.Idle;
        Target = null;
        ActiveId = natural;
    }
}
#endregion
