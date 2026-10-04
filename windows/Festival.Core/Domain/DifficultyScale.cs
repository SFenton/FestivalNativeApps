using System.Globalization;

namespace Festival.Core.Domain;

#region Difficulty scale
/// <summary>Branded seven-bar difficulty meter mapping and geometry (difficulty-meter spec).</summary>
public static class DifficultyScale
{
    /// <summary>Canvas width in logical units.</summary>
    public const double Width = 62;
    /// <summary>Canvas height in logical units.</summary>
    public const double Height = 20;
    /// <summary>Number of bars.</summary>
    public const int BarCount = 7;
    /// <summary>UI Automation ID of a meter showing a level.</summary>
    public const string MeterAutomationId = "fst.songs.difficulty-meter";
    /// <summary>UI Automation ID of a meter with no valid level.</summary>
    public const string UnavailableAutomationId = "fst.songs.difficulty-unavailable";
    /// <summary>Visible and spoken text of the <c>invalid</c> state.</summary>
    public const string UnavailableText = "Difficulty unavailable";

    /// <summary>Everything the meter shows and exposes for a raw level (one of the spec's eight states).</summary>
    /// <param name="raw">Raw 0–6 difficulty; non-finite is <c>invalid</c>.</param>
    /// <returns>The state.</returns>
    public static DifficultyMeterState State(double raw)
    {
        var bars = BarsForRaw(raw);
        return bars > 0
            ? new(bars, MeterAutomationId, Announcement(raw))
            : new(0, UnavailableAutomationId, UnavailableText);
    }

    /// <summary>Maps a raw 0–6 service level to 1–7 filled bars (truncate, clamp, add one).</summary>
    /// <param name="raw">Raw difficulty (99 → 7).</param>
    /// <returns>1–7, or 0 for a non-finite value.</returns>
    public static int BarsForRaw(double raw) =>
        double.IsFinite(raw) ? (int)Math.Clamp(Math.Truncate(raw), 0, 6) + 1 : 0;

    /// <summary>Screen-reader text for a raw level.</summary>
    /// <param name="raw">Raw difficulty, or <see langword="null"/> when not charted.</param>
    /// <returns>"Difficulty N of 7" or "Difficulty unavailable".</returns>
    public static string Announcement(double? raw) =>
        raw is { } value && BarsForRaw(value) is > 0 and var bars
            ? string.Create(CultureInfo.CurrentCulture, $"Difficulty {bars} of 7")
            : UnavailableText;

    /// <summary>Vertices of bar <paramref name="index"/>: (x+2,0) (x+8,0) (x+6,20) (x,20) with x = 9·index.</summary>
    /// <param name="index">0–6.</param>
    /// <returns>Four (x, y) points.</returns>
    public static (double X, double Y)[] BarPolygon(int index)
    {
        var x = index * 9.0;
        return [(x + 2, 0), (x + 8, 0), (x + 6, 20), (x, 20)];
    }
}

/// <summary>One rendered difficulty-meter state.</summary>
/// <param name="FilledBars">Filled bars (1–7), or 0 for <c>invalid</c>.</param>
/// <param name="AutomationId">UI Automation ID for the state.</param>
/// <param name="Name">Accessible name (the visible text when invalid).</param>
public readonly record struct DifficultyMeterState(int FilledBars, string AutomationId, string Name)
{
    private static readonly string[] Names = ["invalid", "one", "two", "three", "four", "five", "six", "seven"];

    /// <summary>Whether a level is shown (bars) rather than the "Difficulty unavailable" text.</summary>
    public bool IsAvailable => FilledBars > 0;

    /// <summary>Spec state name: <c>one</c> … <c>seven</c> or <c>invalid</c>.</summary>
    public string StateName => Names[FilledBars];

    /// <summary>Whether bar <paramref name="index"/> (0–6) is filled.</summary>
    /// <param name="index">Bar index.</param>
    /// <returns><see langword="true"/> for a filled bar.</returns>
    public bool IsFilled(int index) => index < FilledBars;
}
#endregion
