namespace Festival.Core.Domain;

#region Paths table layout
/// <summary>
/// Column widths and the stacking breakpoint for the CHOpt Paths text table (web <c>COLUMN_WIDTHS</c>, issue #223). The
/// beat, time and score columns and the Overdrive % label hold text, so they grow with the Windows text size; the
/// activation (fret pills) and Overdrive bar columns share the remaining width. The breakpoint below which each card
/// stacks (web mobile rows) grows by the same extra width, so larger text stacks the cards rather than clipping values.
/// </summary>
public static class PathTableLayout
{
    /// <summary>Table width (epx at 100% text) below which cards stack.</summary>
    public const double StackWidth = 640;

    /// <summary>Activation column minimum (epx): five 22 epx pills and the "Open" label at 100% text.</summary>
    public const double NoteMinWidth = 190;

    /// <summary>Overdrive bar minimum (epx); the bar is decorative beside its percentage label.</summary>
    public const double OdBarMinWidth = 80;

    /// <summary>Overdrive % label minimum (epx at 100% text).</summary>
    public const double OdLabelWidth = 32;

    /// <summary>Fixed text column width at 100% text, or <see langword="null"/> for the star-sized columns.</summary>
    /// <param name="key">Column.</param>
    /// <returns>Width in epx, or null for activation and Overdrive.</returns>
    public static double? BaseWidth(PathColumnKey key) => key switch
    {
        PathColumnKey.Beat => 80,
        PathColumnKey.Time => 110,
        PathColumnKey.Score => 100,
        _ => null,
    };

    /// <summary>Fixed text column width for the Windows text size, or <see langword="null"/> for star-sized columns.</summary>
    /// <param name="key">Column.</param>
    /// <param name="textScale">Text size factor (1–2.25).</param>
    /// <returns>Width in epx, or null for activation and Overdrive.</returns>
    public static double? Width(PathColumnKey key, double textScale) =>
        BaseWidth(key) is { } width ? TextScaling.ScaledWidth(width, textScale) : null;

    /// <summary>Overdrive % label minimum width for the Windows text size.</summary>
    /// <param name="textScale">Text size factor (1–2.25).</param>
    /// <returns>Width in epx.</returns>
    public static double OdLabelMinWidth(double textScale) => TextScaling.ScaledWidth(OdLabelWidth, textScale);

    /// <summary>Table width below which cards stack: <see cref="StackWidth"/> plus the extra width the text columns need.</summary>
    /// <param name="textScale">Text size factor (1–2.25).</param>
    /// <returns>Breakpoint in epx.</returns>
    public static double StackBreakpoint(double textScale)
    {
        var textWidth = BaseWidth(PathColumnKey.Beat)!.Value + BaseWidth(PathColumnKey.Time)!.Value
            + BaseWidth(PathColumnKey.Score)!.Value + OdLabelWidth;
        var scaled = Width(PathColumnKey.Beat, textScale)!.Value + Width(PathColumnKey.Time, textScale)!.Value
            + Width(PathColumnKey.Score, textScale)!.Value + OdLabelMinWidth(textScale);
        return StackWidth + scaled - textWidth;
    }

    /// <summary>Whether activation cards stack (caption above each value) at this table width.</summary>
    /// <param name="tableWidth">Table width in epx; 0 or less before layout keeps the grid.</param>
    /// <param name="textScale">Text size factor (1–2.25).</param>
    /// <returns><see langword="true"/> to stack.</returns>
    public static bool Stacks(double tableWidth, double textScale) =>
        tableWidth > 0 && tableWidth < StackBreakpoint(textScale);
}
#endregion
