using System.Numerics;
using Festival.App.Services;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;

namespace Festival.App.Controls;

#region First-run demo
/// <summary>
/// Live mini-demo for a first-run slide (<see cref="FirstRunDemos"/>): the page's own WinUI controls and layout
/// (<see cref="SongRowCard"/>, <see cref="LeaderboardEntryRow"/>, menus, cards, the navigation pane) filled with demo
/// content, entering with the web's per-slide stagger (<see cref="FirstRunEntrance"/>) and advancing rotating web demos
/// every <see cref="FirstRunDemoTiming.Interval"/>. Motion effects off shows everything in place and swaps instantly;
/// hidden or inactive windows pause. Inert and decorative for UI Automation: the slide's title and description carry
/// the meaning.
/// </summary>
public sealed partial class FirstRunDemo : UserControl
{
    /// <summary>Slide ID dependency property.</summary>
    public static readonly DependencyProperty SlideIdProperty =
        DependencyProperty.Register(nameof(SlideId), typeof(string), typeof(FirstRunDemo), new PropertyMetadata(null, (d, _) => ((FirstRunDemo)d).Rebuild()));

    /// <summary>Realized demos whose Shop pulses run now (UI thread only): the <c>pulse-slides</c> census for UI tests.</summary>
    private static readonly HashSet<FirstRunDemo> PulseDemos = [];

