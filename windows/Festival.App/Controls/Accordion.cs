using System.Diagnostics;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Accordion
/// <summary>
/// The app's one accordion motion (pattern <c>load-transition</c>, owner-approved accordion variant, issue #561):
/// opening grows the section and then fades its content in; closing fades the content out and then collapses the
/// section (<see cref="AccordionMotion"/>, 150 ms + 150 ms), instantly while motion is off (<see cref="Motion.Allowed"/>).
/// The implicit <see cref="Expander"/> style in <c>Themes/Styles.xaml</c> sets <c>Accordion.Sequenced</c> on every
/// Expander, which replaces the template's slide-in storyboards with this sequence; plain disclosure panels (Settings
/// options a switch reveals) bind <c>Accordion.Open</c>, and <see cref="InstrumentSelector"/> details drive an
/// <see cref="AccordionMover"/> directly. The Expander's own header,
/// keyboard handling and UIA expand/collapse pattern are untouched.
/// </summary>
public static class Accordion
{
    private const string ExpandStates = "ExpandStates";
    private const string ContentClipPart = "ExpanderContentClip";
    private const string ContentPart = "ExpanderContent";

    #region Sequenced
    /// <summary>Whether an <see cref="Expander"/> opens and closes with the sequenced accordion motion.</summary>
    public static readonly DependencyProperty SequencedProperty = DependencyProperty.RegisterAttached(
        "Sequenced", typeof(bool), typeof(Accordion), new PropertyMetadata(false, OnSequencedChanged));

    private static readonly DependencyProperty MoverProperty = DependencyProperty.RegisterAttached(
        "Mover", typeof(AccordionMover), typeof(Accordion), new PropertyMetadata(null));

    /// <summary>Gets <c>Sequenced</c>.</summary>
    /// <param name="expander">Expander.</param>
    /// <returns>Whether enabled.</returns>
    public static bool GetSequenced(Expander expander) => (bool)expander.GetValue(SequencedProperty);

    /// <summary>Sets <c>Sequenced</c>.</summary>
    /// <param name="expander">Expander.</param>
    /// <param name="value">Whether enabled.</param>
    public static void SetSequenced(Expander expander, bool value) => expander.SetValue(SequencedProperty, value);

    /// <summary>Hooks the Expander's template and expansion once.</summary>
    /// <param name="d">Expander.</param>
    /// <param name="e">New value.</param>
    private static void OnSequencedChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not Expander expander || e.NewValue is not true) return;
        expander.Loaded += (_, _) => Attach(expander);
        expander.RegisterPropertyChangedCallback(Expander.IsExpandedProperty, (_, _) =>
        {
            if (expander.GetValue(MoverProperty) is AccordionMover mover)
                mover.Set(expander.IsExpanded, animate: expander.IsLoaded);
        });
        if (expander.IsLoaded) Attach(expander);
    }

    /// <summary>
    /// Takes over the template's content part: stops and empties the <c>ExpandStates</c> storyboards (keeping their
    /// header setters) and hands the content to an <see cref="AccordionMover"/>. Leaves the system motion in place when
    /// the template doesn't have the expected parts.
    /// </summary>
    /// <param name="expander">Expander.</param>
    private static void Attach(Expander expander)
    {
        if (VisualTreeHelper.GetChildrenCount(expander) == 0 || VisualTreeHelper.GetChild(expander, 0) is not FrameworkElement root) return;
        if (expander.GetValue(MoverProperty) is AccordionMover existing && existing.Owns(root)) return;
        if (Find(root, ContentClipPart) is not FrameworkElement clip || Find(root, ContentPart) is not Border body
            || body.Child is not UIElement content) return;
        VisualStateGroup? group = null;
        foreach (var candidate in VisualStateManager.GetVisualStateGroups(root))
            if (candidate.Name == ExpandStates) group = candidate;
        if (group is null) return;
        foreach (var state in group.States)
        {
            // Empty the template's own storyboards in place: replacing VisualState.Storyboard leaves the Expander's
            // next GoToState hung (UIA Expand timed out), so the states keep their (now empty) storyboards and setters.
            if (state.Storyboard is not { } storyboard) continue;
            storyboard.Stop();
            storyboard.Children.Clear();
        }
        if (body.RenderTransform is CompositeTransform slide) slide.TranslateY = 0;
        var mover = new AccordionMover(root, clip, body, body, content, named: expander);
        expander.SetValue(MoverProperty, mover);
        mover.Set(expander.IsExpanded, animate: false);
    }

    #endregion

    #region Open
    /// <summary>
    /// Whether a plain disclosure panel is open: a <see cref="Border"/> (declared <c>Visibility="Collapsed"</c>) whose
    /// child is the revealed content, such as Settings options a switch reveals. Changes after load run the sequenced
    /// motion; before load, or with motion off, the panel opens and closes at once.
    /// </summary>
    public static readonly DependencyProperty OpenProperty = DependencyProperty.RegisterAttached(
        "Open", typeof(bool), typeof(Accordion), new PropertyMetadata(false, OnOpenChanged));

    /// <summary>Gets <c>Open</c>.</summary>
    /// <param name="panel">Disclosure panel.</param>
    /// <returns>Whether open.</returns>
    public static bool GetOpen(Border panel) => (bool)panel.GetValue(OpenProperty);

    /// <summary>Sets <c>Open</c>.</summary>
    /// <param name="panel">Disclosure panel.</param>
    /// <param name="value">Whether open.</param>
    public static void SetOpen(Border panel, bool value) => panel.SetValue(OpenProperty, value);

    /// <summary>Opens or closes the panel through its (lazily created) mover.</summary>
    /// <param name="d">Border.</param>
    /// <param name="e">New value.</param>
    private static void OnOpenChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not Border { Child: FrameworkElement content } panel) return;
        if (panel.GetValue(MoverProperty) is not AccordionMover mover)
        {
            mover = new AccordionMover(panel, panel, panel, content, content);
            panel.SetValue(MoverProperty, mover);
        }
        mover.Set(e.NewValue is true, animate: panel.IsLoaded);
    }
    #endregion

    #region Template lookup
    /// <summary>Finds a named element in a template's visual tree.</summary>
    /// <param name="parent">Search root.</param>
    /// <param name="name">Element name.</param>
    /// <returns>The element, or <see langword="null"/>.</returns>
    private static FrameworkElement? Find(DependencyObject parent, string name)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            if (child is FrameworkElement { Name: var childName } element && childName == name) return element;
            if (Find(child, name) is { } found) return found;
        }
        return null;
    }
    #endregion
}
#endregion

