using Festival.App.Services;
using Microsoft.UI.Xaml;

namespace Festival.App.Controls;

#region Selected row reveal
/// <summary>
/// The automatic scroll to a board's selected row (web <c>navToPlayer</c>/<c>navToBand</c>, pattern
/// <c>load-transition</c> R5, issue #323), shared by the song leaderboard, Full Rankings and the song band leaderboard.
/// It waits until the row's own entrance has finished (<see cref="FadeInTiming.RevealWait"/>) while the rows below the
/// first screen wait for the jump (<see cref="FadeIn"/> hold), then rushes the rest of the entrance and scrolls, so every
/// row the scroll reaches fades in together. A reader's own scroll first, a reload or leaving the page calls it off.
/// With motion off it scrolls at once without animation (R6).
/// </summary>
public static class SelectedRowReveal
{
    /// <summary>Timers waiting to scroll, held until they tick.</summary>
    private static readonly HashSet<Microsoft.UI.Dispatching.DispatcherQueueTimer> Waiting = [];

    /// <summary>Scrolls a stagger list to its selected row once the row's entrance has finished.</summary>
    /// <param name="list">The stagger list (<c>FadeIn.Stagger</c>) holding the row.</param>
    /// <param name="index">The selected row's index.</param>
    /// <param name="scroll">Brings the row into view; the argument says whether to animate.</param>
    /// <param name="immediate">Scroll now, rushing the entrance (keyboard focus is moving to the row).</param>
    public static void Start(FrameworkElement list, int index, Action<bool> scroll, bool immediate = false)
    {
        if (index < 0) return;
        if (!Motion.Allowed || immediate)
        {
            if (Motion.Allowed) FadeIn.RushForAutomaticScroll(list, FadeInTiming.RevealScroll);
            FadeIn.Trace("fade-reveal", list, $"index={index} wait=0 scrolled=1");
            scroll(Motion.Allowed);
            return;
        }
        var arm = FadeIn.ArmFor(list);
        var generation = arm.Generation;
        var wait = FadeInTiming.RevealWait(index, FadeIn.VisibleRows(list));
        var token = FadeIn.ExpectAutomaticScroll(list, FadeIn.Now + wait);
        var timer = list.DispatcherQueue.CreateTimer();
        timer.Interval = wait;
        timer.IsRepeating = false;
        timer.Tick += (sender, _) =>
        {
            sender.Stop();
            Waiting.Remove(sender);
            // Web navToPlayer: the reader's own scroll in the meantime wins; so do a newer load and leaving the page.
            var go = list.IsLoaded && arm.Generation == generation && !arm.HasScrolled;
            if (go) FadeIn.RushForAutomaticScroll(list, FadeInTiming.RevealScroll);
            arm.EndExpectation(token);
            FadeIn.Trace("fade-reveal", list, $"index={index} wait={wait.TotalMilliseconds:F0} scrolled={(go ? 1 : 0)}");
            if (go) scroll(Motion.Allowed);
        };
        Waiting.Add(timer);
        timer.Start();
    }
}
#endregion
