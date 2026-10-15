namespace Festival.Core.Domain;

#region Suggestion row metrics
/// <summary>
/// Vertical layout of a Suggestions row (web <c>CategoryCard</c> row, Android <c>SuggestionRowView</c>). A row is one
/// centred line (art, title/subtitle, metadata, chevron) unless it is narrow and its metadata is wide (instrument chips or
/// a rival pill), when the metadata moves to a second line under the title like the web's two-row layout. The gap between
/// the lines exists only when there is a second line: an empty second line's spacing pushed one-line rows' content
/// <see cref="LineSpacing"/>/2 epx above the row's centre (issue #654).
/// </summary>
public static class SuggestionRowMetrics
{
    /// <summary>Row width (epx) under which wide metadata moves under the title.</summary>
    public const double NarrowWidth = 440;

    /// <summary>Gap between a two-line row's title line and its metadata line (epx).</summary>
    public const double LineSpacing = 6;

    /// <summary>Whether the row puts its metadata on a second line under the title.</summary>
    /// <param name="layout">The row's metadata layout, or none before the row has data.</param>
    /// <param name="width">The row's width (epx); 0 before the first layout pass.</param>
    /// <param name="hasMetadata">Whether the row shows any metadata.</param>
    /// <returns>True for a narrow row with instrument chips or a rival pill.</returns>
    public static bool StacksMetadata(SuggestionRowLayout? layout, double width, bool hasMetadata) =>
        hasMetadata && width > 0 && width < NarrowWidth && layout is SuggestionRowLayout.InstrumentChips or SuggestionRowLayout.Rival;

    /// <summary>Spacing between the row's grid lines: <see cref="LineSpacing"/> on a two-line row, none on a one-line row.</summary>
    /// <param name="stacked">Whether the metadata is on a second line (<see cref="StacksMetadata"/>).</param>
    /// <returns>Row spacing (epx).</returns>
    public static double RowSpacing(bool stacked) => stacked ? LineSpacing : 0;
}
#endregion
