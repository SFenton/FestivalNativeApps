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
    private readonly Func<bool> reduceMotion;
    private readonly Dictionary<string, FrameworkElement> anchors = [];

    /// <summary>Attaches to a scroller.</summary>
    /// <param name="scroller">Page scroller.</param>
    /// <param name="model">Quick Links model.</param>
    /// <param name="reduceMotion">Whether jumps skip the scroll animation (system or in-app).</param>
    public QuickLinksBinder(ScrollViewer scroller, QuickLinksViewModel model, Func<bool> reduceMotion)
    {
        this.scroller = scroller;
        this.model = model;
        this.reduceMotion = reduceMotion;
        scroller.ViewChanged += (_, e) => Report(!e.IsIntermediate);
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
        if (anchors.Count == 0) Collect();
        var frames = new Dictionary<string, QuickLinkFrame>();
        foreach (var (id, element) in anchors)
        {
            if (element.Visibility != Visibility.Visible || element.ActualHeight <= 0) continue;
            var top = element.TransformToVisual(scroller).TransformPoint(default).Y;
            frames[id] = new QuickLinkFrame(top, top + element.ActualHeight);
        }
        model.ReportLayout(frames, scroller.ViewportHeight, isFinal);
    }

    /// <summary>Scrolls a section to the top of the viewport.</summary>
    /// <param name="id">Section.</param>
    private void Jump(string id)
    {
        if (anchors.Count == 0) Collect();
        // Repeater-owned sections go through the repeater: a recycled element can still carry an old anchor ID, and a
        // just-realized one has no position until the repeater arranges it.
        if (Resolve?.Invoke(id) is { } realized)
        {
            realized.StartBringIntoView(new BringIntoViewOptions
            {
                VerticalAlignmentRatio = 0,
                VerticalOffset = -LandingMargin,
                AnimationDesired = !reduceMotion(),
            });
            Land(realized, id);
            return;
        }
        if (!anchors.TryGetValue(id, out var element)) return;
        Land(element, id);
        var top = element.TransformToVisual(scroller).TransformPoint(default).Y;
        var target = Math.Clamp(scroller.VerticalOffset + top - LandingMargin, 0, scroller.ScrollableHeight);
        if (Math.Abs(target - scroller.VerticalOffset) < 0.5)
        {
            Report(true);
        }
        else
        {
            scroller.ChangeView(null, target, null, reduceMotion());
        }
    }

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
        if (node is FrameworkElement element && QuickLinkAnchor.GetId(element) is { Length: > 0 } id) anchors[id] = element;
        var count = VisualTreeHelper.GetChildrenCount(node);
        for (var i = 0; i < count; i++) Walk(VisualTreeHelper.GetChild(node, i));
    }
}
#endregion
