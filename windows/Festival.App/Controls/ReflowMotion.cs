using System.Numerics;
using System.Runtime.CompilerServices;
using Festival.App.Services;
using Festival.Core.Domain;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Reflow motion
/// <summary>
/// Layout reflow motion (pattern <c>reflow-motion</c>, issue #669), the one place Windows animates content that a layout
/// change moved: a card that a column change put somewhere else glides from where it was to its new place (a composition
/// <c>Translation</c> from the old-minus-new offset to zero, so layout itself is never animated), and a card that the
/// change brought into view fades in. Timing is <see cref="ReflowTiming"/>. A card whose load stagger
/// (<see cref="FadeIn"/>) is still running is left to finish it; a move interrupted by another reflow starts from where the
/// card is drawn now. With motion off (<see cref="Motion.Allowed"/>) nothing animates, and turning motion off (Windows
/// Animation effects or the app's Reduce Motion) while glides or fades run stops every one of them in its settled state
/// (R4): only while any runs is <see cref="Motion.Changed"/> observed.
/// Run it only on reflow events (column changes, split open/close), never per scroll frame (Windows gotcha #642).
/// </summary>
public static class ReflowMotion
{
    private const string Translation = "Translation";
    private const string Opacity = "Opacity";

    /// <summary>
    /// A whole reflow's run time: <see cref="ReflowTiming.Duration"/>, or the Debug/automation
    /// <c>FST_DEBUG_REFLOW_MS</c> stretch so UI Automation can change a motion setting mid-move.
    /// </summary>
    public static readonly TimeSpan Duration = ReflowTiming.ParseDuration(App.LaunchEnvironment("FST_DEBUG_REFLOW_MS")) ?? ReflowTiming.Duration;

    /// <summary>Running moves: the starting shift and when it began, so an interrupted move can carry on.</summary>
    private static readonly ConditionalWeakTable<UIElement, MoveState> Moves = new();

    /// <summary>Glides and fades that may still be running, with when each ends (<see cref="FadeIn.Now"/> time).</summary>
    private static readonly List<(WeakReference<UIElement> Element, TimeSpan Ends)> Running = [];

    /// <summary>Whether <see cref="OnMotionChanged"/> is subscribed (only while <see cref="Running"/> has entries).</summary>
    private static bool observing;

    #region Single elements
    /// <summary>Glides an element that layout just moved by <paramref name="shift"/> (old minus new position) back into place.</summary>
    /// <param name="element">Laid-out element at its new position.</param>
    /// <param name="shift">Old position minus new position, in epx.</param>
    /// <returns><see langword="true"/> when a move started.</returns>
    public static bool Move(UIElement element, Point shift)
    {
        if (!Motion.Allowed)
        {
            Stop(element);
            return false;
        }
        if (FadeIn.IsPlaying(element)) return false;
        var now = FadeIn.Now;
        var from = new Vector2((float)shift.X, (float)shift.Y);
        // Interrupted: the card is still drawn part of the way along its previous move.
        if (Moves.TryGetValue(element, out var running)) from += running.Offset(now);
        if (!ReflowTiming.Moves(from.X, from.Y))
        {
            Stop(element);
            return false;
        }
        var visual = ElementCompositionPreview.GetElementVisual(element);
        ElementCompositionPreview.SetIsTranslationEnabled(element, true);
        var move = visual.Compositor.CreateVector3KeyFrameAnimation();
        move.InsertKeyFrame(0f, new Vector3(from, 0));
        move.InsertKeyFrame(1f, Vector3.Zero, Ease(visual.Compositor));
        move.Duration = Duration;
        visual.StartAnimation(Translation, move);
        Moves.AddOrUpdate(element, new MoveState(from, now));
        Track(element, now);
        return true;
    }

    /// <summary>Fades in an element that a reflow brought into view.</summary>
    /// <param name="element">Element.</param>
    /// <returns><see langword="true"/> when a fade started.</returns>
    public static bool Enter(UIElement element)
    {
        if (!Motion.Allowed || FadeIn.IsPlaying(element)) return false;
        var visual = ElementCompositionPreview.GetElementVisual(element);
        var fade = visual.Compositor.CreateScalarKeyFrameAnimation();
        fade.InsertKeyFrame(0f, 0f);
        fade.InsertKeyFrame(1f, 1f, Ease(visual.Compositor));
        fade.Duration = Duration;
        visual.StartAnimation(Opacity, fade);
        Track(element, FadeIn.Now);
        return true;
    }

    /// <summary>Stops a running move and shows the element in place.</summary>
    /// <param name="element">Element.</param>
    public static void Stop(UIElement element)
    {
        if (!Moves.TryGetValue(element, out _)) return;
        Moves.Remove(element);
        var visual = ElementCompositionPreview.GetElementVisual(element);
        visual.StopAnimation(Translation);
        visual.Properties.InsertVector3(Translation, Vector3.Zero);
    }

