using Festival.App.Services;
using Festival.Core.ViewModels;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.UI.ViewManagement;

namespace Festival.App.Controls;

#region Anchor attached property
/// <summary>Marks an element as a Quick Links section anchor: <c>controls:QuickLinkAnchor.Id="app-settings"</c>.</summary>
public static class QuickLinkAnchor
{
    /// <summary>Section ID attached property.</summary>
    public static readonly DependencyProperty IdProperty =
        DependencyProperty.RegisterAttached("Id", typeof(string), typeof(QuickLinkAnchor), new PropertyMetadata(null));

    /// <summary>Reads the section ID.</summary>
    /// <param name="element">Element.</param>
    /// <returns>ID or <see langword="null"/>.</returns>
    public static string? GetId(DependencyObject element) => (string?)element.GetValue(IdProperty);

    /// <summary>Sets the section ID.</summary>
    /// <param name="element">Element.</param>
    /// <param name="value">ID.</param>
    public static void SetId(DependencyObject element, string? value) => element.SetValue(IdProperty, value);
}
#endregion

#region Binder
/// <summary>
/// Connects a page <see cref="ScrollViewer"/> to a <see cref="QuickLinksViewModel"/>: measures anchors only when the
/// view changes (no per-frame work while idle), reports frames, and scrolls on jump requests (instant under reduced
/// motion). Anchors are found once per load by <see cref="QuickLinkAnchor"/>.
/// </summary>
public sealed class QuickLinksBinder
{
    /// <summary>Gap kept above a jump target (below the page header).</summary>
    private const double LandingMargin = 8;

    private readonly ScrollViewer scroller;
    private readonly QuickLinksViewModel model;
    private readonly Dictionary<string, FrameworkElement> anchors = [];

    /// <summary>Jump target still being settled, or <see langword="null"/>.</summary>
    private FrameworkElement? landing;

    /// <summary>Section ID of <see cref="landing"/>.</summary>
    private string? landingId;

    /// <summary>Re-aims left for <see cref="landing"/>.</summary>
    private int corrections;

    /// <summary>Repeaters whose realization changes mark <see cref="anchors"/> stale.</summary>
    private readonly HashSet<ItemsRepeater> watched = [];

    /// <summary>Whether a repeater realized or recycled a section since the last <see cref="Collect"/>.</summary>
    private bool stale;

    /// <summary>Attaches to a scroller.</summary>
    /// <param name="scroller">Page scroller.</param>
    /// <param name="model">Quick Links model.</param>
    /// <param name="reduceMotion">Kept for callers; jumps are always instant now (operator batch 7.15).</param>
    public QuickLinksBinder(ScrollViewer scroller, QuickLinksViewModel model, Func<bool> reduceMotion)
    {
        this.scroller = scroller;
        this.model = model;
        _ = reduceMotion;
        scroller.ViewChanged += (_, e) => OnViewChanged(!e.IsIntermediate);
        scroller.SizeChanged += (_, _) => Report(false);
        scroller.Loaded += (_, _) =>
        {
            Collect();
            Report(false);
        };
        model.JumpRequested += (_, id) => Jump(id);
    }

    /// <summary>
    /// Returns the live element for a repeater-owned section, realizing it if needed (a virtualized card far below the
    /// viewport), e.g. <c>ItemsRepeater.GetOrCreateElement</c>; <see langword="null"/> for other sections.
    /// </summary>
    public Func<string, FrameworkElement?>? Resolve { get; set; }

    /// <summary>Whether Windows or the app asks for reduced motion.</summary>
    /// <param name="appReduceMotion">In-app override.</param>
    /// <returns><see langword="true"/> when animations should be skipped.</returns>
    public static bool ReducedMotion(bool appReduceMotion) => appReduceMotion || !new UISettings().AnimationsEnabled;

    /// <summary>Re-reads anchors (call after sections appear or disappear).</summary>
    public void Collect()
    {
        anchors.Clear();
        stale = false;
        if (scroller.Content is DependencyObject root) Walk(root);
    }

    /// <summary>Re-reads anchors and reports their frames (after data-driven sections were laid out).</summary>
    public void Refresh()
    {
        Collect();
        Report(false);
    }

    /// <summary>Measures anchors and reports them.</summary>
    /// <param name="isFinal">Whether scrolling came to rest.</param>
    private void Report(bool isFinal)
    {
        if (anchors.Count == 0 || stale) Collect();
        var frames = new Dictionary<string, QuickLinkFrame>();
        foreach (var (id, element) in anchors)
        {
            if (QuickLinkAnchor.GetId(element) != id || element.Visibility != Visibility.Visible || element.ActualHeight <= 0) continue;
            var top = element.TransformToVisual(scroller).TransformPoint(default).Y;
            frames[id] = new QuickLinkFrame(top, top + element.ActualHeight);
        }
        model.ReportLayout(frames, scroller.ViewportHeight, isFinal);
    }