#region Accordion mover
/// <summary>
/// Drives one accordion section: the <c>clip</c>'s height grows or shrinks between zero and the natural height of the
/// <c>natural</c> element, <c>shown</c> is collapsed while closed, and <c>fade</c> fades in after the grow and out
/// before the collapse (<see cref="AccordionMotion.Plan"/>). A toggle during a move starts from the reached height and
/// opacity. When settled the clip has no fixed height, so content that changes while open lays out normally.
/// With <c>--perf-log</c> every move is traced frame by frame for <c>tools/windows/accordion_journey.py</c>.
/// </summary>
public sealed class AccordionMover
{
    private readonly object owner;
    private readonly FrameworkElement clip;
    private readonly UIElement shown;
    private readonly FrameworkElement natural;
    private readonly UIElement fade;
    private readonly UIElement? named;
    private Storyboard? running;
    private int startFrames;
    private bool open;

    /// <summary>Rendered frames a move waits before it begins (the frame that lays the content out, then one more).</summary>
    private const int StartFrames = 2;

    /// <summary>Creates a mover over the given parts.</summary>
    /// <param name="owner">Template root or control the parts belong to.</param>
    /// <param name="clip">Element whose height animates (clips its content to its bounds).</param>
    /// <param name="shown">Element collapsed while closed.</param>
    /// <param name="natural">Element whose measured height is the open height.</param>
    /// <param name="fade">Element whose opacity fades.</param>
    /// <param name="named">Element whose AutomationId or x:Name names the trace lines (default: the owner, else the
    /// clip's parent).</param>
    public AccordionMover(object owner, FrameworkElement clip, UIElement shown, FrameworkElement natural, UIElement fade,
        UIElement? named = null)
    {
        this.owner = owner;
        this.clip = clip;
        this.shown = shown;
        this.natural = natural;
        this.fade = fade;
        this.named = named;
        open = shown.Visibility == Visibility.Visible;
        var visual = ElementCompositionPreview.GetElementVisual(clip);
        visual.Clip ??= visual.Compositor.CreateInsetClip();
    }

    /// <summary>Whether the section is open or opening.</summary>
    public bool IsOpen => open;

    /// <summary>Whether this mover drives the given template root or control.</summary>
    /// <param name="candidate">Template root or control.</param>
    /// <returns>Whether it is this mover's owner.</returns>
    public bool Owns(object candidate) => ReferenceEquals(owner, candidate);