    private readonly StackPanel root = new() { Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
    private readonly List<FrameworkElement> slots = [];
    private readonly List<Action<int>> slotSetters = [];
    private IReadOnlyList<FirstRunDemoSong> songs = [];
    private FirstRunDemoKind? kind;
    private DispatcherQueueTimer? timer;
    private CancellationTokenSource? artLoads;
    private Action<int>? advance;
    private readonly List<ActiveSwap> activeSwaps = [];
    private readonly List<ShopPulseRing> pulseRings = [];
    private readonly List<ShopPulseFill> pulseFills = [];
    private TimeSpan activeInterval = FirstRunDemoTiming.Interval;
    private int step;
    private bool active;
    private int swaps;
    private bool lastSwapFaded;

    /// <summary>One in-flight data swap that must complete if the slide deactivates mid-fade.</summary>
    private sealed class ActiveSwap
    {
        public FrameworkElement Element { get; init; } = null!;
        public Action? Change { get; init; }
        public bool Changed { get; set; }
        public List<DispatcherQueueTimer> Timers { get; } = [];
    }

    /// <summary>Creates the demo.</summary>
    public FirstRunDemo()
    {
        Content = root;
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        Loaded += (_, _) =>
        {
            // Idempotent: a repeated Loaded (see Unloaded) must not double-subscribe.
            Motion.Changed -= OnMotionChanged;
            App.Session.PropertyChanged -= OnSessionChanged;
            Motion.Changed += OnMotionChanged;
            App.Session.PropertyChanged += OnSessionChanged;
            if (CatalogueNowAvailable) Build();
            UpdateTimer();
        };
        Unloaded += (_, _) =>
        {
            // The FlipView re-hosts realized slides after the dialog lays out, and WinUI then raises a late Unloaded
            // while the demo is still in the live tree (issue #241). Tearing down there left the visible slide
            // unsubscribed from the catalogue (placeholder rows on a slow network), its art cancelled and swaps cut.
            if (IsLoaded) return;
            Motion.Changed -= OnMotionChanged;
            App.Session.PropertyChanged -= OnSessionChanged;
            timer?.Stop();
            StopAutoScroll();
            CompleteSwaps();
            artLoads?.Cancel();
            // Unloaded: no longer counted as a running pulse demo.
            PublishStatus();
        };
    }

    /// <summary>
    /// Raw-view peer so UI tests can read the demo's <c>fst.first-run.demo.*</c> AutomationId and ItemStatus
    /// (Narrator still skips it; its decorative children stay as they were).
    /// </summary>
    /// <returns>A framework element peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new FrameworkElementAutomationPeer(this);

    #region Fit
    private readonly ScaleTransform fit = new();
    private double fitScale = 1;

    /// <summary>
    /// Lays the demo out at the frame's width and, when large text makes it taller than the 210 epx frame, re-lays it
    /// out wider and shrinks it uniformly so every sample row stays whole (issue #241; <see cref="FirstRunDemoFit"/>).
    /// </summary>
    /// <param name="availableSize">Frame size.</param>
    /// <returns>Desired size, never taller than the frame.</returns>
    protected override Windows.Foundation.Size MeasureOverride(Windows.Foundation.Size availableSize)
    {
        var width = availableSize.Width;
        root.Measure(new Windows.Foundation.Size(width, double.PositiveInfinity));
        fitScale = double.IsFinite(width) ? FirstRunDemoFit.Scale(root.DesiredSize.Height, availableSize.Height) : 1;
        if (fitScale < 1) root.Measure(new Windows.Foundation.Size(width / fitScale, double.PositiveInfinity));
        return new Windows.Foundation.Size(
            double.IsFinite(width) ? width : root.DesiredSize.Width,
            Math.Min(root.DesiredSize.Height * fitScale, availableSize.Height));
    }

    /// <summary>Arranges the (possibly re-laid-out) demo in unscaled space, then applies the fit scale.</summary>
    /// <param name="finalSize">Frame size.</param>
    /// <returns><paramref name="finalSize"/>.</returns>
    protected override Windows.Foundation.Size ArrangeOverride(Windows.Foundation.Size finalSize)
    {
        fit.ScaleX = fit.ScaleY = fitScale;
        root.RenderTransform = fitScale < 1 ? fit : null;
        root.Arrange(new Windows.Foundation.Rect(0, 0, finalSize.Width / fitScale, finalSize.Height / fitScale));
        return finalSize;
    }
    #endregion


    /// <summary>Slide ID.</summary>
    public string? SlideId
    {
        get => (string?)GetValue(SlideIdProperty);
        set => SetValue(SlideIdProperty, value);
    }

    /// <summary>Whether this demo's slide is the visible one (set by the carousel).</summary>
    public bool Active
    {
        get => active;
        set
        {
            if (active == value) return;
            active = value;
            UpdateTimer();
            // Web FadeIn: a slide's blocks stagger in each time it is shown.
            if (value) PlayEntrance();
            else SyncEntranceVisibility();
        }
    }

    /// <summary>Whether the rows are placeholders while the catalogue could now supply real songs.</summary>
    private bool CatalogueNowAvailable => songs.Count > 0 && songs[0].IsPlaceholder && !SongPoolFor(kind)[0].IsPlaceholder;

    /// <summary>The songs a demo kind rotates through (Shop demos prefer the publication-matched Shop feed).</summary>
    /// <param name="k">Kind, or <see langword="null"/>.</param>
    /// <returns>Pool, placeholders while the catalogue is loading or unavailable.</returns>
    private static IReadOnlyList<FirstRunDemoSong> SongPoolFor(FirstRunDemoKind? k)
    {
        var session = App.Session;
        var shopIds = k is { } kind && FirstRunDemos.UsesShopSongs(kind)
            ? FirstRunDemos.ShopPreference(session.Shop, session.ShopOffersForCatalog, session.Settings.HideShop)
            : [];
        return FirstRunDemos.SongPool(session.Catalog?.Songs, shopIds);
    }

    /// <summary>Swaps placeholders for real songs as soon as the catalogue arrives (even with motion off).</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(App.Session.Catalog) && CatalogueNowAvailable) Rebuild();
    }

    /// <summary>Rebuilds with the current catalogue, keeping the timer state.</summary>
    private void Rebuild()
    {
        Build();
        UpdateTimer();
    }

    /// <summary>Whether a demo exists for the slide (otherwise the static illustration shows).</summary>
    public bool HasDemo => kind is not null;