    /// <summary>Scrolls a section to the top of the viewport.</summary>
    /// <param name="id">Section.</param>
    private void Jump(string id)
    {
        if (anchors.Count == 0 || stale) Collect();
        landing = null;
        landingId = id;
        corrections = QuickLinks.MaxJumpCorrections;
        // Repeater-owned sections go through the repeater: a recycled element can still carry an old anchor ID, and a
        // just-realized one has no position until the repeater arranges it.
        if (Resolve?.Invoke(id) is { } realized)
        {
            landing = realized;
            realized.StartBringIntoView(new BringIntoViewOptions
            {
                VerticalAlignmentRatio = 0,
                VerticalOffset = -LandingMargin,
                // Operator batch 7.15: Quick Links teleport rather than animate the scroll.
                AnimationDesired = false,
            });
            Land(realized, id);
            // Settles the jump even when the section was already in place (no view change follows).
            scroller.DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, CheckLanding);
            return;
        }
        if (!anchors.TryGetValue(id, out var element)) return;
        Land(element, id);
        landing = element;
        if (!Aim(element))
        {
            landing = null;
            Report(true);
        }
    }

    /// <summary>Scrolls toward an anchor's current position.</summary>
    /// <param name="element">Anchor.</param>
    /// <returns><see langword="false"/> when already there (no view change will follow).</returns>
    private bool Aim(FrameworkElement element)
    {
        var top = element.TransformToVisual(scroller).TransformPoint(default).Y;
        var target = QuickLinks.JumpOffset(scroller.VerticalOffset, top, scroller.ScrollableHeight, LandingMargin);
        if (QuickLinks.IsLanded(scroller.VerticalOffset, target)) return false;
        return scroller.ChangeView(null, target, null, disableAnimation: true);
    }

    /// <summary>
    /// Handles a view change. Section positions below or inside a virtualizing <c>ItemsRepeater</c> (profile
    /// instruments and Bands) are first measured against the repeater's estimated card heights; once the jump settles,
    /// the cards around the new viewport are realized and the page extent changes, moving the target (or clamping the
    /// offset at the end). Until the target has landed, rest events report as intermediate so the jump is not settled
    /// (and released) on a stale position.
    /// </summary>
    /// <param name="isFinal">Whether scrolling came to rest.</param>
    private void OnViewChanged(bool isFinal)
    {
        if (landing is null || !isFinal)
        {
            Report(isFinal);
            return;
        }
        Report(false);
        scroller.DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, CheckLanding);
    }

    /// <summary>
    /// Lays the page out, re-measures the pending jump target and re-aims (bounded by
    /// <see cref="QuickLinks.MaxJumpCorrections"/>); once it rests on the target, settles the jump.
    /// </summary>
    private void CheckLanding()
    {
        if (landing is not { } element) return;
        scroller.UpdateLayout();
        if (corrections-- > 0 && IsLive(element, landingId) && Aim(element)) return;
        landing = null;
        Report(true);
    }

    /// <summary>Whether an anchor element still shows the given section (not unloaded, pooled or recycled).</summary>
    /// <param name="element">Anchor element.</param>
    /// <param name="id">Section ID.</param>
    /// <returns><see langword="true"/> while it can be measured for that section.</returns>
    private static bool IsLive(FrameworkElement element, string? id) =>
        element.IsLoaded && QuickLinkAnchor.GetId(element) == id && !IsPooled(element);

    /// <summary>Whether an element is a repeater child kept for reuse rather than showing an item.</summary>
    /// <param name="element">Element.</param>
    /// <returns><see langword="true"/> for a pooled repeater element.</returns>
    private static bool IsPooled(FrameworkElement element) =>
        VisualTreeHelper.GetParent(element) is ItemsRepeater owner && owner.GetElementIndex(element) < 0;
    /// <summary>
    /// Like a web skip link, a jump moves keyboard focus to the section's first focusable element and tells Narrator
    /// which section it reached (a scroll alone is silent and leaves focus on the menu or pane).
    /// </summary>
    /// <param name="target">Section element.</param>
    /// <param name="id">Section ID.</param>
    private void Land(FrameworkElement target, string id)
    {
        var title = model.Items.FirstOrDefault(i => i.Section.Id == id)?.Section.AccessibleTitle;
        target.DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, () =>
        {
            if (FocusManager.FindFirstFocusableElement(target) is UIElement first) first.Focus(FocusState.Programmatic);
            if (title is { Length: > 0 }) ScreenReader.Announce(target, new Announcement($"{title} section", AnnouncementKind.Completed));
        });
    }

    /// <summary>Finds anchors in the content tree.</summary>
    /// <param name="node">Node.</param>
    private void Walk(DependencyObject node)
    {
        if (node is ItemsRepeater repeater && watched.Add(repeater))
        {
            // Sections realized or recycled after the first walk change which element carries which ID.
            repeater.ElementPrepared += (_, _) => stale = true;
            repeater.ElementClearing += (_, _) => stale = true;
        }
        if (node is FrameworkElement element)
        {
            // A pooled repeater element still carries the ID of the section it showed last.
            if (IsPooled(element)) return;
            if (QuickLinkAnchor.GetId(element) is { Length: > 0 } id) anchors[id] = element;
        }
        var count = VisualTreeHelper.GetChildrenCount(node);
        for (var i = 0; i < count; i++) Walk(VisualTreeHelper.GetChild(node, i));
    }
}
#endregion
