using Festival.App.Services;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Selected row reveal
/// <summary>
/// The one automatic scroll to a board's selected row (web <c>navToPlayer</c>/<c>navToBand</c>; patterns
/// <c>leaderboard-row</c> R7 and <c>load-transition</c> R5, issues #307 and #323), shared by the song leaderboard, Full
/// Rankings and the song band leaderboard. Call it after the list's <c>FadeIn.StaggerRealized</c>. A list the load gate
/// has just shown realizes its rows on a later layout pass, so it first waits, frame by frame (up to about 2 s), for the
/// selected row or the first row to be realized. Then it holds the rows below the first screen for the jump
/// (<see cref="FadeIn"/> hold) and waits until the row's own entrance has finished (<see cref="FadeInTiming.RevealWait"/>),
/// rushes the rest of the entrance and scrolls, so every row the scroll reaches fades in together and none is already
/// opaque. A reader's own scroll first, a newer reveal or load, or leaving the page calls it off. With motion off it
/// scrolls at once and rushes nothing (R6). The scroll itself is the caller's (instant, centred; #318 made it reliable);
/// repeater boards use <see cref="CentreRow"/>, which lays a freshly realized row out before centring it (#571).
/// </summary>
public static class SelectedRowReveal
{
    private static readonly DependencyProperty CurrentProperty = DependencyProperty.RegisterAttached(
        "Current", typeof(object), typeof(SelectedRowReveal), new PropertyMetadata(null));

    /// <summary>Rendered frames a reveal waits for the list to realize its rows before going ahead anyway (about 2 s).</summary>
    private const int RealizeFrames = 120;

    /// <summary>Rendered frames <see cref="CentreRow"/> re-checks that its row landed in view (about 0.5 s).</summary>
    private const int CentreFrames = 30;

    /// <summary>
    /// The reveal's scroll for an <see cref="ItemsRepeater"/> board: realizes the row, lays it out and centres it at once.
    /// A row the repeater only now creates (the selected row lies past the realized first screen, as at 225% text) has no
    /// arranged position yet, and bringing it into view before layout is a silent no-op that leaves the board at the top
    /// with its first rows recycled (issue #571). So it lays the row out first and, for a few frames, asks again until the
    /// row's centre lies inside the scroll viewport, stopping when the row is recycled or the list unloads.
    /// </summary>
    /// <param name="repeater">The board's repeater.</param>
    /// <param name="index">The selected row's index.</param>
    public static void CentreRow(ItemsRepeater repeater, int index)
    {
        if (repeater.GetOrCreateElement(index) is not UIElement row) return;
        Centre(row);
        var frames = 0;
        void OnFrame(object? sender, object e)
        {
            if (++frames > CentreFrames || !repeater.IsLoaded || !ReferenceEquals(repeater.TryGetElement(index), row) || InView(row))
            {
                CompositionTarget.Rendering -= OnFrame;
                return;
            }
            FadeIn.Trace("fade-reveal-retry", repeater, $"index={index} frame={frames}");
            Centre(row);
        }
        CompositionTarget.Rendering += OnFrame;
    }

    /// <summary>Lays a row out and asks its scroll viewer to centre it instantly.</summary>
    /// <param name="row">Realized row.</param>
    private static void Centre(UIElement row)
    {
        row.UpdateLayout();
        row.StartBringIntoView(new BringIntoViewOptions { VerticalAlignmentRatio = 0.5, AnimationDesired = false });
    }

    /// <summary>Whether a row's vertical centre lies inside its nearest scroll viewer's viewport.</summary>
    /// <param name="row">Realized row.</param>
    /// <returns><see langword="true"/> when visible, or when there is no scroll viewer to check.</returns>
    private static bool InView(UIElement row)
    {
        var parent = VisualTreeHelper.GetParent(row);
        while (parent is not null and not ScrollViewer) parent = VisualTreeHelper.GetParent(parent);
        if (parent is not ScrollViewer scroller) return true;
        var centre = row.TransformToVisual(scroller).TransformPoint(default).Y + row.ActualSize.Y / 2;
        return centre >= 0 && centre <= scroller.ViewportHeight;
    }

