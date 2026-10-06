using System.Diagnostics;
using System.Numerics;
using Festival.App.Services;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Fade in
/// <summary>
/// The web's <c>fadeInUp</c> for native content (<see cref="FadeInTiming"/>: 400 ms ease-out from opacity 0 and 12 epx
/// lower). <c>FadeIn.OnShow</c> fades an element each time it becomes visible (page content bound to a loaded state);
/// <c>FadeIn.Stagger</c> on an <see cref="ItemsRepeater"/> or <see cref="ListViewBase"/> fades the rows realized just
/// after its items change, 125 ms apart, for the rows that fit the viewport; the first scroll movement after a load closes
/// that window (<see cref="StaggerArm"/>, pattern <c>load-transition</c> R5), so rows realized by scrolling just appear,
/// as on the web. <see cref="Restagger(UIElement, int)"/> re-arms it for an appended batch only, which scrolling reveals
/// (Suggestions). Both run on
/// the compositor, leave nothing running when finished, and do nothing while motion is off (<see cref="Motion.Allowed"/>).
/// </summary>
public static class FadeIn
{
    private const string Opacity = "Opacity";
    private const string Translation = "Translation";

    #region OnShow
    /// <summary>Fade the element in when it loads and whenever it turns visible again.</summary>
    public static readonly DependencyProperty OnShowProperty = DependencyProperty.RegisterAttached(
        "OnShow", typeof(bool), typeof(FadeIn), new PropertyMetadata(false, OnShowChanged));

    /// <summary>Gets <c>OnShow</c>.</summary>
    /// <param name="element">Element.</param>
    /// <returns>Whether enabled.</returns>
    public static bool GetOnShow(UIElement element) => (bool)element.GetValue(OnShowProperty);

    /// <summary>Sets <c>OnShow</c>.</summary>
    /// <param name="element">Element.</param>
    /// <param name="value">Whether enabled.</param>
    public static void SetOnShow(UIElement element, bool value) => element.SetValue(OnShowProperty, value);

