namespace Festival.Core.Domain;

#region Fade-in timing
/// <summary>
/// Content fade-in timing ported from the web (<c>packages/theme/src/animation.ts</c>, <c>styles/animations.css</c>,
/// <c>packages/ui-utils/src/stagger.ts</c>): <c>fadeInUp</c> is 400 ms <c>ease-out</c> from opacity 0 and 12 px below,
/// and list rows stagger by 125 ms, starting one interval in, for the rows that fit in the viewport. Rows below them fade
/// in with the last staggered row (<see cref="TailDelay"/>); a scroll during the entrance rushes whatever hasn't started
/// (<see cref="StaggerArm"/>, web <c>useStaggerRush</c>).
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
    /// Delay of a row below the first screen during a load (issue #323, the Apple decision B): it fades in with the last
    /// staggered row, never opaque, keeping top-to-bottom order on tall windows; a scroll before then rushes it.
    /// </summary>
    /// <param name="maxItems">Rows that stagger (the visible count).</param>
    /// <returns>The last staggered row's delay.</returns>
    public static TimeSpan TailDelay(int maxItems) => Interval * Math.Clamp(maxItems, 1, MaxStaggered);

    /// <summary>
    /// How long a selected-row reveal waits before its automatic scroll (web <c>navToPlayer</c>, issue #323): until the
    /// row's own entrance has finished, its stagger (or the tail's) plus one fade.
    /// </summary>
    /// <param name="index">The selected row's index.</param>
    /// <param name="maxItems">Rows that stagger (the visible count).</param>
    /// <returns>Wait from the board's reveal.</returns>
    public static TimeSpan RevealWait(int index, int maxItems) =>
        (StaggerDelay(Math.Max(0, index), maxItems) ?? TailDelay(maxItems)) + Duration;

    /// <summary>
    /// How long a selected-row reveal's scroll may take to realize the rows it reaches; they fade in at delay 0 while it
    /// runs (plus one fade).
    /// </summary>
    public static readonly TimeSpan RevealScroll = TimeSpan.FromMilliseconds(500);

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
/// <summary>What a scroll movement did to a <see cref="StaggerArm"/>.</summary>
public enum ArmScroll
{
    /// <summary>Nothing: not a load arm, already closed, not settled yet or less than <see cref="StaggerArm.ScrollSlop"/>.</summary>
    None,

    /// <summary>The scroll came after the entrance had finished: the arm closed and nothing replays (R5).</summary>
    Closed,

    /// <summary>
    /// The scroll came while the entrance was running: every fade that hasn't started must start now, and rows realized
    /// in the next moments fade in with them (web <c>useStaggerRush</c>, issue #323).
    /// </summary>
    Rushed,
}

/// <summary>
/// One list's (or page's) first-load fade window (pattern <c>load-transition</c> R5, issues #260 and #323): which freshly
/// realized rows fade in and when. A load arm (a new or re-sorted list, <c>batchStart</c> 0) staggers the rows that fit
/// the viewport and fades the rows below them with the last staggered row (<see cref="FadeInTiming.TailDelay"/>), so a
/// row is never opaque while the entrance is running. The first scroll movement while the entrance runs <b>rushes</b> it
/// (<see cref="ArmScroll.Rushed"/>, like the web <c>useStaggerRush</c>): fades that haven't started start at once and rows
/// realized during the rush fade at delay 0, together. A scroll after the entrance has finished just closes the arm, so
/// scrolling never replays an entrance. An appended batch (Suggestions' incremental loading, <c>batchStart</c> &gt; 0)
/// is revealed by scrolling, stays open for its window and is never rushed (web <c>SuggestionsPage</c> doesn't install
/// the rush). A selected-row reveal announces its automatic scroll (<see cref="ExpectScroll"/>), which holds the rows
/// below the first screen until the jump rushes them (<see cref="Rush"/>). The scroll position is anchored once the
/// arm's first layout settles (<see cref="Settle"/>), so a page's own reset to the top as part of the reload doesn't
/// count as the reader scrolling.
/// </summary>
public sealed class StaggerArm
{
    /// <summary>Scroll movement (epx) that counts as the reader scrolling; smaller changes are layout rounding.</summary>
    public const double ScrollSlop = 1;