    /// <summary>Scrolls a stagger list to its selected row once the row's entrance has finished.</summary>
    /// <param name="list">The stagger list (<c>FadeIn.Stagger</c>: a <see cref="ListViewBase"/> or <see cref="ItemsRepeater"/>).</param>
    /// <param name="index">The selected row's index.</param>
    /// <param name="scroll">Brings the row into view.</param>
    public static void Start(FrameworkElement list, int index, Action scroll)
    {
        if (index < 0) return;
        (list.GetValue(CurrentProperty) as Reveal)?.Stop();
        if (!Motion.Allowed)
        {
            list.ClearValue(CurrentProperty);
            FadeIn.Trace("fade-reveal", list, $"index={index} wait=0 scrolled=1 motion=0");
            scroll();
            return;
        }
        var reveal = new Reveal(list, index, scroll);
        list.SetValue(CurrentProperty, reveal);
        reveal.Start();
    }

    /// <summary>One reveal waiting for its row's realization, then for its entrance.</summary>
    private sealed class Reveal(FrameworkElement list, int index, Action scroll)
    {
        private readonly StaggerArm arm = FadeIn.ArmFor(list);
        private readonly int generation = FadeIn.ArmFor(list).Generation;
        private DispatcherQueueTimer? timer;
        private bool listening;
        private int frames;
        private int token = -1;
        private TimeSpan wait;

        /// <summary>Waits for the list's next rendered frames.</summary>
        public void Start()
        {
            listening = true;
            CompositionTarget.Rendering += OnFrame;
        }

        /// <summary>Drops the reveal (a newer one replaced it) and releases its hold.</summary>
        public void Stop()
        {
            StopFrames();
            timer?.Stop();
            timer = null;
            if (token >= 0) arm.EndExpectation(token);
        }

        /// <summary>Whether this is still the list's reveal.</summary>
        private bool Current => ReferenceEquals(list.GetValue(CurrentProperty), this);

        /// <summary>Stops listening to frames.</summary>
        private void StopFrames()
        {
            if (listening) CompositionTarget.Rendering -= OnFrame;
            listening = false;
        }

        /// <summary>Once the list has realized the selected (or first) row, holds the tail and waits for the row's entrance.</summary>
        /// <param name="sender">Unused.</param>
        /// <param name="e">Unused.</param>
        private void OnFrame(object? sender, object e)
        {
            if (!Current || !list.IsLoaded || arm.Generation != generation)
            {
                Finish();
                return;
            }
            var realized = Realized(index) || Realized(0);
            if (!realized && ++frames < RealizeFrames) return;
            StopFrames();
            var now = FadeIn.Now;
            // Rows realized now start their stagger (or a whole-card board its one fade, #614) now; a board whose entrance already ended (rows shown in place) waits for nothing.
            wait = arm.IsRunning(now) ? arm.RevealWait(index, FadeIn.VisibleRows(list), now) : TimeSpan.Zero;
            if (wait <= TimeSpan.Zero)
            {
                Finish();
                return;
            }
            token = FadeIn.ExpectAutomaticScroll(list, now + wait);
            timer = list.DispatcherQueue.CreateTimer();
            timer.Interval = wait;
            timer.IsRepeating = false;
            timer.Tick += (t, _) =>
            {
                t.Stop();
                timer = null;
                Finish();
            };
            timer.Start();
        }

        /// <summary>
        /// Rushes the entrance and scrolls, unless a newer reveal or load, an unload or the reader's own scroll got there
        /// first (web <c>navToPlayer</c> skips its scroll then).
        /// </summary>
        private void Finish()
        {
            StopFrames();
            var current = Current;
            if (current) list.ClearValue(CurrentProperty);
            var go = current && list.IsLoaded && arm.Generation == generation && !arm.HasScrolled;
            if (go) FadeIn.RushForAutomaticScroll(list, FadeInTiming.RevealScroll);
            if (token >= 0) arm.EndExpectation(token);
            FadeIn.Trace("fade-reveal", list, $"index={index} wait={wait.TotalMilliseconds:F0} scrolled={(go ? 1 : 0)} motion=1");
            if (go) scroll();
        }

        /// <summary>Whether the list has realized a row.</summary>
        /// <param name="row">Row index.</param>
        /// <returns><see langword="true"/> when its element exists.</returns>
        private bool Realized(int row) => list switch
        {
            ListViewBase view => view.ContainerFromIndex(row) is not null,
            ItemsRepeater repeater => repeater.TryGetElement(row) is not null,
            _ => true,
        };
    }
}
#endregion