    /// <summary>Hooks Loaded and Visibility changes once.</summary>
    /// <param name="d">Element.</param>
    /// <param name="e">New value.</param>
    private static void OnShowChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not FrameworkElement element || e.NewValue is not true) return;
        element.Loaded += (_, _) => { if (element.Visibility == Visibility.Visible) Play(element, TimeSpan.Zero); };
        element.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) =>
        {
            if (element.IsLoaded && element.Visibility == Visibility.Visible) Play(element, TimeSpan.Zero);
        });
    }
    #endregion

    #region OnHide
    /// <summary>
    /// Fade the element out when it collapses (a composition implicit hide animation), while motion is on; the pair to
    /// <c>OnShow</c> for controls that must never disappear abruptly (Songs Jump, issue #231).
    /// </summary>
    public static readonly DependencyProperty OnHideProperty = DependencyProperty.RegisterAttached(
        "OnHide", typeof(bool), typeof(FadeIn), new PropertyMetadata(false, OnHideChanged));

    /// <summary>Gets <c>OnHide</c>.</summary>
    /// <param name="element">Element.</param>
    /// <returns>Whether enabled.</returns>
    public static bool GetOnHide(UIElement element) => (bool)element.GetValue(OnHideProperty);

    /// <summary>Sets <c>OnHide</c>.</summary>
    /// <param name="element">Element.</param>
    /// <param name="value">Whether enabled.</param>
    public static void SetOnHide(UIElement element, bool value) => element.SetValue(OnHideProperty, value);

    /// <summary>Re-arms the hide animation on load, on each show and whenever the motion switch may have changed.</summary>
    /// <param name="d">Element.</param>
    /// <param name="e">New value.</param>
    private static void OnHideChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not FrameworkElement element || e.NewValue is not true) return;
        void Refresh(object? sender, EventArgs args) => ArmHide(element);
        element.Loaded += (_, _) =>
        {
            ArmHide(element);
            Motion.Changed -= Refresh;
            Motion.Changed += Refresh;
        };
        element.Unloaded += (_, _) => Motion.Changed -= Refresh;
        element.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) =>
        {
            if (element.Visibility != Visibility.Visible) return;
            // A finished hide fade leaves the visual transparent; OnShow's fade (if any) animates over this.
            ElementCompositionPreview.GetElementVisual(element).Opacity = 1;
            ArmHide(element);
        });
    }

    /// <summary>Sets the implicit hide fade while motion is allowed, and clears it otherwise.</summary>
    /// <param name="element">Element.</param>
    private static void ArmHide(UIElement element)
    {
        if (!Motion.Allowed)
        {
            ElementCompositionPreview.SetImplicitHideAnimation(element, null);
            return;
        }
        var compositor = ElementCompositionPreview.GetElementVisual(element).Compositor;
        var fade = compositor.CreateScalarKeyFrameAnimation();
        fade.Target = Opacity;
        fade.InsertKeyFrame(1f, 0f);
        fade.Duration = FadeInTiming.HideDuration;
        ElementCompositionPreview.SetImplicitHideAnimation(element, fade);
    }
    #endregion

    #region Stagger
    /// <summary>Stagger rows in after the list's items change.</summary>
    public static readonly DependencyProperty StaggerProperty = DependencyProperty.RegisterAttached(
        "Stagger", typeof(bool), typeof(FadeIn), new PropertyMetadata(false, OnStaggerChanged));

    /// <summary>Row height used to estimate how many rows fit (web <c>estimateVisibleCount</c>); default 48 epx.</summary>
    public static readonly DependencyProperty RowHeightProperty = DependencyProperty.RegisterAttached(
        "RowHeight", typeof(double), typeof(FadeIn), new PropertyMetadata(48.0));

    private static readonly DependencyProperty ArmProperty = DependencyProperty.RegisterAttached(
        "Arm", typeof(object), typeof(FadeIn), new PropertyMetadata(null));

    private static readonly DependencyProperty TrackerProperty = DependencyProperty.RegisterAttached(
        "Tracker", typeof(object), typeof(FadeIn), new PropertyMetadata(null));

    private static readonly DependencyProperty AnimatedProperty = DependencyProperty.RegisterAttached(
        "Animated", typeof(bool), typeof(FadeIn), new PropertyMetadata(false));

    /// <summary>Gets <c>Stagger</c>.</summary>
    /// <param name="element">List.</param>
    /// <returns>Whether enabled.</returns>
    public static bool GetStagger(UIElement element) => (bool)element.GetValue(StaggerProperty);

    /// <summary>Sets <c>Stagger</c>.</summary>
    /// <param name="element">List.</param>
    /// <param name="value">Whether enabled.</param>
    public static void SetStagger(UIElement element, bool value) => element.SetValue(StaggerProperty, value);

    /// <summary>Gets <c>RowHeight</c>.</summary>
    /// <param name="element">List.</param>
    /// <returns>Row height in epx.</returns>
    public static double GetRowHeight(UIElement element) => (double)element.GetValue(RowHeightProperty);

    /// <summary>Sets <c>RowHeight</c>.</summary>
    /// <param name="element">List.</param>
    /// <param name="value">Row height in epx.</param>
    public static void SetRowHeight(UIElement element, double value) => element.SetValue(RowHeightProperty, value);

    /// <summary>Re-arms a list's stagger (a sort, filter or search changed without replacing its items source).</summary>
    /// <param name="list">Repeater or list view.</param>
    public static void Restagger(UIElement list) => Restagger(list, 0);

    /// <summary>
    /// Re-arms a list's stagger for a batch appended at <paramref name="batchStart"/> (Suggestions' incremental
    /// loading): rows before it were already revealed and never fade again; the batch staggers from its first row.
    /// </summary>
    /// <param name="list">Repeater or list view.</param>
    /// <param name="batchStart">Index of the batch's first row (0 when the whole list is new).</param>
    public static void Restagger(UIElement list, int batchStart)
    {
        var arm = ArmOf(list);
        arm.Arm(batchStart, Now);
        Trace("fade-arm", list, $"start={arm.BatchStart}");
        if (arm.NeedsSettle && list is FrameworkElement element) SettleAfterLayout(element, arm);
    }

    /// <summary>Monotonic time for the stagger window.</summary>
    private static TimeSpan Now => Stopwatch.GetElapsedTime(0);

    /// <summary>
    /// A new stagger window: <see cref="FadeInTiming.ArmWindow"/>, or the Debug/automation <c>FST_DEBUG_FADE_WINDOW_MS</c>
    /// override, which lets a UI journey's scripted scroll land inside the window (issue #260).
    /// </summary>
    /// <returns>Closed arm.</returns>
    public static StaggerArm NewArm() => new(WindowOverride);

    private static readonly TimeSpan? WindowOverride = StaggerArm.ParseWindow(App.LaunchEnvironment("FST_DEBUG_FADE_WINDOW_MS"));

    /// <summary>The list's stagger window, created on first use.</summary>
    /// <param name="list">Repeater or list view.</param>
    /// <returns>Arm.</returns>
    private static StaggerArm ArmOf(UIElement list)
    {
        if (list.GetValue(ArmProperty) is StaggerArm arm) return arm;
        arm = NewArm();
        list.SetValue(ArmProperty, arm);
        return arm;
    }

    /// <summary>
    /// Anchors a load arm's scroll position once the layout it triggered has settled, so a page that resets its list to
    /// the top as part of the reload (Songs' new sort) still staggers the new first screen.
    /// </summary>
    /// <param name="list">List.</param>
    /// <param name="arm">Its arm.</param>
    private static void SettleAfterLayout(FrameworkElement list, StaggerArm arm)
    {
        var tracker = TrackerOf(list);
        if (tracker.Settling) return;
        tracker.Settling = true;
        void OnLayout(object? sender, object e)
        {
            var (x, y) = tracker.Offset();
            arm.Settle(x, y);
            if (arm.NeedsSettle && arm.IsOpen(Now)) return;
            tracker.Settling = false;
            list.LayoutUpdated -= OnLayout;
        }
        list.LayoutUpdated += OnLayout;
    }

    /// <summary>The list's scroller tracker, created on first use.</summary>
    /// <param name="list">List.</param>
    /// <returns>Tracker.</returns>
    private static ScrollTracker TrackerOf(FrameworkElement list)
    {
        if (list.GetValue(TrackerProperty) is ScrollTracker tracker) return tracker;
        tracker = new ScrollTracker(list);
        list.SetValue(TrackerProperty, tracker);
        return tracker;
    }

    /// <summary>Hooks element preparation, items-source changes and the scroller once.</summary>
    /// <param name="d">List.</param>
    /// <param name="e">New value.</param>
    private static void OnStaggerChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (e.NewValue is not true) return;
        switch (d)
        {
            case ItemsRepeater repeater:
                Restagger(repeater);
                repeater.RegisterPropertyChangedCallback(ItemsRepeater.ItemsSourceProperty, (_, _) => Restagger(repeater));
                repeater.ElementPrepared += (sender, args) => Prepare(sender, args.Element, args.Index);
                break;
            case ListViewBase list:
                Restagger(list);
                list.RegisterPropertyChangedCallback(ItemsControl.ItemsSourceProperty, (_, _) => Restagger(list));
                list.ContainerContentChanging += (sender, args) =>
                {
                    if (args.Phase == 0 && !args.InRecycleQueue) Prepare(sender, args.ItemContainer, args.ItemIndex);
                };
                break;
            default:
                return;
        }
        var element = (FrameworkElement)d;
        element.Loaded += (_, _) => TrackerOf(element).Attach();
        element.Unloaded += (_, _) => TrackerOf(element).Detach();
    }

    /// <summary>
    /// Staggers the rows a list has already realized (a list kept hidden until its first rows are ready, like Songs),
    /// then re-arms the list so rows realized in the next moments continue the sequence.
    /// </summary>
    /// <param name="list">List view.</param>
    public static void StaggerRealized(ListViewBase list)
    {
        Restagger(list);
        SettleNow(list);
        var visible = FadeInTiming.VisibleCount(list.XamlRoot?.Size.Height ?? list.ActualHeight, GetRowHeight(list));
        for (var i = 0; i < FadeInTiming.MaxStaggered; i++)
        {
            if (list.ContainerFromIndex(i) is not UIElement container) break;
            if (FadeInTiming.StaggerDelay(i, visible) is { } delay) PlayRow(list, container, i, delay);
        }
    }

    /// <summary>
    /// <see cref="StaggerRealized(ListViewBase)"/> for a repeater (the Shop grid kept hidden until its first tiles' art
    /// decoded, and a List/Grid switch that replays the entrance for the new layout).
    /// </summary>
    /// <param name="repeater">Repeater.</param>
    public static void StaggerRealized(ItemsRepeater repeater)
    {
        Restagger(repeater);
        SettleNow(repeater);
        var visible = FadeInTiming.VisibleCount(repeater.XamlRoot?.Size.Height ?? repeater.ActualHeight, GetRowHeight(repeater));
        var count = repeater.ItemsSourceView?.Count ?? 0;
        for (var i = 0; i < Math.Min(count, FadeInTiming.MaxStaggered); i++)
        {
            if (repeater.TryGetElement(i) is not UIElement element) continue;
            if (FadeInTiming.StaggerDelay(i, visible) is { } delay) PlayRow(repeater, element, i, delay);
        }
    }

    /// <summary>Anchors the arm at the current scroll position: the list's rows are already laid out and showing.</summary>
    /// <param name="list">List.</param>
    private static void SettleNow(FrameworkElement list)
    {
        var (x, y) = TrackerOf(list).Offset();
        ArmOf(list).Settle(x, y);
    }

    /// <summary>
    /// Fades a freshly realized row when its list (or its newest batch) loaded moments ago, the reader hasn't scrolled
    /// since a load (R5), and the row is within the visible count of that batch; other rows show in place.
    /// </summary>
    /// <param name="list">Owning list.</param>
    /// <param name="element">Row element.</param>
    /// <param name="index">Row index.</param>
    private static void Prepare(FrameworkElement list, UIElement element, int index)
    {
        var arm = ArmOf(list);
        var (x, y) = TrackerOf(list).Offset();
        var now = Now;
        if (arm.Scrolled(x, y)) Trace("fade-close", list, $"start={arm.BatchStart} since={arm.SinceArmed(now).TotalMilliseconds:F0}");
        var visible = FadeInTiming.VisibleCount(list.XamlRoot?.Size.Height ?? list.ActualHeight, GetRowHeight(list));
        if (arm.Delay(index, visible, now, x, y) is { } delay)
        {
            PlayRow(list, element, index, delay);
            return;
        }
        Reset(element);
        if (arm.SuppressedByScroll(now, index, visible)) Trace("fade-skip", list, $"index={index}");
    }

    /// <summary>
    /// A stagger list's scroller (a list view's own, else the nearest scrolling ancestor): its movement closes the
    /// list's load arm. Attached while the list is loaded only, so a recycled inner list never outlives its page.
    /// </summary>
    private sealed class ScrollTracker(FrameworkElement list)
    {
        private ScrollViewer? viewer;

        /// <summary>Whether a layout-settle hook is pending.</summary>
        public bool Settling { get; set; }

        /// <summary>Finds the scroller and listens to its view changes.</summary>
        public void Attach()
        {
            Detach();
            viewer = list is ListViewBase ? Descendant(list) : Ancestor(list);
            if (viewer is null) return;
            viewer.ViewChanging += OnViewChanging;
            viewer.ViewChanged += OnViewChanged;
        }

        /// <summary>Stops listening.</summary>
        public void Detach()
        {
            if (viewer is null) return;
            viewer.ViewChanging -= OnViewChanging;
            viewer.ViewChanged -= OnViewChanged;
            viewer = null;
        }

        /// <summary>The scroller's offsets, or NaN while it is unknown (no movement is measured then).</summary>
        /// <returns>Horizontal and vertical offsets (epx).</returns>
        public (double X, double Y) Offset()
        {
            if (viewer is null && list.IsLoaded) Attach();
            return viewer is null ? (double.NaN, double.NaN) : (viewer.HorizontalOffset, viewer.VerticalOffset);
        }

        private void OnViewChanging(object? sender, ScrollViewerViewChangingEventArgs e) =>
            Moved(e.NextView.HorizontalOffset, e.NextView.VerticalOffset);

        private void OnViewChanged(object? sender, ScrollViewerViewChangedEventArgs e)
        {
            if (viewer is not null) Moved(viewer.HorizontalOffset, viewer.VerticalOffset);
        }

        /// <summary>Closes the list's load arm on movement from its anchor.</summary>
        /// <param name="x">Horizontal offset.</param>
        /// <param name="y">Vertical offset.</param>
        private void Moved(double x, double y)
        {
            if (list.GetValue(ArmProperty) is not StaggerArm arm || !arm.Scrolled(x, y)) return;
            Trace("fade-close", list, $"start={arm.BatchStart} since={arm.SinceArmed(Now).TotalMilliseconds:F0}");
        }

        /// <summary>A list view's template scroller.</summary>
        /// <param name="root">List.</param>
        /// <returns>Scroller, if any.</returns>
        private static ScrollViewer? Descendant(DependencyObject root)
        {
            var queue = new Queue<DependencyObject>();
            queue.Enqueue(root);
            while (queue.Count > 0)
            {
                var node = queue.Dequeue();
                if (node is ScrollViewer found && !ReferenceEquals(node, root)) return found;
                for (var i = 0; i < VisualTreeHelper.GetChildrenCount(node); i++) queue.Enqueue(VisualTreeHelper.GetChild(node, i));
            }
            return null;
        }

        /// <summary>The nearest scrolling ancestor.</summary>
        /// <param name="element">Repeater.</param>
        /// <returns>Scroller, if any.</returns>
        private static ScrollViewer? Ancestor(DependencyObject element)
        {
            for (var node = VisualTreeHelper.GetParent(element); node is not null; node = VisualTreeHelper.GetParent(node))
                if (node is ScrollViewer found) return found;
            return null;
        }
    }

    /// <summary>Plays a row's stagger fade and traces it.</summary>
    /// <param name="list">Owning list.</param>
    /// <param name="element">Row element.</param>
    /// <param name="index">Row index.</param>
    /// <param name="delay">Stagger delay.</param>
    private static void PlayRow(FrameworkElement list, UIElement element, int index, TimeSpan delay)
    {
        Play(element, delay);
        Trace("fade-play", list, $"index={index} delay={delay.TotalMilliseconds:F0} motion={(Motion.Allowed ? 1 : 0)}");
    }

    /// <summary>
    /// Writes a stagger decision to the perf log (<c>--perf-log</c>) for the fade journeys (issue #260): one line per
    /// re-arm, per row that fades, per load arm a scroll closes and per row that scroll kept from fading inside the
    /// closed window; never for rows that just appear otherwise, so steady scrolling writes nothing.
    /// </summary>
    /// <param name="kind">Line kind (<c>fade-arm</c>, <c>fade-play</c>, <c>fade-close</c>, <c>fade-skip</c>).</param>
    /// <param name="list">List (named by its x:Name, else its AutomationId).</param>
    /// <param name="detail">Space-separated <c>key=value</c> pairs.</param>
    private static void Trace(string kind, UIElement list, FormattableString detail)
    {
        if (!PerfLog.Enabled) return;
        var id = (list as FrameworkElement)?.Name;
        if (string.IsNullOrEmpty(id)) id = Microsoft.UI.Xaml.Automation.AutomationProperties.GetAutomationId(list);
        PerfLog.Write($"{kind} list={(string.IsNullOrEmpty(id) ? "?" : id)} {FormattableString.Invariant(detail)}");
    }
    #endregion

    #region Composition
    /// <summary>Plays <c>fadeInUp</c> on the element's composition visual after <paramref name="delay"/>.</summary>
    /// <param name="element">Element.</param>
    /// <param name="delay">Start delay (the element stays transparent until then).</param>
    public static void Play(UIElement element, TimeSpan delay)
    {
        if (!Motion.Allowed)
        {
            Reset(element);
            return;
        }
        var visual = ElementCompositionPreview.GetElementVisual(element);
        var compositor = visual.Compositor;
        ElementCompositionPreview.SetIsTranslationEnabled(element, true);
        element.SetValue(AnimatedProperty, true);
        var (x1, y1, x2, y2) = FadeInTiming.EaseOut;
        var ease = compositor.CreateCubicBezierEasingFunction(new Vector2(x1, y1), new Vector2(x2, y2));

        var fade = compositor.CreateScalarKeyFrameAnimation();
        fade.InsertKeyFrame(0f, 0f);
        fade.InsertKeyFrame(1f, 1f, ease);
        fade.Duration = FadeInTiming.Duration;
        fade.DelayTime = delay;
        fade.DelayBehavior = AnimationDelayBehavior.SetInitialValueBeforeDelay;

        var rise = compositor.CreateVector3KeyFrameAnimation();
        rise.InsertKeyFrame(0f, new Vector3(0, FadeInTiming.OffsetY, 0));
        rise.InsertKeyFrame(1f, Vector3.Zero, ease);
        rise.Duration = FadeInTiming.Duration;
        rise.DelayTime = delay;
        rise.DelayBehavior = AnimationDelayBehavior.SetInitialValueBeforeDelay;

        visual.StartAnimation(Opacity, fade);
        visual.StartAnimation(Translation, rise);
    }

    /// <summary>Stops any fade and shows the element in place (recycled rows, motion off).</summary>
    /// <param name="element">Element.</param>
    public static void Reset(UIElement element)
    {
        if (element.GetValue(AnimatedProperty) is not true) return;
        element.SetValue(AnimatedProperty, false);
        var visual = ElementCompositionPreview.GetElementVisual(element);
        visual.StopAnimation(Opacity);
        visual.StopAnimation(Translation);
        visual.Opacity = 1;
        visual.Properties.InsertVector3(Translation, Vector3.Zero);
    }
    #endregion
}
#endregion
