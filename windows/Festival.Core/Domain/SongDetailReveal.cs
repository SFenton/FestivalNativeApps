namespace Festival.Core.Domain;

#region Song detail reveal
/// <summary>
/// Song Detail's load choreography (web <c>SongDetailPage.tsx</c> <c>useLoadPhase</c> + <c>useStagger</c>): the spinner stays
/// until every section is ready, fades out over <see cref="SpinnerFade"/>, then the sections fade up in order — header,
/// Intensity (100 ms), score history (150 ms), then the chart cards row by row from 300 ms, 150 ms apart
/// (<c>getInstrumentBaseDelay</c>). A load that finished almost at once (cached reads) skips the stagger, like the web's
/// <c>skipAnimation</c> for cached data.
/// </summary>
public static class SongDetailReveal
{
    /// <summary>Web <c>SPINNER_FADE_MS</c>.</summary>
    public static readonly TimeSpan SpinnerFade = TimeSpan.FromMilliseconds(500);

    /// <summary>Loads faster than this reveal without animation.</summary>
    public static readonly TimeSpan InstantLoad = TimeSpan.FromMilliseconds(150);

    /// <summary>Header delay.</summary>
    public static readonly TimeSpan Header = TimeSpan.Zero;

    /// <summary>Intensity delay (web <c>stagger(100)</c>).</summary>
    public static readonly TimeSpan Intensity = TimeSpan.FromMilliseconds(100);

    /// <summary>Score history delay (web <c>stagger(150)</c>).</summary>
    public static readonly TimeSpan History = TimeSpan.FromMilliseconds(150);

    /// <summary>Leaderboards heading delay (the first card row's).</summary>
    public static readonly TimeSpan Leaderboards = TimeSpan.FromMilliseconds(300);

    /// <summary>Whether the reveal animates.</summary>
    /// <param name="loadTime">Time from navigation to ready.</param>
    /// <param name="motionAllowed">Motion policy.</param>
    /// <returns><see langword="true"/> to fade the spinner and stagger.</returns>
    public static bool Animates(TimeSpan loadTime, bool motionAllowed) => motionAllowed && loadTime >= InstantLoad;

    /// <summary>A chart card's delay: 300 ms + 150 ms per grid row.</summary>
    /// <param name="index">Card index.</param>
    /// <param name="columns">Cards per row (1 or 2).</param>
    /// <returns>Delay.</returns>
    public static TimeSpan Card(int index, int columns) =>
        Leaderboards + TimeSpan.FromMilliseconds(150 * (Math.Max(0, index) / Math.Max(1, columns)));
}
#endregion