    /// <summary>Records a glide or fade that runs until <see cref="Duration"/> after <paramref name="now"/> (R4).</summary>
    /// <param name="element">Animated element.</param>
    /// <param name="now">When it started.</param>
    private static void Track(UIElement element, TimeSpan now)
    {
        Running.RemoveAll(r => r.Ends <= now || !r.Element.TryGetTarget(out var other) || ReferenceEquals(other, element));
        Running.Add((new WeakReference<UIElement>(element), now + Duration));
        if (observing) return;
        observing = true;
        Motion.Changed += OnMotionChanged;
    }

    /// <summary>
    /// Motion turned off mid-reflow (R4): every glide and fade still running stops where it was heading, so cards are
    /// drawn in their laid-out places at full opacity at once. Stops observing once nothing runs.
    /// </summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private static void OnMotionChanged(object? sender, EventArgs e)
    {
        var now = FadeIn.Now;
        if (Motion.Allowed)
        {
            Running.RemoveAll(r => r.Ends <= now || !r.Element.TryGetTarget(out _));
            if (Running.Count == 0) StopObserving();
            return;
        }
        var stopped = 0;
        foreach (var (reference, ends) in Running)
        {
            if (ends <= now || !reference.TryGetTarget(out var element)) continue;
            Moves.Remove(element);
            var visual = ElementCompositionPreview.GetElementVisual(element);
            visual.StopAnimation(Translation);
            visual.StopAnimation(Opacity);
            visual.Properties.InsertVector3(Translation, Vector3.Zero);
            visual.Opacity = 1;
            stopped++;
        }
        Running.Clear();
        StopObserving();
        if (stopped > 0 && PerfLog.Enabled)
            PerfLog.Write(FormattableString.Invariant($"reflow-stop stopped={stopped} motion=0 t={now.TotalMilliseconds:F0}"));
    }

    /// <summary>Unsubscribes from <see cref="Motion.Changed"/>.</summary>
    private static void StopObserving()
    {
        if (!observing) return;
        observing = false;
        Motion.Changed -= OnMotionChanged;
    }

    /// <summary>The reflow curve on a compositor.</summary>
    /// <param name="compositor">Compositor.</param>
    /// <returns>Easing.</returns>
    private static CubicBezierEasingFunction Ease(Compositor compositor)
    {
        var (x1, y1, x2, y2) = ReflowTiming.Spline;
        return compositor.CreateCubicBezierEasingFunction(new Vector2(x1, y1), new Vector2(x2, y2));
    }

    /// <summary>A running move.</summary>
    /// <param name="From">Starting shift.</param>
    /// <param name="Start">When it began (<see cref="FadeIn.Now"/>).</param>
    private sealed record MoveState(Vector2 From, TimeSpan Start)
    {
        /// <summary>Where the move draws the element at <paramref name="now"/>, relative to its laid-out place.</summary>
        /// <param name="now">Monotonic time.</param>
        /// <returns>Offset.</returns>
        public Vector2 Offset(TimeSpan now) => From * (float)ReflowTiming.Remaining(now - Start, Duration);
    }
    #endregion

    #region Split panes
    /// <summary>
    /// Moves a split pane from <paramref name="from"/> to <paramref name="to"/> open on the compositor (the layout is
    /// already final): the pane slides by <see cref="ReflowTiming.PaneOffset"/> toward its trailing edge and its opacity
    /// follows its progress. A closing pane (<paramref name="list"/> given) uncovers the widened list behind its leading
    /// edge with an animated clip, so the list never shows through the leaving pane.
    /// </summary>
    /// <param name="pane">The pane, laid out in its final place.</param>
    /// <param name="list">The list to uncover as the pane leaves, or <see langword="null"/> when the pane opens.</param>
    /// <param name="paneWidth">The pane's width in epx.</param>
    /// <param name="from">Progress the pane is drawn at now (0 closed, 1 open).</param>
    /// <param name="to">Target progress.</param>
    /// <param name="duration">Run time (<see cref="ReflowTiming.Plan"/>).</param>
    /// <returns>A batch that completes when the move ends or is replaced.</returns>
    public static CompositionScopedBatch SlidePane(UIElement pane, UIElement list, double paneWidth, double from, double to, TimeSpan duration)
    {
        var visual = ElementCompositionPreview.GetElementVisual(pane);
        ElementCompositionPreview.SetIsTranslationEnabled(pane, true);
        var compositor = visual.Compositor;
        var ease = Ease(compositor);
        var batch = compositor.CreateScopedBatch(CompositionBatchTypes.Animation);
        var slide = compositor.CreateVector3KeyFrameAnimation();
        slide.InsertKeyFrame(0f, new Vector3((float)ReflowTiming.PaneOffset(paneWidth, from), 0, 0));
        slide.InsertKeyFrame(1f, new Vector3((float)ReflowTiming.PaneOffset(paneWidth, to), 0, 0), ease);
        slide.Duration = duration;
        visual.StartAnimation(Translation, slide);
        var fade = compositor.CreateScalarKeyFrameAnimation();
        fade.InsertKeyFrame(0f, (float)from);
        fade.InsertKeyFrame(1f, (float)to, ease);
        fade.Duration = duration;
        visual.StartAnimation(Opacity, fade);
        var listVisual = ElementCompositionPreview.GetElementVisual(list);
        if (to < from)
        {
            var clip = listVisual.Clip as InsetClip ?? compositor.CreateInsetClip();
            listVisual.Clip = clip;
            var uncover = compositor.CreateScalarKeyFrameAnimation();
            uncover.InsertKeyFrame(0f, (float)(paneWidth - ReflowTiming.PaneOffset(paneWidth, from)));
            uncover.InsertKeyFrame(1f, (float)(paneWidth - ReflowTiming.PaneOffset(paneWidth, to)), ease);
            uncover.Duration = duration;
            clip.StartAnimation(nameof(InsetClip.RightInset), uncover);
        }
        else listVisual.Clip = null;
        batch.End();
        return batch;
    }

