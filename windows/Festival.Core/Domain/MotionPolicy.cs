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

    /// <summary>
    /// Web Suggestions <c>getCardDelay</c>: rows before <paramref name="batchStart"/> were already revealed and show
    /// without animation; a newly loaded batch staggers from its own first row.
    /// </summary>
    /// <param name="index">Row index (0-based) in the whole list.</param>
    /// <param name="batchStart">Index of the batch's first row (0 for a fresh list).</param>
    /// <param name="maxItems">Rows that stagger (the visible count).</param>
    /// <returns>Delay, or <see langword="null"/> when the row shows without animation.</returns>
    public static TimeSpan? BatchDelay(int index, int batchStart, int maxItems) =>
        index < batchStart ? null : StaggerDelay(index - Math.Max(0, batchStart), maxItems);

    /// <summary>
    /// The batch start after another batch arrives: batches appended back to back (a fast scroll that cascades
    /// incremental loads) form one reveal from the earliest unrevealed row; a batch after the window starts its own.
    /// </summary>
    /// <param name="current">Start of the batch still armed.</param>
    /// <param name="next">Start of the batch just added.</param>
    /// <param name="sinceArmed">Time since <paramref name="current"/> was armed.</param>
    /// <returns>Start to arm.</returns>
    public static int MergeBatchStart(int current, int next, TimeSpan sinceArmed) =>
        WithinWindow(sinceArmed) ? Math.Min(current, next) : next;

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

#region Stagger arm
/// <summary>
/// One list's stagger window (pattern <c>load-transition</c> R5, issue #260): which freshly realized rows still fade in.
/// A load arm (a new or re-sorted list, <c>batchStart</c> 0) closes at the first scroll movement, so rows realized by
/// scrolling (even within <see cref="FadeInTiming.ArmWindow"/>) just appear; an appended batch (Suggestions' incremental
/// loading, <c>batchStart</c> &gt; 0) is revealed by scrolling and stays open for its window. The scroll position is
/// anchored once the arm's first layout settles (<see cref="Settle"/>), so a page's own reset to the top as part of the
/// reload doesn't count as the reader scrolling. It also remembers when each row's fade starts (<see cref="Played"/>),
/// so a selected-row reveal can wait for that row's own entrance and then rush the fades that haven't begun
/// (<see cref="RevealWait"/>, <see cref="Rush"/>; patterns <c>leaderboard-row</c> R7 and <c>load-transition</c> R5,
/// issue #307).
/// </summary>
public sealed class StaggerArm
{
    /// <summary>Scroll movement (epx) that counts as the reader scrolling; smaller changes are layout rounding.</summary>
    public const double ScrollSlop = 1;

    private readonly Dictionary<int, (TimeSpan ScheduledAt, TimeSpan Delay)> entrances = [];
    private TimeSpan armedAt;
    private bool armed;
    private bool closed;
    private int timeOnlyStart;
    private bool closesOnScroll;
    private int? appendedStart;
    private (double X, double Y)? anchor;

    /// <summary>Creates a closed arm.</summary>
    /// <param name="window">How long an arm stays open without scrolling (default <see cref="FadeInTiming.ArmWindow"/>;
    /// UI journeys lengthen it with <see cref="ParseWindow"/> so a scripted scroll lands inside it).</param>
    public StaggerArm(TimeSpan? window = null) => Window = window ?? FadeInTiming.ArmWindow;

    /// <summary>How long an arm stays open without scrolling.</summary>
    public TimeSpan Window { get; }

    /// <summary>Parses a window override in milliseconds (Debug/automation <c>FST_DEBUG_FADE_WINDOW_MS</c>).</summary>
    /// <param name="milliseconds">Raw value.</param>
    /// <returns>Window between 1 ms and 60 s, else <see langword="null"/> (use the default).</returns>
    public static TimeSpan? ParseWindow(string? milliseconds) =>
        int.TryParse(milliseconds, System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var ms)
        && ms is > 0 and <= 60_000 ? TimeSpan.FromMilliseconds(ms) : null;

    /// <summary>First row of the newest batch (rows before it never fade).</summary>
    public int BatchStart { get; private set; }

    /// <summary>Counts arms, so work scheduled for one load (a selected-row reveal) can tell a newer load replaced it.</summary>
    public int Generation { get; private set; }

    /// <summary>Whether the reader scrolled the list since its last load arm (a reveal then leaves the list alone).</summary>
    public bool ScrolledSinceLoad { get; private set; }

