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
/// back every 3 s with ease-in-out, on the compositor, sampled at <see cref="ShopPulse.StepsPerSecond"/> held keyframes so
/// it redraws on each step rather than at display refresh. It holds the status colour when highlighting is off, motion
/// is off (<see cref="Motion.Allowed"/>), the window is hidden (<see cref="Motion.Paused"/>) or its first-run slide is
/// not the visible one (<see cref="Live"/>), so nothing loops unseen.
/// Decorative for UI Automation: the button's name carries the status.
/// </summary>
public sealed partial class ShopPulseFill : Grid
{
    private ShopHighlight? highlight;
    private bool pulses;
    private bool running;
    private bool live = true;
    private readonly Windows.UI.ViewManagement.UISettings uiSettings = new();

    /// <summary>Creates the fill (hidden from UI Automation, not hit-testable).</summary>
    public ShopPulseFill()
    {
        IsHitTestVisible = false;
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        Loaded += (_, _) =>
        {
            Motion.Changed += OnMotionChanged;
            uiSettings.ColorValuesChanged -= OnColorValuesChanged;
            uiSettings.ColorValuesChanged += OnColorValuesChanged;
            Update();
        };
        Unloaded += (_, _) =>
        {
            Motion.Changed -= OnMotionChanged;
            uiSettings.ColorValuesChanged -= OnColorValuesChanged;
            Stop();
        };
    }

    /// <summary>Sets the status and whether it breathes.</summary>
    /// <param name="value">New / Leaving Tomorrow, or <see langword="null"/> for a plain in-Shop offer (green).</param>
    /// <param name="breathe">Whether Shop highlighting is on (off holds a static green, like the web's plain button).</param>
    public void Apply(ShopHighlight? value, bool breathe)
    {
        highlight = value;
        pulses = breathe;
        var argb = ShopPulse.TargetArgb(breathe ? value : null);
        // Contrast themes: the system Highlight instead of the brand red/gold/green (the label names the state).
        Background = Services.ContrastTheme.IsOn ? Services.ContrastTheme.Brush("FSTShopNewBrush")
            : new SolidColorBrush(Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb));
        Stop();
        Update();
    }

    /// <summary>
    /// Whether the fill may breathe (default <see langword="true"/>). First-run demos clear it on slides that are not
    /// the visible one, so realized neighbours hold the status colour instead of animating unseen.
    /// </summary>
    public bool Live
    {
        get => live;
        set
        {
            if (live == value) return;
            live = value;
            Update();
        }
    }

    /// <summary>Re-evaluates when motion settings or window visibility change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnMotionChanged(object? sender, EventArgs e) => Update();

    /// <summary>Re-resolves the status colour when a contrast theme is switched on or off (ColorValuesChanged).</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="args">Unused.</param>
    private void OnColorValuesChanged(Windows.UI.ViewManagement.UISettings sender, object args) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            if (Background is not null) Apply(highlight, pulses);
        });

    /// <summary>Starts or stops the breathe for the current state.</summary>
    private void Update()
    {
        var animate = IsLoaded && pulses && live && Motion.Allowed && !Motion.Paused;
        if (animate == running) return;
        if (!animate)
        {
            Stop();
            return;
        }
        var visual = ElementCompositionPreview.GetElementVisual(this);
        var compositor = visual.Compositor;
        var hold = compositor.CreateStepEasingFunction(1);
        var breathe = compositor.CreateScalarKeyFrameAnimation();
        foreach (var (progress, level) in ShopPulse.BreatheSteps()) breathe.InsertKeyFrame(progress, level, hold);
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
