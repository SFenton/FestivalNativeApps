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
            : "Difficulty unavailable";

    /// <summary>Vertices of bar <paramref name="index"/>: (x+2,0) (x+8,0) (x+6,20) (x,20) with x = 9·index.</summary>
    /// <param name="index">0–6.</param>
    /// <returns>Four (x, y) points.</returns>
    public static (double X, double Y)[] BarPolygon(int index)
    {
        var x = index * 9.0;
        return [(x + 2, 0), (x + 8, 0), (x + 6, 20), (x, 20)];
    }
}
#endregion