    /// <summary>Opens or closes the section.</summary>
    /// <param name="value">Whether it should be open.</param>
    /// <param name="animate">Whether to animate (also requires <see cref="Motion.Allowed"/> and a loaded clip).</param>
    public void Set(bool value, bool animate)
    {
        var settledAt = shown.Visibility == Visibility.Visible;
        // Already settled there, or already moving there: a repeated request must not restart the move.
        if (value == open && (running is not null || settledAt == value)) return;
        open = value;
        var wasShown = settledAt;
        var height = wasShown ? clip.ActualHeight : 0;
        if (running is not null && clip.Height is var animated && !double.IsNaN(animated)) height = animated;
        var opacity = wasShown ? fade.Opacity : 0;
        Stop();
        var motion = animate && Motion.Allowed && clip.IsLoaded;
        if (!motion)
        {
            Settle(value, animated: false);
            return;
        }
        shown.Visibility = Visibility.Visible;
        var openHeight = Measure();
        var plan = AccordionMotion.Plan(value, AccordionMotion.Progress(height, openHeight), opacity, motionAllowed: true);
        if (plan.Total == TimeSpan.Zero)
        {
            Settle(value, animated: false);
            return;
        }
        clip.Height = height;
        fade.Opacity = opacity;
        var storyboard = new Storyboard();
        var spline = AccordionMotion.Spline;
        if (plan.Height.Duration > TimeSpan.Zero)
            storyboard.Children.Add(Animation(clip, "Height", value ? openHeight : 0, plan.Height, spline, dependent: true));
        if (plan.Fade.Duration > TimeSpan.Zero)
            storyboard.Children.Add(Animation(fade, "Opacity", value ? 1 : 0, plan.Fade, spline, dependent: false));
        storyboard.Completed += (sender, _) =>
        {
            if (!ReferenceEquals(sender, running)) return;
            Stop();
            Settle(value, animated: true);
        };
        running = storyboard;
        TraceMove(value, height, value ? openHeight : 0, opacity);
        startFrames = StartFrames;
        CompositionTarget.Rendering += OnStartFrame;
    }

    /// <summary>
    /// Begins the move once the section's first frame at its starting height and opacity has rendered: showing new
    /// content can stall the UI thread for its first layout (the Settings leeway slider took ~55 ms), and a storyboard
    /// begun before that stall jumped most of the grow in one frame. Nothing visible changes while it waits.
    /// </summary>
    /// <param name="sender">Ignored.</param>
    /// <param name="e">Ignored.</param>
    private void OnStartFrame(object? sender, object e)
    {
        if (running is null)
        {
            CompositionTarget.Rendering -= OnStartFrame;
            return;
        }
        if (--startFrames > 0) return;
        CompositionTarget.Rendering -= OnStartFrame;
        TraceBegin();
        running.Begin();
    }

    /// <summary>Stops the running move, leaving the values it reached as local values.</summary>
    private void Stop()
    {
        CompositionTarget.Rendering -= OnStartFrame;
        if (running is null) return;
        var reached = clip.Height;
        var opacity = fade.Opacity;
        var storyboard = running;
        running = null;
        storyboard.Stop();
        clip.Height = reached;
        fade.Opacity = opacity;
        TraceFrames();
    }

    /// <summary>Puts the section in its final open or closed state with no fixed height.</summary>
    /// <param name="value">Open.</param>
    /// <param name="animated">Whether a move led here (traced as <c>animated=1</c>).</param>
    private void Settle(bool value, bool animated)
    {
        clip.ClearValue(FrameworkElement.HeightProperty);
        fade.Opacity = value ? 1 : 0;
        shown.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
        TraceSettle(value, animated);
    }

    /// <summary>The section's natural open height at the clip's current width.</summary>
    /// <returns>Height in epx.</returns>
    private double Measure()
    {
        var width = clip.ActualWidth > 0 ? clip.ActualWidth : double.PositiveInfinity;
        natural.Measure(new Size(width, double.PositiveInfinity));
        return natural.DesiredSize.Height;
    }

