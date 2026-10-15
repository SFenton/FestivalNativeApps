namespace Festival.Core.Domain;

#region Metadata layout
/// <summary>
/// Page-wide placement of Songs metadata pills (web <c>layoutMode.ts</c> <c>resolveCompactRowMode</c>): every row puts
/// all its pills beside the title when the list column fits the widest value of every enabled field, otherwise the first
/// pill stays top-right and the rest wrap under the title. One decision per page keeps rows consistent while scrolling;
/// <see cref="Hysteresis"/> stops a resize that hovers on the threshold from flipping the layout back and forth.
/// </summary>
public static class SongMetadataLayout
{
    #region Geometry

    /// <summary>Hysteresis in epx (web <c>COMPACT_HYSTERESIS</c>): an inline page stays inline until this much narrower.</summary>
    public const double Hysteresis = 32;

    /// <summary>Gap between trailing pills (the row card's trailing <c>StackPanel.Spacing</c>).</summary>
    public const double PillSpacing = 6;

    /// <summary>Chart icon edge shown before the pills on a non-Lead chart.</summary>
    public const double ChartIconSize = 20;

    /// <summary>Invalid-score indicator edge (a 40 epx button, Fluent's minimum target) at the end of the pills.</summary>
    public const double IndicatorSize = 40;

    /// <summary>
    /// Row chrome around the pills in epx: list end padding (12), item margins (8), card padding (10 + 14) and border (2),
    /// art (44) and the card's two column gaps (2 × 12).
    /// </summary>
    public const double RowChrome = 114;

    /// <summary>Width the title column keeps beside inline pills (about twenty characters before it marquees).</summary>
    public const double MinimumTitleWidth = 180;

    #endregion

    #region Test IDs

    /// <summary>Cross-platform test ID of one pill: <c>fst.songs.metadata.&lt;field&gt;.&lt;songId&gt;</c>.</summary>
    /// <param name="field">Field.</param>
    /// <param name="songId">Row song.</param>
    /// <returns>Automation ID, e.g. <c>fst.songs.metadata.lastplayed.fixture-pulse</c>.</returns>
    public static string AutomationId(MetadataField field, string songId) =>
        $"fst.songs.metadata.{field.ToString().ToLowerInvariant()}.{songId}";

    /// <summary>Test ID of the chart icon a non-Lead chart shows before the pills.</summary>
    /// <param name="songId">Row song.</param>
    /// <returns>Automation ID.</returns>
    public static string ChartAutomationId(string songId) => $"fst.songs.metadata.chart.{songId}";

    /// <summary>Test ID of a row's non-scored text ("No score", "Scores syncing", "Loading scores", …).</summary>
    /// <param name="songId">Row song.</param>
    /// <returns>Automation ID.</returns>
    public static string StateAutomationId(string songId) => $"fst.songs.metadata.state.{songId}";

    #endregion

    #region Decision

    /// <summary>
    /// The widest value each enabled field can show, for measuring the inline threshold at the current text size:
    /// a six-digit score, the full-combo <c>100%</c> (or <c>FC</c> with Percentage hidden), <c>Top 100%</c>, five stars, a two-digit
    /// current season, the intensity meter and the widest difficulty letter, plus a Last Played date (after a chart icon
    /// when unfiltered) only under the Last Played sort, the one sort that shows it.
    /// </summary>
    /// <param name="settings">Visibility settings.</param>
    /// <param name="lastPlayed">Rows show a Last Played entry (the Last Played sort).</param>
    /// <param name="lastPlayedChart">That entry carries its chart icon (no chart filter).</param>
    /// <returns>Sample fields, one per shown kind.</returns>
    public static IReadOnlyList<SongMetadataField> WidestSamples(AppSettings settings, bool lastPlayed = false, bool lastPlayedChart = false)
    {
        var samples = new List<SongMetadataField>();
        if (settings.MetadataScore)
            samples.Add(new(MetadataField.Score, ScoreFormatting.Score(999_999), ""));
        // A full combo always shows, even with Percentage hidden (FC-only).
        samples.Add(new(MetadataField.Percentage, settings.MetadataPercentage ? ScoreFormatting.Accuracy(1_000_000) : "FC", "")
            { FullCombo = true });
        if (settings.MetadataPercentile)
            samples.Add(new(MetadataField.Percentile, "Top 100%", "") { Percentile = SongPercentileTier.TopOne });
        if (settings.MetadataStars)
            samples.Add(new(MetadataField.Stars, new string('★', 5), "") { Stars = (5, true) });
        if (settings.MetadataSeason)
            samples.Add(new(MetadataField.Season, "S99", "") { CurrentSeason = true });
        if (settings.MetadataIntensity)
            samples.Add(new(MetadataField.Intensity, "", "") { IntensityRaw = 6 });
        if (settings.MetadataDifficulty)
            samples.Add(new(MetadataField.Difficulty, SongMetadataPolicy.DifficultyLetters[1], "") { GameDifficulty = 1 });
        if (lastPlayed)
            samples.Add(SongMetadataPolicy.LastPlayedField("2026-09-28T12:00:00Z", lastPlayedChart ? Instrument.ProDrums : null));
        return samples;
    }

    /// <summary>List width a row needs to show every pill beside a readable title.</summary>
    /// <param name="pillWidths">Measured widths of the pills (see <see cref="WidestSamples"/>).</param>
    /// <param name="namesChart">A non-Lead chart icon precedes the pills.</param>
    /// <param name="indicator">
    /// Rows may end with the invalid-score indicator (Filter Invalid Scores on), so its <see cref="IndicatorSize"/> is reserved
    /// page-wide rather than per row.
    /// </param>
    /// <returns>Required list width in epx.</returns>
    public static double RequiredWidth(IEnumerable<double> pillWidths, bool namesChart, bool indicator = false)
    {
        var widths = pillWidths.Where(w => double.IsFinite(w) && w > 0).ToList();
        if (namesChart) widths.Add(ChartIconSize);
        if (indicator) widths.Add(IndicatorSize);
        var trailing = widths.Sum() + PillSpacing * Math.Max(0, widths.Count - 1);
        return RowChrome + MinimumTitleWidth + trailing;
    }

    /// <summary>Whether rows put every pill inline for a list width, with hysteresis around the threshold.</summary>
    /// <param name="listWidth">List column width in epx.</param>
    /// <param name="required">Width from <see cref="RequiredWidth"/>.</param>
    /// <param name="wasInline">The page's current decision.</param>
    /// <returns><see langword="true"/> for one inline row of pills.</returns>
    public static bool Inline(double listWidth, double required, bool wasInline) =>
        double.IsFinite(listWidth) && listWidth > 0 && listWidth >= (wasInline ? required - Hysteresis : required);
    #endregion
}
#endregion