    /// <summary>Stops a pane move and draws the pane in place, fully opaque, with the list unclipped.</summary>
    /// <param name="pane">The pane.</param>
    /// <param name="list">The list.</param>
    public static void SettlePane(UIElement pane, UIElement list)
    {
        var visual = ElementCompositionPreview.GetElementVisual(pane);
        visual.StopAnimation(Translation);
        visual.StopAnimation(Opacity);
        visual.Properties.InsertVector3(Translation, Vector3.Zero);
        visual.Opacity = 1;
        var listVisual = ElementCompositionPreview.GetElementVisual(list);
        if (listVisual.Clip is InsetClip clip) clip.StopAnimation(nameof(InsetClip.RightInset));
        listVisual.Clip = null;
    }
    #endregion

    #region Keyed reflows
    /// <summary>
    /// Records where each realized card sits in a viewport before a reflow that replaces or re-chunks its elements
    /// (Suggestions' lines, the Item Shop grid), keyed by the item it shows.
    /// </summary>
    /// <param name="viewport">The scrolling viewport positions are measured in.</param>
    /// <param name="cards">Realized cards and their items.</param>
    /// <returns>Positions by item.</returns>
    public static Dictionary<object, Point> Capture(FrameworkElement viewport, IEnumerable<(object Key, FrameworkElement Element)> cards)
    {
        var positions = new Dictionary<object, Point>();
        foreach (var (key, element) in cards)
        {
            if (element.ActualWidth <= 0) continue;
            var at = Position(element, viewport);
            // Recycled containers a list parks far outside its viewport are not where any card was drawn.
            if (ReflowTiming.Near(at.Y, element.ActualHeight, viewport.ActualHeight)) positions[key] = at;
        }
        return positions;
    }

    /// <summary>
    /// After the reflow's layout: cards that were shown before glide from their old place and cards that were not fade
    /// in; only cards in or passing through the viewport animate.
    /// </summary>
    /// <param name="viewport">The viewport <see cref="Capture"/> measured in.</param>
    /// <param name="before">Positions from <see cref="Capture"/>.</param>
    /// <param name="cards">The realized cards now.</param>
    /// <param name="host">Trace name (<c>--perf-log</c>).</param>
    /// <returns>Cards moved and faded in.</returns>
    public static (int Moved, int Entered) Play(FrameworkElement viewport, IReadOnlyDictionary<object, Point> before,
        IEnumerable<(object Key, FrameworkElement Element)> cards, string host)
    {
        int moved = 0, entered = 0;
        var motion = Motion.Allowed;
        if (motion)
        {
            var height = viewport.ActualHeight;
            foreach (var (key, element) in cards)
            {
                if (element.ActualWidth <= 0) continue;
                var now = Position(element, viewport);
                if (!ReflowTiming.Near(now.Y, element.ActualHeight, height)) continue;
                var inView = ReflowTiming.InView(now.Y, element.ActualHeight, height);
                if (before.TryGetValue(key, out var was))
                {
                    if ((inView || ReflowTiming.InView(was.Y, element.ActualHeight, height))
                        && Move(element, new Point(was.X - now.X, was.Y - now.Y))) moved++;
                }
                else if (inView && Enter(element)) entered++;
            }
        }
        Trace(host, moved, entered, motion);
        return (moved, entered);
    }

