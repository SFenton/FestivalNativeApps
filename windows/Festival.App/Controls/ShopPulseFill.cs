using System.Numerics;
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

#region Shop pulse fill
/// <summary>
/// The Item Shop button's status fill (web <c>shopBreathe</c>, <c>shopBreatheGold</c>, <c>shopBreatheRed</c>): a
/// status-coloured layer behind the label that breathes from transparent (the button's opaque surface shows) to full and
/// back every 3 s with ease-in-out, on the compositor. It holds the status colour when highlighting is off, motion is
/// off (<see cref="Motion.Allowed"/>) or the window is hidden (<see cref="Motion.Paused"/>), so nothing loops unseen.
/// Decorative for UI Automation: the button's name carries the status.
/// </summary>
public sealed partial class ShopPulseFill : Grid
{
    private ShopHighlight? highlight;
    private bool pulses;
    private bool running;

    /// <summary>Creates the fill (hidden from UI Automation, not hit-testable).</summary>
    public ShopPulseFill()
    {
        IsHitTestVisible = false;
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        Loaded += (_, _) => { Motion.Changed += OnMotionChanged; Update(); };
        Unloaded += (_, _) => { Motion.Changed -= OnMotionChanged; Stop(); };
    }

    /// <summary>Sets the status and whether it breathes.</summary>
    /// <param name="value">New / Leaving Tomorrow, or <see langword="null"/> for a plain in-Shop offer (green).</param>
    /// <param name="breathe">Whether Shop highlighting is on (off holds a static green, like the web's plain button).</param>
    public void Apply(ShopHighlight? value, bool breathe)
    {
        highlight = value;
        pulses = breathe;
        var argb = ShopPulse.TargetArgb(breathe ? value : null);
        Background = new SolidColorBrush(Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb));
        Stop();
        Update();
    }

    /// <summary>Re-evaluates when motion settings or window visibility change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnMotionChanged(object? sender, EventArgs e) => Update();

    /// <summary>Starts or stops the breathe for the current state.</summary>
    private void Update()
    {
        var animate = IsLoaded && pulses && Motion.Allowed && !Motion.Paused;
        if (animate == running) return;
        if (!animate)
        {
            Stop();
            return;
        }
        var visual = ElementCompositionPreview.GetElementVisual(this);
        var compositor = visual.Compositor;
        var ease = compositor.CreateCubicBezierEasingFunction(new Vector2(0.42f, 0f), new Vector2(0.58f, 1f));
        var breathe = compositor.CreateScalarKeyFrameAnimation();
        breathe.InsertKeyFrame(0f, 0f);
        breathe.InsertKeyFrame(0.5f, 1f, ease);
        breathe.InsertKeyFrame(1f, 0f, ease);
        breathe.Duration = ShopPulse.Cycle;
        breathe.IterationBehavior = AnimationIterationBehavior.Forever;
        visual.StartAnimation("Opacity", breathe);
        running = true;
    }

    /// <summary>Stops the breathe and holds the status colour.</summary>
    private void Stop()
    {
        if (!running) return;
        var visual = ElementCompositionPreview.GetElementVisual(this);
        visual.StopAnimation("Opacity");
        visual.Opacity = 1;
        running = false;
    }

    /// <summary>Current status (for tests and diagnostics).</summary>
    public ShopHighlight? Highlight => highlight;
}
#endregion