    private TimeSpan armedAt;
    private bool armed;
    private bool closed;
    private int timeOnlyStart;
    private bool closesOnScroll;
    private int? appendedStart;
    private (double X, double Y)? anchor;
    private TimeSpan entranceEnd;
    private TimeSpan? rushUntil;
    private int rushLimit;
    private TimeSpan? expectedAt;
    private int expectation;

    /// <summary>Creates a closed arm.</summary>
    /// <param name="window">How long an arm stays open without scrolling (default <see cref="FadeInTiming.ArmWindow"/>;
    /// UI journeys lengthen it with <see cref="ParseWindow"/> so a scripted scroll lands inside it).</param>
    public StaggerArm(TimeSpan? window = null) => Window = window ?? FadeInTiming.ArmWindow;

    /// <summary>How long an arm keeps staggering newly realized rows without scrolling.</summary>
    public TimeSpan Window { get; }

    /// <summary>Parses a window override in milliseconds (Debug/automation <c>FST_DEBUG_FADE_WINDOW_MS</c>).</summary>
    /// <param name="milliseconds">Raw value.</param>
    /// <returns>Window between 1 ms and 60 s, else <see langword="null"/> (use the default).</returns>
    public static TimeSpan? ParseWindow(string? milliseconds) =>
        int.TryParse(milliseconds, System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var ms)
        && ms is > 0 and <= 60_000 ? TimeSpan.FromMilliseconds(ms) : null;

    /// <summary>First row of the newest batch (rows before it never fade).</summary>
    public int BatchStart { get; private set; }

    /// <summary>Changes with every arm that is not merged into an open one (a selected-row reveal checks it went stale).</summary>
    public int Generation { get; private set; }

    /// <summary>Whether the reader (or anything else) moved the scroller since the load arm settled (web <c>navToPlayer</c>
    /// then skips its automatic scroll).</summary>
    public bool HasScrolled { get; private set; }