    /// <summary>One eased keyframe animation for a phase.</summary>
    /// <param name="target">Animated element.</param>
    /// <param name="property">Property path.</param>
    /// <param name="to">End value.</param>
    /// <param name="phase">Start delay and duration.</param>
    /// <param name="spline">Easing control points.</param>
    /// <param name="dependent">Whether the property animates on the UI thread (layout).</param>
    /// <returns>The animation.</returns>
    private static Timeline Animation(DependencyObject target, string property, double to, AccordionPhase phase,
        (float X1, float Y1, float X2, float Y2) spline, bool dependent)
    {
        var animation = new DoubleAnimationUsingKeyFrames { BeginTime = phase.Begin, EnableDependentAnimation = dependent };
        animation.KeyFrames.Add(new SplineDoubleKeyFrame
        {
            KeyTime = KeyTime.FromTimeSpan(phase.Duration),
            Value = to,
            KeySpline = new KeySpline { ControlPoint1 = new Point(spline.X1, spline.Y1), ControlPoint2 = new Point(spline.X2, spline.Y2) },
        });
        Storyboard.SetTarget(animation, target);
        Storyboard.SetTargetProperty(animation, property);
        return animation;
    }

    #region Trace
    private List<string>? frames;
    private long moveStart;
    private string traceId = "?";

    /// <summary>The trace name: the named element's (or owner's) AutomationId or x:Name, else the clip parent's.</summary>
    private string TraceName
    {
        get
        {
            foreach (var candidate in new[] { named ?? owner as DependencyObject, VisualTreeHelper.GetParent(clip) })
            {
                if (candidate is not FrameworkElement element) continue;
                var id = Microsoft.UI.Xaml.Automation.AutomationProperties.GetAutomationId(element);
                if (string.IsNullOrEmpty(id)) id = element.Name;
                if (!string.IsNullOrEmpty(id)) return id.Replace(' ', '_');
            }
            return "?";
        }
    }

    /// <summary>
    /// Starts tracing a move (<c>--perf-log</c> only): one <c>accordion-move</c> line now, then one
    /// <c>accordion-frame</c> line per rendered frame until it stops (written together then, so tracing never costs a
    /// frame a file write), so a journey can check that the height moves while the content is hidden and the opacity
    /// moves at full height (load-transition R10).
    /// </summary>
    /// <param name="value">Opening.</param>
    /// <param name="from">Starting height.</param>
    /// <param name="to">Target height.</param>
    /// <param name="opacity">Starting opacity.</param>
    private void TraceMove(bool value, double from, double to, double opacity)
    {
        if (!PerfLog.Enabled) return;
        moveStart = Stopwatch.GetTimestamp();
        frames = [];
        traceId = TraceName;
        PerfLog.Write(FormattableString.Invariant(
            $"accordion-move id={traceId} open={(value ? 1 : 0)} from={from:F1} to={to:F1} opacity={opacity:F3}"));
        CompositionTarget.Rendering += OnTraceFrame;
    }

    /// <summary>Marks when the waiting move began (<c>accordion-begin</c>, <c>t</c> since the toggle).</summary>
    private void TraceBegin()
    {
        if (frames is null) return;
        frames.Add(FormattableString.Invariant(
            $"accordion-begin id={traceId} t={Stopwatch.GetElapsedTime(moveStart).TotalMilliseconds:F0}"));
    }

    /// <summary>Records the clip's laid-out height and the content's opacity for one rendered frame.</summary>
    /// <param name="sender">Ignored.</param>
    /// <param name="e">Ignored.</param>
    private void OnTraceFrame(object? sender, object e)
    {
        if (frames is null || running is null) return;
        var t = Stopwatch.GetElapsedTime(moveStart).TotalMilliseconds;
        frames.Add(FormattableString.Invariant(
            $"accordion-frame id={traceId} t={t:F0} height={clip.ActualHeight:F1} opacity={fade.Opacity:F3}"));
    }

    /// <summary>Writes the stopped move's frames.</summary>
    private void TraceFrames()
    {
        CompositionTarget.Rendering -= OnTraceFrame;
        if (frames is null) return;
        if (frames.Count > 0) PerfLog.Write(string.Join(Environment.NewLine, frames));
        frames = null;
    }

    /// <summary>Writes where the section settled and whether a move led there (<c>--perf-log</c> only).</summary>
    /// <param name="value">Open.</param>
    /// <param name="animated">Whether a move led here.</param>
    private void TraceSettle(bool value, bool animated)
    {
        TraceFrames();
        if (!PerfLog.Enabled) return;
        if (!animated) traceId = TraceName;
        var t = animated ? Stopwatch.GetElapsedTime(moveStart).TotalMilliseconds : 0;
        PerfLog.Write(FormattableString.Invariant(
            $"accordion-settle id={traceId} open={(value ? 1 : 0)} animated={(animated ? 1 : 0)} motion={(Motion.Allowed ? 1 : 0)} t={t:F0}"));
    }
    #endregion
}
#endregion