    /// <summary>Arms the window for a load (<paramref name="batchStart"/> 0) or an appended batch.</summary>
    /// <param name="batchStart">Index of the batch's first row (0 when the whole list is new).</param>
    /// <param name="now">Monotonic time.</param>
    public void Arm(int batchStart, TimeSpan now)
    {
        Generation++;
        if (batchStart <= 0)
        {
            entrances.Clear();
            ScrolledSinceLoad = false;
        }
        var open = IsOpen(now);
        // What a purely time-based window (no scroll close) would stagger from: kept only to trace R5's suppressions.
        timeOnlyStart = armed && Within(now) ? Math.Min(timeOnlyStart, batchStart) : batchStart;
        // Batches appended back to back form one reveal (FadeInTiming.MergeBatchStart within this arm's window).
        BatchStart = open ? Math.Min(BatchStart, batchStart) : batchStart;
        var appended = batchStart > 0;
        if (open && closesOnScroll && appended)
        {
            // A batch that lands while the load arm is still open joins its reveal; a later scroll keeps only the batch.
            appendedStart = Math.Min(appendedStart ?? batchStart, batchStart);
        }
        else
        {
            closesOnScroll = !appended;
            appendedStart = null;
            anchor = null;
        }
        armedAt = now;
        armed = true;
        closed = false;
    }

    /// <summary>Anchors the scroll position the load arm measures movement from, once its first layout settled.</summary>
    /// <param name="x">Horizontal offset (epx).</param>
    /// <param name="y">Vertical offset (epx).</param>
    public void Settle(double x, double y)
    {
        if (closesOnScroll && anchor is null && double.IsFinite(x) && double.IsFinite(y)) anchor = (x, y);
    }

    /// <summary>Whether the arm still waits for <see cref="Settle"/> (its first layout after arming).</summary>
    public bool NeedsSettle => armed && !closed && closesOnScroll && anchor is null;

    /// <summary>
    /// Records a scroll position: movement from the anchor closes the load arm (keeping only a batch appended into it).
    /// </summary>
    /// <param name="x">Horizontal offset (epx).</param>
    /// <param name="y">Vertical offset (epx).</param>
    /// <returns><see langword="true"/> when this movement closed the load arm (<see cref="BatchStart"/> is then the
    /// kept batch's first row, or the load's 0 when nothing stays open).</returns>
    public bool Scrolled(double x, double y)
    {
        if (!closesOnScroll || closed || anchor is not { } at) return false;
        if (!(Math.Abs(x - at.X) >= ScrollSlop || Math.Abs(y - at.Y) >= ScrollSlop)) return false;
        closesOnScroll = false;
        ScrolledSinceLoad = true;
        if (appendedStart is { } start)
        {
            BatchStart = start;
            appendedStart = null;
        }
        else
        {
            closed = true;
        }
        return true;
    }

    /// <summary>Whether rows realized now may still fade (armed, within the window and not closed by a scroll).</summary>
    /// <param name="now">Monotonic time.</param>
    /// <returns>Whether the window is open.</returns>
    public bool IsOpen(TimeSpan now) => armed && !closed && Within(now);

    /// <summary>Time since the last arm (for the fade trace).</summary>
    /// <param name="now">Monotonic time.</param>
    /// <returns>Elapsed time, or <see cref="TimeSpan.Zero"/> before the first arm.</returns>
    public TimeSpan SinceArmed(TimeSpan now) => armed ? now - armedAt : TimeSpan.Zero;

    /// <summary>
    /// Whether a row realized now shows in place only because a scroll closed the load window (R5's case): a purely
    /// time-based window would still have faded it.
    /// </summary>
    /// <param name="now">Monotonic time.</param>
    /// <param name="index">Row index.</param>
    /// <param name="visible">Rows that stagger (the visible count).</param>
    /// <returns><see langword="true"/> for a row the scroll close kept from fading.</returns>
    public bool SuppressedByScroll(TimeSpan now, int index, int visible) =>
        armed && Within(now)
        && FadeInTiming.BatchDelay(index, timeOnlyStart, visible) is not null
        && !(IsOpen(now) && FadeInTiming.BatchDelay(index, BatchStart, visible) is not null);

    /// <summary>Whether <paramref name="now"/> falls inside this arm's window.</summary>
    /// <param name="now">Monotonic time.</param>
    /// <returns>Whether the window has not run out.</returns>
    private bool Within(TimeSpan now) => now - armedAt >= TimeSpan.Zero && now - armedAt < Window;

