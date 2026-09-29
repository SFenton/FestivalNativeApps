using System.Diagnostics;
using System.Numerics;
using Festival.App.Services;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;

namespace Festival.App.Controls;

#region Fade in
/// <summary>
/// The web's <c>fadeInUp</c> for native content (<see cref="FadeInTiming"/>: 400 ms ease-out from opacity 0 and 12 epx
/// lower). <c>FadeIn.OnShow</c> fades an element each time it becomes visible (page content bound to a loaded state);
/// <c>FadeIn.Stagger</c> on an <see cref="ItemsRepeater"/> or <see cref="ListViewBase"/> fades the rows realized just
/// after its items change, 125 ms apart, for the rows that fit the viewport (rows realized later by scrolling just
/// appear, as on the web). Both run on the compositor, leave nothing running when finished, and do nothing while
/// motion is off (<see cref="Motion.Allowed"/>).
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

    #region Stagger
    /// <summary>Stagger rows in after the list's items change.</summary>
    public static readonly DependencyProperty StaggerProperty = DependencyProperty.RegisterAttached(
        "Stagger", typeof(bool), typeof(FadeIn), new PropertyMetadata(false, OnStaggerChanged));

    /// <summary>Row height used to estimate how many rows fit (web <c>estimateVisibleCount</c>); default 48 epx.</summary>
    public static readonly DependencyProperty RowHeightProperty = DependencyProperty.RegisterAttached(
        "RowHeight", typeof(double), typeof(FadeIn), new PropertyMetadata(48.0));

    private static readonly DependencyProperty ArmedAtProperty = DependencyProperty.RegisterAttached(
        "ArmedAt", typeof(long), typeof(FadeIn), new PropertyMetadata(0L));

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
    public static void Restagger(UIElement list) => list.SetValue(ArmedAtProperty, Stopwatch.GetTimestamp());

    /// <summary>Hooks element preparation and items-source changes once.</summary>
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
        }
    }

    /// <summary>
    /// Staggers the rows a list has already realized (a list kept hidden until its first rows are ready, like Songs),
    /// then re-arms the list so rows realized in the next moments continue the sequence.
    /// </summary>
    /// <param name="list">List view.</param>
    public static void StaggerRealized(ListViewBase list)
    {
        Restagger(list);
        var visible = FadeInTiming.VisibleCount(list.XamlRoot?.Size.Height ?? list.ActualHeight, GetRowHeight(list));
        for (var i = 0; i < FadeInTiming.MaxStaggered; i++)
        {
            if (list.ContainerFromIndex(i) is not UIElement container) break;
            if (FadeInTiming.StaggerDelay(i, visible) is { } delay) Play(container, delay);
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
        var visible = FadeInTiming.VisibleCount(repeater.XamlRoot?.Size.Height ?? repeater.ActualHeight, GetRowHeight(repeater));
        var count = repeater.ItemsSourceView?.Count ?? 0;
        for (var i = 0; i < Math.Min(count, FadeInTiming.MaxStaggered); i++)
        {
            if (repeater.TryGetElement(i) is not UIElement element) continue;
            if (FadeInTiming.StaggerDelay(i, visible) is { } delay) Play(element, delay);
        }
    }

    /// <summary>Fades a freshly realized row when its list loaded moments ago and it is within the visible count.</summary>
    /// <param name="list">Owning list.</param>
    /// <param name="element">Row element.</param>
    /// <param name="index">Row index.</param>
    private static void Prepare(FrameworkElement list, UIElement element, int index)
    {
        var armedAt = (long)list.GetValue(ArmedAtProperty);
        var visible = FadeInTiming.VisibleCount(list.XamlRoot?.Size.Height ?? list.ActualHeight, GetRowHeight(list));
        if (FadeInTiming.WithinWindow(Stopwatch.GetElapsedTime(armedAt))
            && FadeInTiming.StaggerDelay(index, visible) is { } delay)
            Play(element, delay);
        else
            Reset(element);
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
