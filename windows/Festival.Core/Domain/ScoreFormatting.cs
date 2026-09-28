using System.Globalization;

namespace Festival.Core.Domain;

#region Score formatting
/// <summary>Shared score display policy for leaderboard rows (score-accuracy control).</summary>
public static class ScoreFormatting
{
    /// <summary>Formats expanded accuracy (ten-thousandths of a percent) with one decimal only when needed.</summary>
    /// <param name="expandedAccuracy">Service accuracy, e.g. 985000 → "98.5%".</param>
    /// <returns>Percent text, or an empty string for a non-finite value.</returns>
    public static string Accuracy(double? expandedAccuracy)
    {
        if (expandedAccuracy is not { } value || !double.IsFinite(value)) return "";
        var rounded = Math.Round(value / 1_000, MidpointRounding.AwayFromZero) / 10;
        var format = rounded == Math.Round(rounded) ? "0" : "0.0";
        return rounded.ToString(format, CultureInfo.CurrentCulture) + "%";
    }

    /// <summary>Formats a score with grouping separators.</summary>
    /// <param name="score">Score.</param>
    /// <returns>Grouped digits.</returns>
    public static string Score(long score) => score.ToString("N0", CultureInfo.CurrentCulture);

    /// <summary>Formats a one-based rank.</summary>
    /// <param name="rank">Rank.</param>
    /// <returns><c>#1,234</c>.</returns>
    public static string Rank(int rank) => "#" + rank.ToString("N0", CultureInfo.CurrentCulture);

    /// <summary>Red-to-green accuracy tint (the caller applies 25% opacity).</summary>
    /// <param name="expandedAccuracy">Service accuracy.</param>
    /// <returns>sRGB components.</returns>
    public static (byte R, byte G, byte B) AccuracyTint(double expandedAccuracy)
    {
        var f = double.IsFinite(expandedAccuracy) ? Math.Clamp(expandedAccuracy / 1_000_000, 0, 1) : 0;
        return (Channel(220 * (1 - f) + 46 * f), Channel(40 * (1 - f) + 204 * f), Channel(40 * (1 - f) + 113 * f));

        static byte Channel(double value) => (byte)Math.Round(value, MidpointRounding.AwayFromZero);
    }
}
#endregion