    /// <summary>The fade delay of a row realized now, at the given scroll position.</summary>
    /// <param name="index">Row index.</param>
    /// <param name="visible">Rows that stagger (the visible count).</param>
    /// <param name="now">Monotonic time.</param>
    /// <param name="x">Horizontal offset (epx) of the list's scroller.</param>
    /// <param name="y">Vertical offset (epx) of the list's scroller.</param>
    /// <returns>Delay, or <see langword="null"/> when the row shows in place.</returns>
    public TimeSpan? Delay(int index, int visible, TimeSpan now, double x, double y)
    {
        Scrolled(x, y);
        return IsOpen(now) ? FadeInTiming.BatchDelay(index, BatchStart, visible) : null;
    }

    /// <summary>Records a row's fade (it starts <paramref name="delay"/> after <paramref name="now"/>).</summary>
    /// <param name="index">Row index.</param>
    /// <param name="delay">Stagger delay.</param>
    /// <param name="now">Monotonic time.</param>
    public void Played(int index, TimeSpan delay, TimeSpan now) => entrances[index] = (now, delay < TimeSpan.Zero ? TimeSpan.Zero : delay);

    /// <summary>Forgets a row's fade: it was shown in place (recycled, motion off) or its element is gone.</summary>
    /// <param name="index">Row index.</param>
    public void Shown(int index) => entrances.Remove(index);

    /// <summary>A row's recorded fade.</summary>
    /// <param name="index">Row index.</param>
    /// <param name="now">Monotonic time.</param>
    /// <returns>Its stagger delay and the time since it was scheduled, or <see langword="null"/> for a row that never faded.</returns>
    public (TimeSpan Delay, TimeSpan Since)? Entrance(int index, TimeSpan now) =>
        entrances.TryGetValue(index, out var e) ? (e.Delay, now - e.ScheduledAt) : null;

    /// <summary>
    /// How long a selected-row reveal waits: until that row's own fade has finished (its stagger delay plus
    /// <see cref="FadeInTiming.Duration"/>), like web <c>navToPlayer</c>/<c>navToBand</c> (<c>load-transition</c> R5).
    /// </summary>
    /// <param name="index">Selected row index.</param>
    /// <param name="now">Monotonic time.</param>
    /// <returns>Time left; zero for a row without a running fade.</returns>
    public TimeSpan RevealWait(int index, TimeSpan now)
    {
        if (!entrances.TryGetValue(index, out var e)) return TimeSpan.Zero;
        var left = e.ScheduledAt + e.Delay + FadeInTiming.Duration - now;
        return left > TimeSpan.Zero ? left : TimeSpan.Zero;
    }

    /// <summary>
    /// Starts every recorded fade that hasn't begun yet now (web <c>useStaggerRush</c>, <c>load-transition</c> R5): the
    /// caller replays them without delay, so the rest of the entrance fades in together. Fades already running keep going.
    /// </summary>
    /// <param name="now">Monotonic time.</param>
    /// <returns>Rushed rows in index order, each with the stagger delay it had.</returns>
    public IReadOnlyList<(int Index, TimeSpan Delay)> Rush(TimeSpan now)
    {
        var pending = entrances
            .Where(e => e.Value.ScheduledAt + e.Value.Delay > now)
            .OrderBy(e => e.Key)
            .Select(e => (e.Key, e.Value.Delay))
            .ToList();
        foreach (var (index, _) in pending) entrances[index] = (now, TimeSpan.Zero);
        return pending;
    }
}
#endregion

#region Pinned row reveal
/// <summary>
/// When the selected player's pinned leaderboard row (the footer "your score" row) fades in (issue #295). It shares the
/// rows' load gate, so it is hidden while a page loads and enters with the board's first row; a row that only arrives
/// after the board is showing (the score index loaded late) fades in on its own instead of popping in.
/// </summary>
public static class PinnedRowReveal
{
    /// <summary>Delay of the pinned row's <c>fadeInUp</c> when the board reveals: the first row's stagger delay.</summary>
    public static TimeSpan RevealDelay => FadeInTiming.StaggerDelay(0, FadeInTiming.MaxStaggered)!.Value;

    /// <summary>Whether a pinned row change should fade the row in by itself, outside a board reveal.</summary>
    /// <param name="hadRow">Whether a pinned row was shown before the change.</param>
    /// <param name="hasRow">Whether a pinned row is shown after the change.</param>
    /// <param name="phase">Board load phase at the change.</param>
    /// <returns><see langword="true"/> only for a row that newly appears over an already revealed board.</returns>
    public static bool FadesOnArrival(bool hadRow, bool hasRow, LoadSwapPhase phase) =>
        !hadRow && hasRow && phase == LoadSwapPhase.ContentIn;
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