    /// <summary>Arms the window for a load (<paramref name="batchStart"/> 0) or an appended batch.</summary>
    /// <param name="batchStart">Index of the batch's first row (0 when the whole list is new).</param>
    /// <param name="now">Monotonic time.</param>
    public void Arm(int batchStart, TimeSpan now)
    {
        var open = IsOpen(now);
        // What a purely time-based window (no scroll close or rush) would stagger from: kept only to trace R5's suppressions.
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
            entranceEnd = now;
            rushUntil = null;
            rushLimit = 0;
            expectedAt = null;
            if (!appended) HasScrolled = false;
            Generation++;
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
    /// Records a scroll position: movement from the anchor rushes the load arm while its entrance runs, else closes it
    /// (keeping only a batch appended into it, which is never rushed).
    /// </summary>
    /// <param name="x">Horizontal offset (epx).</param>
    /// <param name="y">Vertical offset (epx).</param>
    /// <param name="now">Monotonic time.</param>
    /// <returns>What the movement did; <see cref="BatchStart"/> is then the kept batch's first row, or the load's 0.</returns>
    public ArmScroll Scrolled(double x, double y, TimeSpan now)
    {
        if (!closesOnScroll || closed || anchor is not { } at) return ArmScroll.None;
        if (!(Math.Abs(x - at.X) >= ScrollSlop || Math.Abs(y - at.Y) >= ScrollSlop)) return ArmScroll.None;
        HasScrolled = true;
        var rush = IsRunning(now);
        EndLoad(rush ? now + FadeInTiming.Duration : null);
        return rush ? ArmScroll.Rushed : ArmScroll.Closed;
    }

    /// <summary>
    /// Rushes the load entrance for an automatic scroll that is about to start (a selected-row reveal): fades that
    /// haven't started start now and rows realized while the scroll runs, plus one fade, start at delay 0.
    /// </summary>
    /// <param name="now">Monotonic time.</param>
    /// <param name="lasting">How long the scroll may take to realize the rows it reaches.</param>
    /// <returns><see langword="true"/> when the entrance (or a held tail) was still running and is now rushed.</returns>
    public bool Rush(TimeSpan now, TimeSpan lasting)
    {
        if (!closesOnScroll || closed || !IsRunning(now)) return false;
        EndLoad(now + lasting + FadeInTiming.Duration);
        return true;
    }

    /// <summary>Ends the load part of the arm: a rush (or plain close) that keeps only a batch appended into it.</summary>
    /// <param name="rushedUntil">End of the rush window, or <see langword="null"/> for a plain close.</param>
    private void EndLoad(TimeSpan? rushedUntil)
    {
        closesOnScroll = false;
        expectedAt = null;
        rushUntil = rushedUntil;
        rushLimit = rushedUntil is null ? 0 : appendedStart ?? int.MaxValue;
        if (appendedStart is { } start)
        {
            BatchStart = start;
            appendedStart = null;
        }
        else
        {
            closed = true;
        }
    }

    /// <summary>
    /// Announces an automatic scroll at <paramref name="at"/> (a selected-row reveal): until it runs, or
    /// <see cref="EndExpectation"/>, rows past the first screen wait for it, so the jump rushes them rather than reaching
    /// rows that already faded in unseen.
    /// </summary>
    /// <param name="at">When the scroll is expected (monotonic time).</param>
    /// <returns>A token for <see cref="EndExpectation"/>, so a stale reveal can't end a newer one.</returns>
    public int ExpectScroll(TimeSpan at)
    {
        expectedAt = closesOnScroll && !closed ? at : null;
        return ++expectation;
    }

    /// <summary>Ends an expectation (the reveal scrolled, was called off or went stale).</summary>
    /// <param name="token">Token from <see cref="ExpectScroll"/>.</param>
    public void EndExpectation(int token)
    {
        if (token == expectation) expectedAt = null;
    }

    /// <summary>When the load entrance is expected to finish, if a selected-row reveal holds rows for its scroll.</summary>
    public TimeSpan? ExpectedScroll => expectedAt;

    /// <summary>Whether the load entrance is still running (the window, scheduled fades or an expected scroll).</summary>
    /// <param name="now">Monotonic time.</param>
    /// <returns><see langword="true"/> while a scroll would rush rather than close.</returns>
    public bool IsRunning(TimeSpan now) =>
        armed && closesOnScroll && !closed && now >= armedAt
        && (now - armedAt < Window || now < entranceEnd || (expectedAt is { } at && now < at + FadeInTiming.Duration));

    /// <summary>Whether a rush started fades that rows realized now join (at delay 0).</summary>
    /// <param name="now">Monotonic time.</param>
    /// <returns><see langword="true"/> inside the rush window.</returns>
    public bool IsRushing(TimeSpan now) => rushUntil is { } until && now < until;

    /// <summary>Rows the latest rush reaches: all of the load, or those before a batch appended into it (never rushed).</summary>
    public int RushLimit => rushLimit;

    /// <summary>Whether rows realized now may still fade (the load entrance, a rush or an open appended batch).</summary>
    /// <param name="now">Monotonic time.</param>
    /// <returns>Whether the window is open.</returns>
    public bool IsOpen(TimeSpan now) =>
        IsRushing(now) || (armed && !closed && (closesOnScroll ? IsRunning(now) : Within(now)));

    /// <summary>Time since the last arm (for the fade trace).</summary>
    /// <param name="now">Monotonic time.</param>
    /// <returns>Elapsed time, or <see cref="TimeSpan.Zero"/> before the first arm.</returns>
    public TimeSpan SinceArmed(TimeSpan now) => armed ? now - armedAt : TimeSpan.Zero;

    /// <summary>
    /// Whether a row realized now shows in place only because a scroll closed or rushed the load window (R5's case): a
    /// purely time-based window would still have faded it.
    /// </summary>
    /// <param name="now">Monotonic time.</param>
    /// <param name="index">Row index.</param>
    /// <param name="visible">Rows that stagger (the visible count).</param>
    /// <returns><see langword="true"/> for a row the scroll kept from fading.</returns>
    public bool SuppressedByScroll(TimeSpan now, int index, int visible) =>
        armed && Within(now)
        && FadeInTiming.BatchDelay(index, timeOnlyStart, visible) is not null
        && Planned(index, visible, now) is null;

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
        Scrolled(x, y, now);
        var delay = Planned(index, visible, now);
        if (delay is { } d && closesOnScroll) Note(now + d);
        return delay;
    }

