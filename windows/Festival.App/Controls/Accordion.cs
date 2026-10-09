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
/// Expander, which replaces the template's slide-in storyboards with this sequence; other disclosure panels
/// (<see cref="InstrumentSelector"/> details) drive an <see cref="AccordionMover"/> directly. The Expander's own header,
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
        var mover = new AccordionMover(root, clip, body, body, content);
        expander.SetValue(MoverProperty, mover);
        mover.Set(expander.IsExpanded, animate: false);
    }

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
/// </summary>
public sealed class AccordionMover
{
    private readonly object owner;
    private readonly FrameworkElement clip;
    private readonly UIElement shown;
    private readonly FrameworkElement natural;
    private readonly UIElement fade;
    private Storyboard? running;
    private bool open;

    /// <summary>Creates a mover over the given parts.</summary>
    /// <param name="owner">Template root or control the parts belong to.</param>
    /// <param name="clip">Element whose height animates (clips its content to its bounds).</param>
    /// <param name="shown">Element collapsed while closed.</param>
    /// <param name="natural">Element whose measured height is the open height.</param>
    /// <param name="fade">Element whose opacity fades.</param>
    public AccordionMover(object owner, FrameworkElement clip, UIElement shown, FrameworkElement natural, UIElement fade)
    {
        this.owner = owner;
        this.clip = clip;
        this.shown = shown;
        this.natural = natural;
        this.fade = fade;
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
            Settle(value);
            return;
        }
        shown.Visibility = Visibility.Visible;
        var openHeight = Measure();
        var plan = AccordionMotion.Plan(value, AccordionMotion.Progress(height, openHeight), opacity, motionAllowed: true);
        if (plan.Total == TimeSpan.Zero)
        {
            Settle(value);
            return;
        }
        clip.Height = height;
        fade.Opacity = opacity;
        var storyboard = new Storyboard();
        var spline = value ? AccordionMotion.EnterSpline : AccordionMotion.ExitSpline;
        if (plan.Height.Duration > TimeSpan.Zero)
            storyboard.Children.Add(Animation(clip, "Height", value ? openHeight : 0, plan.Height, spline, dependent: true));
        if (plan.Fade.Duration > TimeSpan.Zero)
            storyboard.Children.Add(Animation(fade, "Opacity", value ? 1 : 0, plan.Fade, spline, dependent: false));
        storyboard.Completed += (sender, _) =>
        {
            if (!ReferenceEquals(sender, running)) return;
            Stop();
            Settle(value);
        };
        running = storyboard;
        storyboard.Begin();
    }

    /// <summary>Stops the running move, leaving the values it reached as local values.</summary>
    private void Stop()
    {
        if (running is null) return;
        var reached = clip.Height;
        var opacity = fade.Opacity;
        var storyboard = running;
        running = null;
        storyboard.Stop();
        clip.Height = reached;
        fade.Opacity = opacity;
    }

    /// <summary>Puts the section in its final open or closed state with no fixed height.</summary>
    /// <param name="value">Open.</param>
    private void Settle(bool value)
    {
        clip.ClearValue(FrameworkElement.HeightProperty);
        fade.Opacity = value ? 1 : 0;
        shown.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
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
}
#endregion
