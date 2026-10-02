namespace Festival.Core.Domain;

#region Instrument switch
/// <summary>What Score History does when the requested chart changes.</summary>
public enum ScoreHistorySwapPlan
{
    /// <summary>Nothing to show.</summary>
    None,
    /// <summary>The graph already shows the request: finish any swap by fading fully back in.</summary>
    Settle,
    /// <summary>Swap at once, without animation (first value or reduced motion).</summary>
    Instant,
    /// <summary>Fade out, swap, fade in.</summary>
    Fade,
}

/// <summary>
/// How Song Detail's Score History swaps its graph when the selected chart changes (issue #61, iOS #31): the graph, its
/// detail row and pager and the best-scores list fade out, swap to the new chart, then fade back in while the card keeps
/// its size. With motion off (Windows "Animation effects", in-app Reduce Motion or <c>--reduce-motion</c>) the swap is
/// instant.
/// </summary>
public static class ScoreHistorySwap
{
    /// <summary>Fade-out time of the old chart's graph.</summary>
    public static readonly TimeSpan FadeOut = TimeSpan.FromMilliseconds(150);

    /// <summary>Fade-in time of the new chart's graph (also the card-height release).</summary>
    public static readonly TimeSpan FadeIn = TimeSpan.FromMilliseconds(250);

    /// <summary>Plans a swap.</summary>
    /// <param name="displayed">Chart the graph shows now, or <see langword="null"/> before it first draws.</param>
    /// <param name="target">Chart the selector now requests, or <see langword="null"/>.</param>
    /// <param name="reduceMotion">Whether motion is off.</param>
    /// <returns>The swap to perform.</returns>
    public static ScoreHistorySwapPlan Plan(Instrument? displayed, Instrument? target, bool reduceMotion)
    {
        if (target is null) return ScoreHistorySwapPlan.None;
        if (displayed is null) return ScoreHistorySwapPlan.Instant;
        if (displayed == target) return ScoreHistorySwapPlan.Settle;
        return reduceMotion ? ScoreHistorySwapPlan.Instant : ScoreHistorySwapPlan.Fade;
    }

    /// <summary>
    /// Whether the card keeps room for the pager on <b>every</b> chart, so it keeps one size when the chart changes: true
    /// when any selectable chart has more rows than one page holds.
    /// </summary>
    /// <param name="counts">Rows per chart.</param>
    /// <param name="instruments">The selector's charts.</param>
    /// <param name="maxBars">Bars per page (<see cref="int.MaxValue"/> before the plot is measured).</param>
    /// <returns>True to lay out the pager row (empty when the shown chart doesn't page).</returns>
    public static bool ReservesPager(IReadOnlyDictionary<Instrument, int> counts, IEnumerable<Instrument> instruments, int maxBars) =>
        instruments.Any(i => counts.GetValueOrDefault(i) > maxBars);
}

/// <summary>
/// Runs <see cref="ScoreHistorySwap"/> plans one at a time: a newer request cancels the running one, so rapid switching
/// ends on the last choice. The view supplies the fade, the swap and the card-height hold.
/// </summary>
/// <param name="displayed">Chart the graph shows now.</param>
/// <param name="show">Swaps the graph to a chart.</param>
/// <param name="fade">Animates the graph's opacity to a value over a duration (zero = at once); completes when done.</param>
/// <param name="hold">Holds (<see langword="true"/>) or releases the card's height (released with motion when allowed).</param>
public sealed class ScoreHistorySwapper(
    Func<Instrument?> displayed,
    Action<Instrument> show,
    Func<double, TimeSpan, CancellationToken, Task> fade,
    Action<bool> hold)
{
    private CancellationTokenSource? running;

    /// <summary>Whether a swap is in progress.</summary>
    public bool IsRunning => running is not null;

    /// <summary>Swaps to <paramref name="target"/>, cancelling any swap in progress.</summary>
    /// <param name="target">Requested chart.</param>
    /// <param name="reduceMotion">Whether motion is off.</param>
    /// <returns>The plan that ran; completes when the swap finishes or a newer request cancels it.</returns>
    public async Task<ScoreHistorySwapPlan> RequestAsync(Instrument? target, bool reduceMotion)
    {
        running?.Cancel();
        var plan = ScoreHistorySwap.Plan(displayed(), target, reduceMotion);
        if (plan == ScoreHistorySwapPlan.None || target is not { } chart)
        {
            running = null;
            hold(false);
            await fade(1, TimeSpan.Zero, CancellationToken.None).ConfigureAwait(true);
            return plan;
        }
        using var current = new CancellationTokenSource();
        running = current;
        var token = current.Token;
        try
        {
            // Continuations must stay on the UI thread: show/fade/hold touch bound state and composition visuals.
            switch (plan)
            {
                case ScoreHistorySwapPlan.Instant:
                    show(chart);
                    await fade(1, TimeSpan.Zero, token).ConfigureAwait(true);
                    break;
                case ScoreHistorySwapPlan.Settle:
                    await fade(1, reduceMotion ? TimeSpan.Zero : ScoreHistorySwap.FadeIn, token).ConfigureAwait(true);
                    break;
                default:
                    hold(true);
                    await fade(0, ScoreHistorySwap.FadeOut, token).ConfigureAwait(true);
                    show(chart);
                    await fade(1, ScoreHistorySwap.FadeIn, token).ConfigureAwait(true);
                    break;
            }
            hold(false);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            // A newer request took over and finishes the swap.
        }
        finally
        {
            if (ReferenceEquals(running, current)) running = null;
        }
        return plan;
    }
}
#endregion
