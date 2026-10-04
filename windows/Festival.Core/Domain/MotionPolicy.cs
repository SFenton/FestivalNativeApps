namespace Festival.Core.Domain;

#region Fade-in timing
/// <summary>
/// Content fade-in timing ported from the web (<c>packages/theme/src/animation.ts</c>, <c>styles/animations.css</c>,
/// <c>packages/ui-utils/src/stagger.ts</c>): <c>fadeInUp</c> is 400 ms <c>ease-out</c> from opacity 0 and 12 px below,
/// and list rows stagger by 125 ms, starting one interval in, for the rows that fit in the viewport. Rows beyond that
/// (or realized later by scrolling) appear without animation.
/// </summary>
public static class FadeInTiming
{
    /// <summary>Web <c>FADE_DURATION</c>.</summary>
    public static readonly TimeSpan Duration = TimeSpan.FromMilliseconds(400);

    /// <summary>
    /// Fade-out for a control leaving the page (<c>FadeIn.OnHide</c>): WinUI's <c>ControlFastAnimationDuration</c>, so
    /// exits stay quicker than entrances, as Fluent motion asks.
    /// </summary>
    public static readonly TimeSpan HideDuration = TimeSpan.FromMilliseconds(167);

    /// <summary>Web <c>STAGGER_INTERVAL</c>.</summary>
    public static readonly TimeSpan Interval = TimeSpan.FromMilliseconds(125);

    /// <summary>How long after a list (re)loads newly realized rows may still stagger in.</summary>
    public static readonly TimeSpan ArmWindow = TimeSpan.FromMilliseconds(1000);

    /// <summary>Upper bound on staggered rows whatever the viewport (keeps the last row's delay under 2.5 s).</summary>
    public const int MaxStaggered = 20;

    /// <summary>The web's <c>fadeInUp</c> starting offset in epx.</summary>
    public const float OffsetY = 12;

    /// <summary>CSS <c>ease-out</c>: <c>cubic-bezier(0, 0, 0.58, 1)</c>.</summary>
    public static readonly (float X1, float Y1, float X2, float Y2) EaseOut = (0f, 0f, 0.58f, 1f);

    /// <summary>Web <c>staggerDelay</c>: <c>(index + 1) × interval</c> for rows within <paramref name="maxItems"/>.</summary>
    /// <param name="index">Row index (0-based).</param>
    /// <param name="maxItems">Rows that stagger (the visible count).</param>
    /// <returns>Delay, or <see langword="null"/> when the row shows without animation.</returns>
    public static TimeSpan? StaggerDelay(int index, int maxItems) =>
        index >= 0 && index < Math.Min(maxItems, MaxStaggered) ? Interval * (index + 1) : null;

    /// <summary>Web <c>estimateVisibleCount</c>: rows of <paramref name="itemHeight"/> that fit, plus one partial row.</summary>
    /// <param name="viewportHeight">Viewport height in epx.</param>
    /// <param name="itemHeight">Row height in epx.</param>
    /// <returns>Visible rows (at least 1).</returns>
    public static int VisibleCount(double viewportHeight, double itemHeight) =>
        itemHeight <= 0 || !double.IsFinite(viewportHeight) || viewportHeight <= 0
            ? 1
            : (int)Math.Min(MaxStaggered, Math.Ceiling(viewportHeight / itemHeight) + 1);

    /// <summary>Whether a row realized <paramref name="sinceArmed"/> after its list loaded still animates.</summary>
    /// <param name="sinceArmed">Time since the list's items changed.</param>
    /// <returns><see langword="true"/> within <see cref="ArmWindow"/>.</returns>
    public static bool WithinWindow(TimeSpan sinceArmed) => sinceArmed >= TimeSpan.Zero && sinceArmed < ArmWindow;
}
#endregion

#region Motion switches
/// <summary>Whether decorative motion (fade-ins, pulses, marquees) may run.</summary>
public static class MotionSwitch
{
    /// <summary>Motion runs only when Windows "Animation effects" is on and neither Reduce Motion switch is set.</summary>
    /// <param name="systemAnimationsEnabled"><c>UISettings.AnimationsEnabled</c>.</param>
    /// <param name="appReduceMotion">In-app Reduce Motion.</param>
    /// <param name="launchReduceMotion"><c>--reduce-motion</c>.</param>
    /// <returns>Whether to animate.</returns>
    public static bool Allowed(bool systemAnimationsEnabled, bool appReduceMotion, bool launchReduceMotion) =>
        systemAnimationsEnabled && !appReduceMotion && !launchReduceMotion;
}
#endregion

#region Shop pulse
/// <summary>
/// The Song Detail Item Shop button's status "breathe" (web <c>animations.module.css</c> <c>shopBreathe*</c>): the
/// background eases from the opaque card surface to the status colour and back every 3 s (<c>ease-in-out</c>); under
/// reduced motion it holds the status colour. Gold is New, green is in the Shop, red is Leaving Tomorrow.
/// </summary>
public static class ShopPulse
{
    /// <summary>One breathe cycle.</summary>
    public static readonly TimeSpan Cycle = TimeSpan.FromSeconds(3);

    /// <summary>
    /// Breathe updates per second: the compositor holds each sampled level, so it redraws on each step instead of at
    /// display refresh (120–240 Hz), like <c>ShopPulseClock</c> and the backdrop drift.
    /// </summary>
    public const int StepsPerSecond = 30;

    /// <summary>Held keyframes for one breathe: the ease-in-out level (0 → 1 → 0) sampled <see cref="StepsPerSecond"/> times a second.</summary>
    /// <returns>Progress (0…1) and level (0…1) pairs, first and last at progress 0 and 1.</returns>
    public static IReadOnlyList<(float Progress, float Level)> BreatheSteps()
    {
        var steps = (int)(Cycle.TotalSeconds * StepsPerSecond);
        var frames = new (float, float)[steps + 1];
        for (var i = 0; i <= steps; i++)
        {
            var t = (float)i / steps;
            frames[i] = (t, SongRowShopPulse.Level(t));
        }
        return frames;
    }

    /// <summary>Resting colour, web <c>rgb(18 24 38 / 96%)</c> (ARGB).</summary>
    public const uint BaseArgb = 0xF5121826;

    /// <summary>Status colour at the peak of the breathe (ARGB).</summary>
    /// <param name="highlight">Shop state; <see langword="null"/> is a plain in-Shop offer.</param>
    /// <returns>Gold stroke <c>#CFA500</c>, leaving red <c>#EF4444</c> or green stroke <c>#1E7F46</c>.</returns>
    public static uint TargetArgb(ShopHighlight? highlight) => highlight switch
    {
        ShopHighlight.New => 0xFFCFA500,
        ShopHighlight.LeavingTomorrow => 0xFFEF4444,
        _ => 0xFF1E7F46,
    };

    /// <summary>Accessible name of the Item Shop button, carrying the removed badge's text.</summary>
    /// <param name="highlight">Shop state, or <see langword="null"/>.</param>
    /// <returns>"Open in Item Shop, Leaving Tomorrow" or "Open in Item Shop".</returns>
    public static string ButtonName(ShopHighlight? highlight) =>
        "Open in Item Shop" + (highlight is { } h ? ", " + h.Label() : "");
}
#endregion
