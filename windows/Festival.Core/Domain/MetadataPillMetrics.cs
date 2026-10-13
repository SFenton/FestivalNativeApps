namespace Festival.Core.Domain;

#region Metadata pill metrics
/// <summary>Shared season and percentile geometry; minimums grow with Windows text scaling.</summary>
public static class MetadataPillMetrics
{
    /// <summary>Label size in effective pixels.</summary>
    public const double FontSize = 14;
    /// <summary>Minimum pill height in effective pixels.</summary>
    public const double Height = 24;
    /// <summary>Minimum season width in effective pixels.</summary>
    public const double SeasonWidth = 48;
    /// <summary>Percentile minimum width: the web's 5.5 em.</summary>
    public const double PercentileWidth = FontSize * 5.5;
    /// <summary>Fluent control corner radius.</summary>
    public const double Radius = 4;
    /// <summary>Web season and percentile outline thickness.</summary>
    public const double Stroke = 2;

    /// <summary>Season column width including the shared pill's padding and outline.</summary>
    /// <param name="characters">Season label length.</param>
    /// <param name="scale">Text scale, already validated by the column fitter.</param>
    /// <returns>Width in effective pixels.</returns>
    public static double SeasonColumnWidth(int characters, double scale) =>
        Math.Max(SeasonWidth, Math.Ceiling(characters * LeaderboardColumnLayout.SeasonCharWidth) + 20) * scale;
}
#endregion
