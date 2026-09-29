namespace Festival.Core.Domain;

#region Playback policy
/// <summary>What the shared artwork background should do right now.</summary>
public enum ArtworkMode
{
    /// <summary>Rotate covers with crossfade and slow zoom/pan.</summary>
    Animated,
    /// <summary>One still cover (reduced motion / animations off).</summary>
    Static,
    /// <summary>No art and no dim overlay (save data, contrast themes).</summary>
    Hidden,
    /// <summary>Keep the current frame; stop timers and animations (window minimized or hidden).</summary>
    Paused,
}

/// <summary>Inputs from the system, the window and the app's additive accessibility overrides.</summary>
/// <param name="SystemAnimationsEnabled">Windows "Animation effects".</param>
/// <param name="WindowVisible">Window is shown and not minimized.</param>
/// <param name="WindowOccluded">Window is fully covered (when measurable).</param>
/// <param name="ReduceMotion">In-app reduce motion.</param>
/// <param name="DisableAnimatedArtwork">In-app disable artwork animation.</param>
/// <param name="SaveData">In-app data saving or a metered connection.</param>
/// <param name="HighContrast">A Windows contrast theme is on: decorative art is hidden so content sits on the theme's window colour.</param>
public readonly record struct ArtworkPolicyInputs(
    bool SystemAnimationsEnabled, bool WindowVisible, bool WindowOccluded,
    bool ReduceMotion, bool DisableAnimatedArtwork, bool SaveData, bool HighContrast = false);

/// <summary>Combines policy inputs (artwork-background spec). Focus moving to a game does not pause.</summary>
public static class ArtworkPlaybackPolicy
{
    /// <summary>Resolves the background mode.</summary>
    /// <param name="inputs">Current inputs.</param>
    /// <returns>Mode to apply.</returns>
    public static ArtworkMode Resolve(ArtworkPolicyInputs inputs)
    {
        if (inputs.SaveData || inputs.HighContrast) return ArtworkMode.Hidden;
        if (!inputs.WindowVisible || inputs.WindowOccluded) return ArtworkMode.Paused;
        if (!inputs.SystemAnimationsEnabled || inputs.ReduceMotion || inputs.DisableAnimatedArtwork) return ArtworkMode.Static;
        return ArtworkMode.Animated;
    }
}
#endregion

#region Motion presets
/// <summary>A slow zoom/pan: scale and translation (logical units) at the start and end of a 6 s drift.</summary>
/// <param name="FromScale">Start scale.</param>
/// <param name="ToScale">End scale (≤1.18).</param>
/// <param name="FromX">Start X offset.</param>
/// <param name="FromY">Start Y offset.</param>
/// <param name="ToX">End X offset (|x| ≤ 18).</param>
/// <param name="ToY">End Y offset (|y| ≤ 18).</param>
public readonly record struct MotionPreset(double FromScale, double ToScale, double FromX, double FromY, double ToX, double ToY)
{
    /// <summary>Start offset as drawn: CSS <c>scale(s) translate(x, y)</c> moves the scaled layer by s·x, s·y.</summary>
    public (double X, double Y) VisualFrom => (FromX * FromScale, FromY * FromScale);

    /// <summary>End offset as drawn (see <see cref="VisualFrom"/>).</summary>
    public (double X, double Y) VisualTo => (ToX * ToScale, ToY * ToScale);
}
#endregion

#region Carousel
/// <summary>
/// Pure carousel sequencing: ≤100 shuffled covers, 5 s dwell, 1 s crossfade, 6 s drift with one of ten
/// presets, and paced failure recovery (skip failures; stop after five per pool).
/// </summary>
public sealed class ArtworkCarousel
{
    /// <summary>Maximum covers in one rotation.</summary>
    public const int MaxCovers = 100;
    /// <summary>Time each cover is shown.</summary>
    public static readonly TimeSpan Dwell = TimeSpan.FromSeconds(5);
    /// <summary>Crossfade duration.</summary>
    public static readonly TimeSpan Crossfade = TimeSpan.FromSeconds(1);
    /// <summary>Zoom/pan duration.</summary>
    public static readonly TimeSpan Drift = TimeSpan.FromSeconds(6);
    /// <summary>Opacity of the black dim layer.</summary>
    public const double DimOpacity = 0.7;
    /// <summary>Failures tolerated per pool before rotation stops.</summary>
    public const int FailureBudget = 5;

    /// <summary>The web's ten zoom/pan presets (<c>AnimatedBackground.tsx</c> <c>MOTION_PRESETS</c>, PWA gap 18).</summary>
    public static IReadOnlyList<MotionPreset> Presets { get; } =
    [
        new(1.00, 1.12, 0, 0, 0, 0), // Zoom in
        new(1.12, 1.00, 0, 0, 0, 0), // Zoom out
        new(1.18, 1.18, 18, 0, -18, 0), // Pan left
        new(1.18, 1.18, -18, 0, 18, 0), // Pan right
        new(1.18, 1.18, 0, 18, 0, -18), // Pan up
        new(1.18, 1.18, 0, -18, 0, 18), // Pan down
        new(1.18, 1.18, -14, -14, 14, 14), // Diagonal ↘
        new(1.18, 1.18, 14, -14, -14, 14), // Diagonal ↙
        new(1.18, 1.18, -14, 14, 14, -14), // Diagonal ↗
        new(1.18, 1.18, 14, 14, -14, -14), // Diagonal ↖
    ];

    private readonly List<string> covers;
    private readonly Random random;
    private int index = -1;
    private int failures;

    /// <summary>Builds a shuffled rotation from catalogue art references.</summary>
    /// <param name="artReferences">Raw <c>albumArt</c> values (duplicates and blanks ignored).</param>
    /// <param name="random">Randomness source (seeded in tests).</param>
    public ArtworkCarousel(IEnumerable<string?> artReferences, Random? random = null)
    {
        this.random = random ?? Random.Shared;
        var unique = artReferences.Where(a => !string.IsNullOrWhiteSpace(a)).Distinct(StringComparer.Ordinal).Select(a => a!).ToArray();
        this.random.Shuffle(unique);
        covers = unique.Take(MaxCovers).ToList();
    }

    /// <summary>Covers in rotation order.</summary>
    public IReadOnlyList<string> Covers => covers;

    /// <summary>Whether rotation has stopped (no covers or failure budget exhausted).</summary>
    public bool IsExhausted => covers.Count == 0 || failures >= FailureBudget;

    /// <summary>Advances to the next cover.</summary>
    /// <returns>The cover and a random preset, or <see langword="null"/> when exhausted.</returns>
    public (string Cover, MotionPreset Preset)? Next()
    {
        if (IsExhausted) return null;
        index = (index + 1) % covers.Count;
        return (covers[index], Presets[random.Next(Presets.Count)]);
    }

    /// <summary>Records a failed cover so the next call skips ahead.</summary>
    public void ReportFailure() => failures++;
}
#endregion
