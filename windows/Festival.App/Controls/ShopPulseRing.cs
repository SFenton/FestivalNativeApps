using Festival.App.Services;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Festival.App.Controls;

#region Songs row Shop ring
/// <summary>
/// The Songs row's pulsing Item Shop border (<see cref="SongRowShopPulse"/>): a 2 epx, 8 epx-radius ring over the card whose opacity
/// follows one shared compositor clock (<see cref="ShopPulseClock"/>), so any number of realized rows cost a single
/// keyframe animation. Holds still at the peak opacity when motion is off; decorative for UI Automation (the row's
/// name carries the Shop state).
/// </summary>
public sealed partial class ShopPulseRing : Grid
{
    private readonly Border ring = new() { BorderThickness = new Thickness(SongRowShopPulse.Thickness), CornerRadius = new CornerRadius(8) };
    private SongRowShopPulse? pulse;
    private bool attached;

    /// <summary>Creates a hidden ring.</summary>
    public ShopPulseRing()
    {
        IsHitTestVisible = false;
        Children.Add(ring);
        Visibility = Visibility.Collapsed;
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        Loaded += (_, _) => Attach();
        Unloaded += (_, _) => Detach();
    }

    /// <summary>Shows a pulse, or hides the ring for <see langword="null"/> (row recycling calls this every time).</summary>
    /// <param name="value">Pulse.</param>
    public void Apply(SongRowShopPulse? value)
    {
        if (value == pulse) return;
        Detach();
        pulse = value;
        if (value is null)
        {
            Visibility = Visibility.Collapsed;
            return;
        }
        // Contrast themes: the system Highlight instead of the brand gold/red (the row's UIA name carries the Shop state).
        ring.BorderBrush = Services.ContrastTheme.IsOn ? Services.ContrastTheme.Brush("FSTShopNewBrush")
            : new SolidColorBrush(Color.FromArgb(0xFF, (byte)(value.Argb >> 16), (byte)(value.Argb >> 8), (byte)value.Argb));
        Visibility = Visibility.Visible;
        if (IsLoaded) Attach();
    }

    /// <summary>Binds this ring's opacity to the shared clock.</summary>
    private void Attach()
    {
        if (attached || pulse is null) return;
        var visual = ElementCompositionPreview.GetElementVisual(this);
        var opacity = visual.Compositor.CreateExpressionAnimation("clock.Level * peak");
        opacity.SetReferenceParameter("clock", ShopPulseClock.Acquire(visual.Compositor));
        opacity.SetScalarParameter("peak", pulse.PeakOpacity);
        visual.StartAnimation("Opacity", opacity);
        attached = true;
    }

    /// <summary>Releases the clock.</summary>
    private void Detach()
    {
        if (!attached) return;
        var visual = ElementCompositionPreview.GetElementVisual(this);
        visual.StopAnimation("Opacity");
        visual.Opacity = 1;
        ShopPulseClock.Release();
        attached = false;
    }
}
#endregion

#region Shared clock
/// <summary>
/// One compositor property (<c>Level</c>, 0…1) that every visible Shop ring follows. It breathes 0 → 1 → 0 over
/// <see cref="SongRowShopPulse.Cycle"/> with ease-in-out, sampled at <see cref="StepsPerSecond"/> held keyframes (smooth
/// at that rate, and the compositor redraws only on each step instead of at display refresh); it holds at 1 when
/// motion is off (<see cref="Motion.Allowed"/>), while the window is hidden (<see cref="Motion.Paused"/>) or when no
/// ring is visible.
/// </summary>
public static class ShopPulseClock
{
    /// <summary>Level updates per second.</summary>
    public const int StepsPerSecond = 30;

    private static CompositionPropertySet? clock;
    private static int users;
    private static bool running;

    /// <summary>Adds a ring and returns the clock.</summary>
    /// <param name="compositor">Window compositor.</param>
    /// <returns>Property set with a <c>Level</c> scalar.</returns>
    public static CompositionPropertySet Acquire(Compositor compositor)
    {
        if (clock is null)
        {
            clock = compositor.CreatePropertySet();
            clock.InsertScalar("Level", 1f);
            Motion.Changed += (_, _) => Update();
        }
        users++;
        Update();
        return clock;
    }

    /// <summary>Removes a ring.</summary>
    public static void Release()
    {
        users = Math.Max(0, users - 1);
        Update();
    }

    /// <summary>Runs or holds the clock for the current users and motion state.</summary>
    private static void Update()
    {
        if (clock is null) return;
        var animate = users > 0 && Motion.Allowed && !Motion.Paused;
        if (animate == running) return;
        running = animate;
        if (!animate)
        {
            clock.StopAnimation("Level");
            clock.InsertScalar("Level", 1f);
            return;
        }
        var compositor = clock.Compositor;
        var breathe = compositor.CreateScalarKeyFrameAnimation();
        var steps = (int)(SongRowShopPulse.Cycle.TotalSeconds * StepsPerSecond);
        var hold = compositor.CreateStepEasingFunction(1);
        for (var i = 0; i <= steps; i++)
        {
            var t = (float)i / steps;
            breathe.InsertKeyFrame(t, SongRowShopPulse.Level(t), hold);
        }
        breathe.Duration = SongRowShopPulse.Cycle;
        breathe.IterationBehavior = AnimationIterationBehavior.Forever;
        clock.StartAnimation("Level", breathe);
    }
}
#endregion