    /// <summary>
    /// <see cref="Play"/> once the layout pass running now has placed the cards: a reflow decided in a
    /// <c>SizeChanged</c> handler is laid out later in the same pass (<c>UpdateLayout</c> there does nothing), and
    /// <c>LayoutUpdated</c> still comes before that frame renders, so no card is ever drawn at its new place first.
    /// </summary>
    /// <param name="viewport">The viewport <see cref="Capture"/> measured in.</param>
    /// <param name="before">Positions from <see cref="Capture"/>.</param>
    /// <param name="cards">Reads the realized cards after layout.</param>
    /// <param name="host">Trace name (<c>--perf-log</c>).</param>
    public static void PlayAfterLayout(FrameworkElement viewport, IReadOnlyDictionary<object, Point> before,
        Func<IEnumerable<(object Key, FrameworkElement Element)>> cards, string host)
    {
        EventHandler<object>? played = null;
        played = (_, _) =>
        {
            viewport.LayoutUpdated -= played;
            Play(viewport, before, cards(), host);
        };
        viewport.LayoutUpdated += played;
    }

    /// <summary>
    /// Keeps keyboard focus on the same control through a reflow that recreates a host's elements (Suggestions' lines):
    /// when the list recycles the focused control's container and moves focus out of the host (to the window's first
    /// control) within <see cref="FocusWindow"/>, focus goes to the control that now shows the same test ID instead. A
    /// move the user makes (Tab, a click) or one into the host is left alone. Motion has no effect on this.
    /// </summary>
    /// <param name="host">Element whose descendants the reflow recreates.</param>
    public static void KeepFocus(FrameworkElement host)
    {
        if (host.XamlRoot is not { } root || FocusManager.GetFocusedElement(root) is not Control focused) return;
        var id = AutomationProperties.GetAutomationId(focused);
        if (string.IsNullOrEmpty(id) || !IsInside(focused, host)) return;
        var started = FadeIn.Now;
        TypedEventHandler<UIElement, LosingFocusEventArgs>? losing = null;
        losing = (_, e) =>
        {
            focused.LosingFocus -= losing;
            if (FadeIn.Now - started > FocusWindow || e.FocusState != FocusState.Programmatic) return;
            if (e.NewFocusedElement is { } next && IsInside(next, host)) return;
            if (Find(host, id, focused) is { } target) e.TrySetNewFocusedElement(target);
        };
        focused.LosingFocus += losing;
    }

    /// <summary>How long after a reflow a programmatic focus move out of its host counts as the reflow's.</summary>
    private static readonly TimeSpan FocusWindow = TimeSpan.FromSeconds(1);

    /// <summary>Whether an element is inside a host's visual tree.</summary>
    /// <param name="element">Element.</param>
    /// <param name="host">Host.</param>
    /// <returns><see langword="true"/> when <paramref name="host"/> is an ancestor (or the element).</returns>
    private static bool IsInside(DependencyObject element, DependencyObject host)
    {
        for (var at = element; at is not null; at = VisualTreeHelper.GetParent(at))
            if (ReferenceEquals(at, host)) return true;
        return false;
    }

    /// <summary>The first focusable descendant with a test ID (a walk of the realized tree, once per reflow).</summary>
    /// <param name="root">Where to look.</param>
    /// <param name="id">Automation ID.</param>
    /// <param name="except">The recycled control that is losing focus.</param>
    /// <returns>Control, or <see langword="null"/>.</returns>
    private static Control? Find(DependencyObject root, string id, Control except)
    {
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < count; i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is Control { IsTabStop: true } control && !ReferenceEquals(control, except)
                && AutomationProperties.GetAutomationId(control) == id) return control;
            if (Find(child, id, except) is { } found) return found;
        }
        return null;
    }

    /// <summary>An element's top-left in a viewport (one transform per card, per reflow event).</summary>
    /// <param name="element">Element.</param>
    /// <param name="viewport">Viewport.</param>
    /// <returns>Position.</returns>
    private static Point Position(UIElement element, UIElement viewport) => element.TransformToVisual(viewport).TransformPoint(default);
    #endregion

    #region Trace
    /// <summary>Writes one reflow's outcome for the reflow journey (<c>--perf-log</c> only).</summary>
    /// <param name="host">Which layout reflowed.</param>
    /// <param name="moved">Cards that glide.</param>
    /// <param name="entered">Cards that fade in.</param>
    /// <param name="motion">Whether motion was allowed.</param>
    public static void Trace(string host, int moved, int entered, bool motion)
    {
        if (!PerfLog.Enabled) return;
        PerfLog.Write(FormattableString.Invariant(
            $"reflow-move host={host} moved={moved} entered={entered} motion={(motion ? 1 : 0)} t={FadeIn.Now.TotalMilliseconds:F0}"));
    }
    #endregion
}
#endregion