    /// <summary>
    /// The delay of a page fade that isn't a row stagger (Song Detail's sections and chart cards): its own delay while
    /// the load entrance runs (held to the entrance's last start once the window has passed), 0 while rushing, else
    /// <see langword="null"/> (show in place).
    /// </summary>
    /// <param name="natural">The fade's delay in the page's choreography.</param>
    /// <param name="now">Monotonic time.</param>
    /// <returns>Delay, or <see langword="null"/>.</returns>
    public TimeSpan? Entrance(TimeSpan natural, TimeSpan now)
    {
        if (IsRushing(now)) return TimeSpan.Zero;
        if (!IsRunning(now)) return null;
        var delay = Within(now) ? natural : Late(now);
        Note(now + delay);
        return delay;
    }

    /// <summary>Whether a row's planned fade waits for the expected automatic scroll (it is past the first screen).</summary>
    /// <param name="index">Row index.</param>
    /// <param name="visible">Rows that stagger (the visible count).</param>
    /// <returns><see langword="true"/> for a tail row of the load.</returns>
    public bool IsTail(int index, int visible) =>
        index >= BatchStart && FadeInTiming.BatchDelay(index, BatchStart, visible) is null;

    /// <summary>The delay a row realized now gets, without side effects.</summary>
    /// <param name="index">Row index.</param>
    /// <param name="visible">Rows that stagger (the visible count).</param>
    /// <param name="now">Monotonic time.</param>
    /// <returns>Delay, or <see langword="null"/> when the row shows in place.</returns>
    private TimeSpan? Planned(int index, int visible, TimeSpan now)
    {
        if (IsRushing(now) && index < rushLimit) return TimeSpan.Zero;
        if (!armed || closed) return null;
        if (!closesOnScroll) return Within(now) ? FadeInTiming.BatchDelay(index, BatchStart, visible) : null;
        if (!IsRunning(now) || index < BatchStart) return null;
        var tail = IsTail(index, visible);
        var delay = !Within(now) ? Late(now)
            : FadeInTiming.BatchDelay(index, BatchStart, visible) ?? FadeInTiming.TailDelay(visible);
        if (tail && expectedAt is { } at && at - now > delay) delay = at - now;
        return delay;
    }

    /// <summary>A row realized after the window while the entrance still runs starts with the entrance's last fade.</summary>
    /// <param name="now">Monotonic time.</param>
    /// <returns>Delay (never negative).</returns>
    private TimeSpan Late(TimeSpan now)
    {
        var lastStart = entranceEnd - FadeInTiming.Duration - now;
        return lastStart > TimeSpan.Zero ? lastStart : TimeSpan.Zero;
    }

    /// <summary>Extends the entrance to cover a fade starting at <paramref name="start"/>.</summary>
    /// <param name="start">Fade start (monotonic time).</param>
    private void Note(TimeSpan start)
    {
        var end = start + FadeInTiming.Duration;
        if (end > entranceEnd) entranceEnd = end;
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
