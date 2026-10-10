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
/// after its items change, 125 ms apart for the rows that fit the viewport and with the last of them for the rows below
/// (<see cref="StaggerArm"/>, pattern <c>load-transition</c> R5). A page's own entrance (sections, headings, cards: Song
/// Detail, Player Profile) is the same arm owned by the page's <see cref="ScrollViewer"/>
/// (<see cref="BeginEntrance"/> + <see cref="Enter"/>), and a board's pinned row enters with its rows' arm
/// (<see cref="Enter"/> with the list as owner): every delayed fade belongs to exactly one entrance. The first scroll
/// movement while an entrance runs <b>rushes</b> it, like the web <c>useStaggerRush</c> (issue #323): every fade of that
/// entrance that hasn't started yet starts at once, so the remaining content fades in together and nothing reached by the
/// scroll is already opaque; a scroll after the entrance never replays it.
/// <see cref="Restagger(UIElement, int)"/> re-arms it for an appended batch only, which scrolling reveals and never rushes
/// (Suggestions). <see cref="SelectedRowReveal"/> holds the rows below the first screen for its automatic scroll and
/// rushes them as it starts. All of it runs on the compositor, leaves nothing running when finished, and does nothing
/// while motion is off (<see cref="Motion.Allowed"/>).
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
        element.Loaded += (_, _) => { if (element.Visibility == Visibility.Visible) Play(element); };
        element.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) =>
        {
            if (element.IsLoaded && element.Visibility == Visibility.Visible) Play(element);
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
    internal static TimeSpan Now => Stopwatch.GetElapsedTime(0);

    /// <summary>A stagger list's fade window (a selected-row reveal reads its generation and scroll state).</summary>
    /// <param name="list">Repeater or list view.</param>
    /// <returns>Arm.</returns>
    internal static StaggerArm ArmFor(UIElement list) => ArmOf(list);

    /// <summary>Rows of the list that stagger: those that fit the window (web <c>estimateVisibleCount</c>).</summary>
    /// <param name="list">Repeater or list view.</param>
    /// <returns>Visible count.</returns>
    internal static int VisibleRows(FrameworkElement list) =>
        FadeInTiming.VisibleCount(list.XamlRoot?.Size.Height ?? list.ActualHeight, GetRowHeight(list));

    /// <summary>
    /// A new stagger window: <see cref="FadeInTiming.ArmWindow"/>, or the Debug/automation <c>FST_DEBUG_FADE_WINDOW_MS</c>
    /// override, which lets a UI journey's scripted scroll land inside the window (issue #260).
    /// </summary>
    /// <returns>Closed arm.</returns>
    private static StaggerArm NewArm() => new(WindowOverride);

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
        TrackerOf((FrameworkElement)d).Hook();
    }

    /// <summary>
    /// Staggers the rows a list has already realized (a list kept hidden until its first rows are ready, like Songs),
    /// then re-arms the list so rows realized in the next moments continue the sequence.
    /// </summary>
    /// <param name="list">List view.</param>
    public static void StaggerRealized(ListViewBase list) =>
        StaggerRealized(list, list.Items.Count, i => list.ContainerFromIndex(i) as UIElement);

    /// <summary>
    /// <see cref="StaggerRealized(ListViewBase)"/> for a repeater (the Shop grid kept hidden until its first tiles' art
    /// decoded, and a List/Grid switch that replays the entrance for the new layout).
    /// </summary>
    /// <param name="repeater">Repeater.</param>
    public static void StaggerRealized(ItemsRepeater repeater) =>
        StaggerRealized(repeater, repeater.ItemsSourceView?.Count ?? 0, repeater.TryGetElement);

    /// <summary>
    /// Re-arms the list and fades every row it has realized: the first screen staggered, the rows below it with the last
    /// staggered row (issue #323), so none of them is opaque when a scroll reaches it during the entrance.
    /// </summary>
    /// <param name="list">Repeater or list view.</param>
    /// <param name="count">Items in the list.</param>
    /// <param name="realized">The realized element at an index, if any.</param>
    private static void StaggerRealized(FrameworkElement list, int count, Func<int, UIElement?> realized)
    {
        Restagger(list);
        SettleNow(list);
        var arm = ArmOf(list);
        var (x, y) = TrackerOf(list).Offset();
        var now = Now;
        var visible = VisibleRows(list);
        var found = false;
        for (var i = 0; i < count; i++)
        {
            if (realized(i) is not UIElement element)
            {
                // Realized rows are contiguous: stop after them, or when none of the first screen is realized.
                if (found || i >= FadeInTiming.MaxStaggered) break;
                continue;
            }
            found = true;
            if (arm.Delay(i, visible, now, x, y) is { } delay) PlayRow(list, element, i, delay, arm);
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
        var tracker = TrackerOf(list);
        var (x, y) = tracker.Offset();
        var now = Now;
        OnScrolled(list, arm, arm.Scrolled(x, y, now), now);
        var visible = VisibleRows(list);
        if (arm.Delay(index, visible, now, x, y) is { } delay)
        {
            PlayRow(list, element, index, delay, arm);
            return;
        }
        Reset(element);
        if (arm.SuppressedByScroll(now, index, visible)) Trace("fade-skip", list, $"index={index}");
    }

    /// <summary>
    /// Acts on what a scroll movement did to an entrance's arm: a rush starts every pending fade of the entrance (its
    /// rows and its direct entrances, such as a board's pinned row) at once; a close only traces.
    /// </summary>
    /// <param name="owner">The entrance's list or page scroller.</param>
    /// <param name="arm">Its arm.</param>
    /// <param name="scroll">What the movement did.</param>
    /// <param name="now">Monotonic time.</param>
    private static void OnScrolled(FrameworkElement owner, StaggerArm arm, ArmScroll scroll, TimeSpan now)
    {
        switch (scroll)
        {
            case ArmScroll.Rushed:
                TraceRush(owner, arm, RushPending(owner, arm, now, out var kept), kept, now);
                break;
            case ArmScroll.Closed:
                Trace("fade-close", owner, $"start={arm.BatchStart} since={arm.SinceArmed(now).TotalMilliseconds:F0}");
                break;
        }
    }

    /// <summary>Traces a rush: fades started at once and fades it left on their delay (only an appended batch's).</summary>
    /// <param name="owner">The entrance's list or page scroller.</param>
    /// <param name="arm">Its arm.</param>
    /// <param name="rushed">Fades started at once.</param>
    /// <param name="kept">Pending fades of the entrance the rush did not reach.</param>
    /// <param name="now">Monotonic time.</param>
    private static void TraceRush(FrameworkElement owner, StaggerArm arm, int rushed, int kept, TimeSpan now) =>
        Trace("fade-rush", owner, $"start={arm.BatchStart} rushed={rushed} kept={kept} since={arm.SinceArmed(now).TotalMilliseconds:F0}");

    /// <summary>
    /// Rushes a list's load entrance for an automatic scroll about to start (<see cref="SelectedRowReveal"/>): pending
    /// fades (rows and the pinned row) start now and rows the scroll realizes fade in with them.
    /// </summary>
    /// <param name="list">List.</param>
    /// <param name="lasting">How long the scroll may take.</param>
    internal static void RushForAutomaticScroll(FrameworkElement list, TimeSpan lasting)
    {
        var arm = ArmOf(list);
        var now = Now;
        if (!arm.Rush(now, lasting)) return;
        TraceRush(list, arm, RushPending(list, arm, now, out var kept), kept, now);
    }
    #endregion

    #region Entrances
    private static readonly DependencyProperty HeldAnchorProperty = DependencyProperty.RegisterAttached(
        "HeldAnchor", typeof(object), typeof(FadeIn), new PropertyMetadata(null));

    /// <summary>A page scroller's position when its content was laid out, before its entrance began.</summary>
    /// <param name="X">Horizontal offset (epx).</param>
    /// <param name="Y">Vertical offset (epx).</param>
    private sealed record HeldAnchor(double X, double Y);

    /// <summary>
    /// Holds a page entrance's start position while its content is already laid out (and scrollable) but still hidden,
    /// such as Song Details behind its spinner's fade-out: a scroll in that moment then rushes the entrance as soon as
    /// <see cref="BeginEntrance"/> starts it, rather than going unseen and leaving the content to stagger in after the
    /// reader has scrolled (R5, issue #532).
    /// </summary>
    /// <param name="scroller">The page's scroller.</param>
    public static void HoldEntrance(ScrollViewer scroller) =>
        scroller.SetValue(HeldAnchorProperty, new HeldAnchor(scroller.HorizontalOffset, scroller.VerticalOffset));

    /// <summary>
    /// Starts a page's own first-load entrance (Song Detail's sections and cards, Player Profile's title and Overview):
    /// a load arm owned by the page's scroller, whose first movement rushes every <see cref="Enter"/> fade of the page
    /// that hasn't started (a drag, wheel, Quick Links jump or programmatic scroll; web <c>useStaggerRush</c>, issue #323).
    /// After <see cref="HoldEntrance"/>, movement is measured from the held position, so a scroll that came first rushes
    /// the entrance at once and its elements enter together.
    /// </summary>
    /// <param name="scroller">The page's scroller.</param>
    public static void BeginEntrance(ScrollViewer scroller)
    {
        TrackerOf(scroller).Hook();
        Restagger(scroller);
        if (scroller.GetValue(HeldAnchorProperty) is not HeldAnchor held)
        {
            SettleNow(scroller);
            return;
        }
        scroller.ClearValue(HeldAnchorProperty);
        var arm = ArmOf(scroller);
        arm.Settle(held.X, held.Y);
        var now = Now;
        OnScrolled(scroller, arm, arm.Scrolled(scroller.HorizontalOffset, scroller.VerticalOffset, now), now);
    }

    /// <summary>
    /// Fades an element in as part of an entrance: its own delay while the entrance runs (held to the entrance's last
    /// start once the window has passed), at once while a scroll rushes it, in place after it (R5). The owner is a page
    /// scroller after <see cref="BeginEntrance"/>, or a stagger list whose rows the element enters with (a board's pinned
    /// row, issue #295), so the rush that starts the rows starts it too.
    /// </summary>
    /// <param name="owner">The entrance's page scroller or stagger list.</param>
    /// <param name="element">Section, card or pinned row.</param>
    /// <param name="natural">Its delay in the entrance's choreography.</param>
    public static void Enter(FrameworkElement owner, UIElement element, TimeSpan natural)
    {
        var arm = ArmOf(owner);
        var (x, y) = TrackerOf(owner).Offset();
        var now = Now;
        // A scroll the scroller hasn't reported yet (an element realized by it) rushes before the element is scheduled.
        OnScrolled(owner, arm, arm.Scrolled(x, y, now), now);
        if (arm.Entrance(natural, now) is not { } delay)
        {
            Reset(element);
            return;
        }
        Schedule(element, delay, arm, -1);
        Trace("fade-enter", owner, $"target={NameOf(element)} delay={delay.TotalMilliseconds:F0} motion={(Motion.Allowed ? 1 : 0)}");
    }
    #endregion

    #region Automatic scroll and scroll tracking

    /// <summary>
    /// Announces a list's automatic scroll at <paramref name="at"/>: rows below its first screen whose fades would start
    /// before then wait for it (<see cref="StaggerArm.ExpectScroll"/>), so the scroll reaches rows still fading in.
    /// </summary>
    /// <param name="list">List.</param>
    /// <param name="at">When the scroll is expected (<see cref="Now"/> time).</param>
    /// <returns>Token for <see cref="StaggerArm.EndExpectation"/>.</returns>
    internal static int ExpectAutomaticScroll(FrameworkElement list, TimeSpan at)
    {
        var arm = ArmOf(list);
        var token = arm.ExpectScroll(at);
        if (arm.ExpectedScroll is null) return token;
        var now = Now;
        var visible = VisibleRows(list);
        var held = 0;
        foreach (var (element, fade) in Pending.ToArray())
        {
            if (fade.Arm != arm || !Current(element, fade) || fade.StartsAt <= now || fade.StartsAt >= at || !arm.IsTail(fade.Index, visible)) continue;
            PlayCore(element, at - now);
            Pending[element] = fade with { Token = TokenOf(element), StartsAt = at };
            held++;
        }
        Trace("fade-hold", list, $"held={held} wait={(at - now).TotalMilliseconds:F0}");
        return token;
    }

    /// <summary>
    /// An entrance's scroller (a page entrance's own scroller, a list view's own, else the nearest scrolling ancestor):
    /// its movement rushes or closes the entrance's load arm. Attached while the owner is loaded only, so a recycled inner
    /// list never outlives its page.
    /// </summary>
    private sealed class ScrollTracker(FrameworkElement list)
    {
        private ScrollViewer? viewer;
        private bool hooked;

        /// <summary>Whether a layout-settle hook is pending.</summary>
        public bool Settling { get; set; }

        /// <summary>Attaches while the owner is loaded, once.</summary>
        public void Hook()
        {
            if (hooked) return;
            hooked = true;
            list.Loaded += (_, _) => Attach();
            list.Unloaded += (_, _) => Detach();
            if (list.IsLoaded) Attach();
        }

        /// <summary>Finds the scroller and listens to its view changes.</summary>
        public void Attach()
        {
            Detach();
            viewer = list switch
            {
                ScrollViewer own => own,
                ListViewBase => Descendant(list),
                _ => Ancestor(list),
            };
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

        /// <summary>Rushes or closes the entrance's load arm on movement from its anchor.</summary>
        /// <param name="x">Horizontal offset.</param>
        /// <param name="y">Vertical offset.</param>
        private void Moved(double x, double y)
        {
            if (list.GetValue(ArmProperty) is not StaggerArm arm) return;
            var now = Now;
            OnScrolled(list, arm, arm.Scrolled(x, y, now), now);
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

    /// <summary>Plays a row's stagger fade, remembers it until it starts (so a rush can start it early) and traces it.</summary>
    /// <param name="list">Owning list.</param>
    /// <param name="element">Row element.</param>
    /// <param name="index">Row index.</param>
    /// <param name="delay">Stagger delay.</param>
    /// <param name="arm">The list's arm.</param>
    private static void PlayRow(FrameworkElement list, UIElement element, int index, TimeSpan delay, StaggerArm arm)
    {
        Schedule(element, delay, arm, index);
        Trace("fade-play", list, $"index={index} delay={delay.TotalMilliseconds:F0} motion={(Motion.Allowed ? 1 : 0)}");
    }

    /// <summary>
    /// Writes a stagger decision to the perf log (<c>--perf-log</c>) for the fade journeys (issues #260 and #323): one
    /// line per re-arm, per row that fades, per entrance element scheduled, per load arm a scroll rushes or closes, per
    /// entrance element a rush started early, per hold for an automatic scroll and per row a scroll kept from fading
    /// after the rush; never for rows that just appear otherwise, so steady scrolling writes nothing.
    /// </summary>
    /// <param name="kind">Line kind (<c>fade-arm</c>, <c>fade-play</c>, <c>fade-enter</c>, <c>fade-rush</c>,
    /// <c>fade-early</c>, <c>fade-close</c>, <c>fade-hold</c>, <c>fade-skip</c>, <c>fade-reveal</c>).</param>
    /// <param name="list">Entrance owner (named by its x:Name, else its AutomationId).</param>
    /// <param name="detail">Space-separated <c>key=value</c> pairs (an <c>at=</c> monotonic time in ms is appended).</param>
    internal static void Trace(string kind, UIElement list, FormattableString detail)
    {
        if (!PerfLog.Enabled) return;
        PerfLog.Write($"{kind} list={NameOf(list)} {FormattableString.Invariant(detail)} at={Now.TotalMilliseconds.ToString("F0", System.Globalization.CultureInfo.InvariantCulture)}");
    }

    /// <summary>An element's trace name: its x:Name, else its AutomationId, else <c>?</c>.</summary>
    /// <param name="element">Element.</param>
    /// <returns>Name without spaces.</returns>
    private static string NameOf(UIElement element)
    {
        var id = (element as FrameworkElement)?.Name;
        if (string.IsNullOrEmpty(id)) id = Microsoft.UI.Xaml.Automation.AutomationProperties.GetAutomationId(element);
        return string.IsNullOrEmpty(id) ? "?" : id.Replace(' ', '_');
    }
    #endregion

    #region Composition
    private static readonly DependencyProperty TokenProperty = DependencyProperty.RegisterAttached(
        "Token", typeof(int), typeof(FadeIn), new PropertyMetadata(0));

    /// <summary>A fade scheduled to start later: a rush or hold may restart it while its token is still current.</summary>
    /// <param name="Arm">The entrance it belongs to (a list's rows or a page's/board's <see cref="Enter"/> fades).</param>
    /// <param name="Index">Row index (-1 for an <see cref="Enter"/> fade).</param>
    /// <param name="Token">The element's fade token when it was scheduled (a later play or reset makes it stale).</param>
    /// <param name="StartsAt">When the fade starts (<see cref="Now"/> time).</param>
    private sealed record PendingFade(StaggerArm Arm, int Index, int Token, TimeSpan StartsAt);

    /// <summary>Fades that haven't started yet, by element; pruned as they start or go stale (UI thread only).</summary>
    private static readonly Dictionary<UIElement, PendingFade> Pending = new(ReferenceEqualityComparer.Instance);

    /// <summary>
    /// Plays <c>fadeInUp</c> on the element's composition visual now (a pinned row arriving over a revealed board, an
    /// <c>OnShow</c> element). A delayed fade always belongs to an entrance (<see cref="Enter"/>), so a scroll can rush it.
    /// </summary>
    /// <param name="element">Element.</param>
    public static void Play(UIElement element) => PlayCore(element, TimeSpan.Zero);

    /// <summary>Plays a fade and remembers it until it starts.</summary>
    /// <param name="element">Element.</param>
    /// <param name="delay">Start delay.</param>
    /// <param name="arm">Owning entrance.</param>
    /// <param name="index">Row index, or -1 for an entrance element.</param>
    private static void Schedule(UIElement element, TimeSpan delay, StaggerArm arm, int index)
    {
        if (!PlayCore(element, delay)) return;
        var now = Now;
        Prune(now);
        if (delay > TimeSpan.Zero) Pending[element] = new PendingFade(arm, index, TokenOf(element), now + delay);
    }

    /// <summary>
    /// Starts every pending fade of a rushed entrance at once (<see cref="StaggerArm.RushReaches"/>: its rows and its
    /// entrance elements, never a batch appended into it).
    /// </summary>
    /// <param name="owner">The entrance's list or page scroller (for the trace).</param>
    /// <param name="arm">The rushed entrance.</param>
    /// <param name="now">Monotonic time.</param>
    /// <param name="kept">Pending fades of the entrance the rush did not reach.</param>
    /// <returns>Fades rushed.</returns>
    private static int RushPending(FrameworkElement owner, StaggerArm arm, TimeSpan now, out int kept)
    {
        var rushed = 0;
        kept = 0;
        foreach (var (element, fade) in Pending.ToArray())
        {
            if (!Current(element, fade) || fade.StartsAt <= now)
            {
                Pending.Remove(element);
                continue;
            }
            if (fade.Arm != arm) continue;
            if (!arm.RushReaches(fade.Index))
            {
                kept++;
                continue;
            }
            Pending.Remove(element);
            PlayCore(element, TimeSpan.Zero);
            rushed++;
            if (fade.Index < 0) Trace("fade-early", owner, $"target={NameOf(element)} left={(fade.StartsAt - now).TotalMilliseconds:F0}");
        }
        return rushed;
    }

    /// <summary>Drops fades that started or were replaced.</summary>
    /// <param name="now">Monotonic time.</param>
    private static void Prune(TimeSpan now)
    {
        if (Pending.Count == 0) return;
        foreach (var (element, fade) in Pending.ToArray())
            if (fade.StartsAt <= now || !Current(element, fade)) Pending.Remove(element);
    }

    /// <summary>Whether a pending fade is still the element's latest.</summary>
    /// <param name="element">Element.</param>
    /// <param name="fade">Pending fade.</param>
    /// <returns><see langword="true"/> while no later play or reset replaced it.</returns>
    private static bool Current(UIElement element, PendingFade fade) => TokenOf(element) == fade.Token;

    /// <summary>The element's fade token.</summary>
    /// <param name="element">Element.</param>
    /// <returns>Token.</returns>
    private static int TokenOf(UIElement element) => (int)element.GetValue(TokenProperty);

    /// <summary>Starts <c>fadeInUp</c> on the element's composition visual, replacing any fade it had.</summary>
    /// <param name="element">Element.</param>
    /// <param name="delay">Start delay.</param>
    /// <returns><see langword="false"/> when motion is off (the element was shown in place instead).</returns>
    private static bool PlayCore(UIElement element, TimeSpan delay)
    {
        if (!Motion.Allowed)
        {
            Reset(element);
            return false;
        }
        element.SetValue(TokenProperty, TokenOf(element) + 1);
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
        return true;
    }

    /// <summary>Stops any fade and shows the element in place (recycled rows, motion off).</summary>
    /// <param name="element">Element.</param>
    public static void Reset(UIElement element)
    {
        if (element.GetValue(AnimatedProperty) is not true) return;
        element.SetValue(AnimatedProperty, false);
        element.SetValue(TokenProperty, TokenOf(element) + 1);
        Pending.Remove(element);
        var visual = ElementCompositionPreview.GetElementVisual(element);
        visual.StopAnimation(Opacity);
        visual.StopAnimation(Translation);
        visual.Opacity = 1;
        visual.Properties.InsertVector3(Translation, Vector3.Zero);
    }
    #endregion
}
#endregion