    #region Motion
    /// <summary>Re-evaluates the timer when motion settings, window visibility or window activation change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnMotionChanged(object? sender, EventArgs e)
    {
        UpdateTimer();
        if (!Motion.Allowed) SyncEntranceVisibility();
    }

    /// <summary>Runs the step timer only for the visible foreground slide; motion-off swaps are instant.</summary>
    private void UpdateTimer()
    {
        // Shop pulses breathe only on the visible slide (iOS #28): FlipView keeps neighbours realized off-screen.
        foreach (var ring in pulseRings) ring.Live = active;
        foreach (var fill in pulseFills) fill.Live = active;
        UpdateAutoScroll();
        var run = RotationState == FirstRunDemoRotationState.Running;
        if (!run)
        {
            timer?.Stop();
            CompleteSwaps();
            PublishStatus();
            return;
        }
        if (timer is null)
        {
            timer = DispatcherQueue.CreateTimer();
            timer.Interval = FirstRunDemos.Cycle;
            timer.Tick += (_, _) =>
            {
                advance?.Invoke(step++);
                PublishStatus();
            };
        }
        timer.Interval = activeInterval;
        if (!timer.IsRunning) timer.Start();
        PublishStatus();
    }

    /// <summary>The rotation gate: only <see cref="FirstRunDemoRotationState.Running"/> runs the swap clock.</summary>
    private FirstRunDemoRotationState RotationState =>
        FirstRunDemoRotationStatus.State(advance is not null, active, IsLoaded, Motion.Paused, Motion.Foreground);

    /// <summary>Publishes the data, rotation and Shop pulse state as the raw-view peer's ItemStatus for UI tests.</summary>
    private void PublishStatus()
    {
        if (kind is null) return;
        var running = CurrentPulse() == FirstRunDemoRotationStatus.PulseRunning;
        // A changed census republishes every running demo's pulse-slides count; this one is published either way.
        if (running ? PulseDemos.Add(this) : PulseDemos.Remove(this))
            foreach (var demo in PulseDemos.Where(d => d != this)) demo.PublishOwnStatus();
        PublishOwnStatus();
    }

    /// <summary>This demo's Shop pulse token (<see cref="FirstRunDemoRotationStatus.PulseState"/>).</summary>
    /// <returns>Token, or <see langword="null"/> without pulses.</returns>
    private string? CurrentPulse() =>
        FirstRunDemoRotationStatus.PulseState(pulseRings.Count + pulseFills.Count > 0, active, IsLoaded, Motion.Allowed, Motion.Paused);

    /// <summary>Sets this demo's ItemStatus from its current state without touching the census.</summary>
    private void PublishOwnStatus()
    {
        if (kind is null) return;
        AutomationProperties.SetItemStatus(this, FirstRunDemoRotationStatus.Format(FirstRunDemos.DataStatus(songs), RotationState, swaps, lastSwapFaded, CurrentPulse(), PulseDemos.Count));
    }

    /// <summary>Records one drawn data swap (a tick whose pool can't replace rows draws none).</summary>
    /// <param name="faded">Whether it fades, else it is instant.</param>
    private void CountSwap(bool faded)
    {
        swaps++;
        lastSwapFaded = faded;
    }

    /// <summary>Fades one slot out, swaps its content at the midpoint and fades it back (web fade-out → swap → fade-in).</summary>
    /// <param name="slot">Slot index.</param>
    /// <param name="poolIndex">New content.</param>
    private void FadeSwap(int slot, int poolIndex)
    {
        if (slot >= slots.Count) return;
        Fade(slots[slot], () => slotSetters[slot](poolIndex));
    }

    /// <summary>Fades every slot out, applies a change and fades back.</summary>
    /// <param name="change">Change applied while hidden.</param>
    private void FadeAll(Action change)
    {
        for (var i = 0; i < slots.Count; i++) Fade(slots[i], i == 0 ? change : null);
    }

