namespace Festival.Core.Domain;

#region Paths selector layout
/// <summary>
/// Plan for the Paths dialog's compact selector row (three native <c>ComboBox</c>es: instrument, difficulty, display;
/// issues #88, #280). Each box is as wide as its longest option, so no option is clipped ("Pro Drums + Cymbals", 200% text)
/// and a box keeps its width whichever option is selected. When the three don't fit side by side, difficulty and display
/// reflow onto a second line under the instrument (Fluent responsive "Reflow"; WCAG 1.4.4). The plan depends only on the
/// row width and the measured options, never on the selection, so picking an instrument never moves the row.
/// </summary>
public static class PathSelectorLayout
{
    /// <summary>Width of the WinUI <c>ComboBox</c> template's drop-down glyph column (epx).</summary>
    public const double DropDownGlyphWidth = 38;

    /// <summary>Instrument icon (24 epx) plus its gap to the name (8 epx) in each instrument option.</summary>
    public const double InstrumentIconSpace = 32;

    /// <summary>Minimum width of the instrument box (issue #88).</summary>
    public const double InstrumentMinWidth = 120;

    /// <summary>Minimum width of the display (Image/Text) box (issue #88).</summary>
    public const double DisplayMinWidth = 96;

    /// <summary>Rounding slack for layout sizes, so a row that fits exactly stays on one line.</summary>
    private const double Slack = 0.5;

    /// <summary>A box's width for its longest option: the widest measured content plus the template's chrome.</summary>
    /// <param name="widestContent">Widest option content (epx, already text-scaled; instrument options include the icon).</param>
    /// <param name="paddingLeft">The box's left content padding (WinUI <c>ComboBoxPadding</c>, 12 epx).</param>
    /// <param name="paddingRight">The box's right content padding (0 epx by default).</param>
    /// <param name="minimum">The box's minimum width.</param>
    /// <returns>The width, at least <paramref name="minimum"/>.</returns>
    public static double BoxWidth(double widestContent, double paddingLeft, double paddingRight, double minimum) =>
        Math.Max(minimum, Math.Ceiling(Math.Max(0, widestContent) + paddingLeft + paddingRight + DropDownGlyphWidth));

    /// <summary>Whether difficulty and display move to a second line under the instrument box.</summary>
    /// <param name="available">Row width (epx).</param>
    /// <param name="instrument">Instrument box width for its longest option.</param>
    /// <param name="difficulty">Difficulty box width for its longest option.</param>
    /// <param name="display">Display box width for its longest option.</param>
    /// <param name="spacing">Gap between boxes.</param>
    /// <returns><see langword="true"/> when the three boxes and both gaps are wider than the row.</returns>
    public static bool Stacks(double available, double instrument, double difficulty, double display, double spacing) =>
        !double.IsInfinity(available) && instrument + difficulty + display + 2 * spacing > available + Slack;
}
#endregion
