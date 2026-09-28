namespace Festival.Core.Domain;

#region Metadata fields
/// <summary>The eight independently visible Song-row metadata fields (web <c>SongRowVisualKey</c>).</summary>
public enum MetadataField
{
    /// <summary>Best score.</summary>
    Score,
    /// <summary>Accuracy percentage.</summary>
    Percentage,
    /// <summary>Leaderboard percentile.</summary>
    Percentile,
    /// <summary>Season achieved.</summary>
    Season,
    /// <summary>Chart intensity meter.</summary>
    Intensity,
    /// <summary>Game difficulty played.</summary>
    Difficulty,
    /// <summary>Stars.</summary>
    Stars,
    /// <summary>Last played date.</summary>
    LastPlayed,
}

/// <summary>The five columns of the CHOpt Paths text table.</summary>
public enum PathColumnKey
{
    /// <summary>Note.</summary>
    Note,
    /// <summary>Beat.</summary>
    Beat,
    /// <summary>Time.</summary>
    Time,
    /// <summary>Overdrive.</summary>
    Od,
    /// <summary>Score.</summary>
    Score,
}

/// <summary>How CHOpt paths open by default.</summary>
public enum PathDisplayMode
{
    /// <summary>Rendered path image.</summary>
    Image,
    /// <summary>Text table.</summary>
    Text,
}

/// <summary>Labels for settings enums.</summary>
public static class SettingsLabels
{
    /// <summary>Title Case label (web <c>settings.en.json</c> / Apple <c>MetadataField.label</c>).</summary>
    /// <param name="field">Field.</param>
    /// <returns>Label.</returns>
    public static string Label(this MetadataField field) => field switch
    {
        MetadataField.Score => "Score",
        MetadataField.Percentage => "Percentage",
        MetadataField.Percentile => "Percentile",
        MetadataField.Season => "Season Achieved",
        MetadataField.Intensity => "Intensity",
        MetadataField.Difficulty => "Game Difficulty",
        MetadataField.Stars => "Stars",
        _ => "Last Played",
    };

    /// <summary>Column header shared by the Paths text table and its Settings reorder row.</summary>
    /// <param name="column">Column.</param>
    /// <returns>Label.</returns>
    public static string Label(this PathColumnKey column) => column switch
    {
        PathColumnKey.Note => "Note",
        PathColumnKey.Beat => "Beat",
        PathColumnKey.Time => "Time",
        PathColumnKey.Od => "OD",
        _ => "Score",
    };

    /// <summary>Stable automation-ID token.</summary>
    /// <param name="field">Field.</param>
    /// <returns>Kebab-case token such as <c>last-played</c>.</returns>
    public static string Token(this MetadataField field) => field == MetadataField.LastPlayed ? "last-played" : field.ToString().ToLowerInvariant();
}
#endregion

#region Order codec
/// <summary>Repairs user-reorderable lists so they survive app updates and corrupt data.</summary>
public static class SettingsOrder
{
    /// <summary>Every case exactly once: the stored order first (unknown and duplicate entries dropped), then any missing case.</summary>
    /// <typeparam name="T">Enum type.</typeparam>
    /// <param name="stored">Persisted order, possibly null, partial or corrupt.</param>
    /// <returns>A complete order.</returns>
    public static IReadOnlyList<T> Normalize<T>(IEnumerable<T>? stored) where T : struct, Enum
    {
        var result = new List<T>();
        var seen = new HashSet<T>();
        foreach (var value in stored ?? [])
        {
            if (Enum.IsDefined(value) && seen.Add(value)) result.Add(value);
        }
        foreach (var value in Enum.GetValues<T>())
        {
            if (seen.Add(value)) result.Add(value);
        }
        return result;
    }

    /// <summary>Moves one item up or down by one place (keyboard/Narrator-friendly reorder).</summary>
    /// <typeparam name="T">Item type.</typeparam>
    /// <param name="order">Current order.</param>
    /// <param name="index">Item index.</param>
    /// <param name="offset">-1 (up) or +1 (down).</param>
    /// <returns>New order, or the same items when the move is out of range.</returns>
    public static IReadOnlyList<T> Move<T>(IReadOnlyList<T> order, int index, int offset)
    {
        var target = index + offset;
        var list = order.ToList();
        if (index < 0 || index >= list.Count || target < 0 || target >= list.Count) return list;
        (list[index], list[target]) = (list[target], list[index]);
        return list;
    }
}
#endregion

#region Leeway
/// <summary>Invalid-score leeway rules (web <c>SettingsPage.tsx</c> slider: −5…+5 %, step 0.1, default +1).</summary>
public static class ScoreLeeway
{
    /// <summary>Lowest leeway percent.</summary>
    public const double Minimum = -5;

    /// <summary>Highest leeway percent.</summary>
    public const double Maximum = 5;

    /// <summary>Default leeway percent.</summary>
    public const double Default = 1;

    /// <summary>Reference CHOpt maximum used in the Settings explanation.</summary>
    public const int ReferenceMaxScore = 100_000;

    /// <summary>Clamps to range and rounds to one decimal; non-finite values use the default.</summary>
    /// <param name="value">Raw value.</param>
    /// <returns>Valid leeway.</returns>
    public static double Clamp(double value) =>
        double.IsFinite(value) ? Math.Round(Math.Clamp(value, Minimum, Maximum), 1, MidpointRounding.AwayFromZero) : Default;

    /// <summary>Signed one-decimal display, e.g. <c>+1.0%</c>, <c>-0.5%</c>, <c>0.0%</c>.</summary>
    /// <param name="value">Leeway.</param>
    /// <returns>Label.</returns>
    public static string Format(double value)
    {
        var v = Clamp(value);
        var text = Math.Abs(v).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + "%";
        return v > 0 ? "+" + text : v < 0 ? "-" + text : text;
    }

    /// <summary>Highest score accepted as valid for the reference maximum.</summary>
    /// <param name="value">Leeway.</param>
    /// <returns>Rounded score.</returns>
    public static int MaxEffectiveScore(double value) => (int)Math.Round(ReferenceMaxScore * (1 + Clamp(value) / 100), MidpointRounding.AwayFromZero);
}
#endregion
