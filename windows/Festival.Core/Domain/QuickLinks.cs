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

    /// <summary>A section is naturally active once its top is within this many epx of the viewport top.</summary>
    public const double DefaultActivationOffset = 16;

    /// <summary>After a jump the target stays active while its top is within this band of the landing line.</summary>
    public const double ReachableBand = 96;

    /// <summary>Scroll drift tolerated before a settled jump releases ownership.</summary>
    public const double CompleteThreshold = 8;

    /// <summary>Windows width (epx) at which the persistent jump pane replaces the menu (web rail breakpoint).</summary>
    public const double PaneMinimumWidth = 1440;

    /// <summary>Whether a page shows its entry point.</summary>
    /// <param name="sectionCount">Section count.</param>
    /// <returns><see langword="true"/> for two or more.</returns>
    public static bool IsAvailable(int sectionCount) => sectionCount >= MinimumSectionCount;

    /// <summary>Whether the wide persistent pane is used rather than the menu.</summary>
    /// <param name="windowWidth">Window width in epx.</param>
    /// <returns><see langword="true"/> at 1440 epx and wider.</returns>
    public static bool UsesPane(double windowWidth) => windowWidth >= PaneMinimumWidth;

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

    /// <summary>
    /// The section a reader is "in": the last (display order) whose top crossed the activation line; unknown frames are
    /// skipped; with none past the line, the first.
    /// </summary>
    /// <param name="sections">Display-ordered sections.</param>
    /// <param name="frames">Known frames by ID.</param>
    /// <param name="activationOffset">Activation line below the viewport top.</param>
    /// <returns>Active ID, or <see langword="null"/> with no sections.</returns>
    public static string? NaturalActive(
        IReadOnlyList<QuickLinkSection> sections, IReadOnlyDictionary<string, QuickLinkFrame> frames, double activationOffset = DefaultActivationOffset)
    {
        if (sections.Count == 0) return null;
        var active = sections[0].Id;
        var threshold = activationOffset + 1;
        foreach (var section in sections)
        {
            if (!frames.TryGetValue(section.Id, out var frame)) continue;
            if (frame.MinY > threshold) break;
            active = section.Id;
        }
        return active;
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