    /// <summary>Compositor fade-out, content swap, fade-in matching the web timing.</summary>
    /// <remarks>
    /// The vertical nudge animates the visual's <c>Translation</c>, never <c>Offset</c>: XAML layout owns a hand-out
    /// visual's Offset, and resetting it to zero stacked every swapped row on the first one (issue #241).
    /// </remarks>
    /// <param name="element">Element.</param>
    /// <param name="change">Change at the midpoint, if any.</param>
    /// <param name="duration">One fade duration.</param>
    /// <param name="translateY">Optional offset while hidden.</param>
    private void Fade(FrameworkElement element, Action? change, TimeSpan? duration = null, float translateY = 0)
    {
        if (!Motion.Allowed)
        {
            CountSwap(faded: false);
            change?.Invoke();
            ResetVisual(element);
            return;
        }
        var fade = duration ?? FirstRunDemoTiming.FadeOut;
        CountSwap(faded: true);
        var visual = ElementCompositionPreview.GetElementVisual(element);
        if (translateY != 0)
        {
            ElementCompositionPreview.SetIsTranslationEnabled(element, true);
            visual.Properties.InsertVector3("Translation", Vector3.Zero);
        }
        var ease = visual.Compositor.CreateCubicBezierEasingFunction(new Vector2(0.25f, 0.1f), new Vector2(0.25f, 1f));
        var swap = new ActiveSwap { Element = element, Change = change };
        activeSwaps.Add(swap);

        void AnimateOpacity(float from, float to)
        {
            var animation = visual.Compositor.CreateScalarKeyFrameAnimation();
            animation.InsertKeyFrame(0f, from);
            animation.InsertKeyFrame(1f, to, ease);
            animation.Duration = fade;
            visual.StartAnimation("Opacity", animation);
        }

        void AnimateTranslation(float from, float to)
        {
            if (translateY == 0) return;
            var animation = visual.Compositor.CreateVector3KeyFrameAnimation();
            animation.InsertKeyFrame(0f, new Vector3(0, from, 0));
            animation.InsertKeyFrame(1f, new Vector3(0, to, 0), ease);
            animation.Duration = fade;
            visual.StartAnimation("Translation", animation);
        }

        AnimateOpacity(1, 0);
        AnimateTranslation(0, translateY);
        var midpoint = DispatcherQueue.CreateTimer();
        midpoint.Interval = fade;
        midpoint.IsRepeating = false;
        midpoint.Tick += (_, _) =>
        {
            swap.Changed = true;
            change?.Invoke();
            visual.Opacity = 0;
            AnimateOpacity(0, 1);
            AnimateTranslation(translateY, 0);
            var done = DispatcherQueue.CreateTimer();
            done.Interval = fade;
            done.IsRepeating = false;
            done.Tick += (_, _) =>
            {
                ResetVisual(element);
                activeSwaps.Remove(swap);
            };
            swap.Timers.Add(done);
            done.Start();
        };
        swap.Timers.Add(midpoint);
        midpoint.Start();
    }

    /// <summary>Completes any hidden swaps before stopping the timer.</summary>
    private void CompleteSwaps()
    {
        foreach (var swap in activeSwaps.ToList())
        {
            foreach (var timerToStop in swap.Timers) timerToStop.Stop();
            if (!swap.Changed)
            {
                swap.Change?.Invoke();
                swap.Changed = true;
            }
            ResetVisual(swap.Element);
            activeSwaps.Remove(swap);
        }
    }

    /// <summary>Stops a slot's fade and shows it fully opaque at its layout position.</summary>
    /// <param name="element">Slot element.</param>
    private static void ResetVisual(UIElement element)
    {
        var visual = ElementCompositionPreview.GetElementVisual(element);
        visual.StopAnimation("Opacity");
        visual.Opacity = 1;
        if (visual.Properties.TryGetVector3("Translation", out _) == Microsoft.UI.Composition.CompositionGetValueStatus.Succeeded)
        {
            visual.StopAnimation("Translation");
            visual.Properties.InsertVector3("Translation", Vector3.Zero);
        }
    }
    #endregion
}
#endregion
