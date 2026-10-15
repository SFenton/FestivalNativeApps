namespace Festival.Core.Domain;

#region Paths selector arrangement
/// <summary>How the Paths dialog's compact selector row is drawn (<see cref="PathSelectorLayout.Plan"/>).</summary>
public enum PathSelectorArrangement
{
    /// <summary>One line; the instrument and display boxes show their icon and name.</summary>
    Labelled,

    /// <summary>
    /// One line; the instrument and display boxes show only their icon (owner-approved, issue #612: "just show
    /// instrument icon and image/text icon in dropdowns like web"), and difficulty takes the remaining width.
    /// </summary>
    IconOnly,

    /// <summary>
    /// Even icon-only boxes don't fit: the labelled instrument box spans the first line and difficulty and display
    /// share the second (issue #280).
    /// </summary>
    Stacked,
}
#endregion

#region Paths selector layout
/// <summary>
/// Plan for the Paths dialog's compact selector row (three native <c>ComboBox</c>es: instrument, difficulty, display;
/// issues #88, #280, #612). Each labelled box is as wide as its longest option, so no option is clipped ("Pro Drums +
/// Cymbals", 200% text) and a box keeps its width whichever option is selected. When the labelled boxes don't fit side by
/// side, the instrument and display boxes drop their names and show only their icons, like the web's mobile Paths
/// selectors (issue #612); only when even that doesn't fit do difficulty and display reflow onto a second line under the
/// instrument (Fluent responsive "Reflow"; WCAG 1.4.4). The plan depends only on the row width and the measured options,
/// never on the selection, so picking an instrument never moves the row.
/// </summary>
public static class PathSelectorLayout
{
    /// <summary>Width of the WinUI <c>ComboBox</c> template's drop-down glyph column (epx).</summary>
    public const double DropDownGlyphWidth = 38;

    /// <summary>Instrument icon size in each option and in the icon-only box (epx).</summary>
    public const double InstrumentIconSize = 24;

    /// <summary>Display (Image/Text) glyph size in each option and in the icon-only box (web <c>IoImage size={20}</c>).</summary>
    public const double DisplayIconSize = 20;

    /// <summary>Gap between an option's icon and its name (epx).</summary>
    public const double IconGap = 8;

    /// <summary>Instrument icon (24 epx) plus its gap to the name (8 epx) in each instrument option.</summary>
    public const double InstrumentIconSpace = InstrumentIconSize + IconGap;

    /// <summary>Display glyph (20 epx) plus its gap to the name (8 epx) in each display option.</summary>
    public const double DisplayIconSpace = DisplayIconSize + IconGap;

    /// <summary>Fluent minimum touch target (<c>FSTMinTargetSize</c>, epx): the narrowest an icon-only box gets.</summary>
    public const double FSTMinTarget = 40;

    /// <summary>Minimum width of the instrument box (issue #88).</summary>
    public const double InstrumentMinWidth = 120;

    /// <summary>Minimum width of the display (Image/Text) box (issue #88).</summary>
    public const double DisplayMinWidth = 96;

    /// <summary>Minimum width of each wide selector box (difficulty, display; issue #650).</summary>
    public const double WideBoxMinWidth = 200;

    /// <summary>Rounding slack for layout sizes, so a row that fits exactly stays on one line.</summary>
    private const double Slack = 0.5;

    /// <summary>
    /// The shared width of the wide difficulty and display selector boxes: the wider labelled box, at least
    /// <see cref="WideBoxMinWidth"/>, so the pair reads as one centred row of equal boxes like the web's desktop selector
    /// row (issue #650) and neither clips its longest option at any text scale.
    /// </summary>
    /// <param name="difficulty">Difficulty box width for its longest option (<see cref="BoxWidth"/>).</param>
    /// <param name="display">Labelled display box width for its longest option.</param>
    /// <returns>The width both boxes use.</returns>
    public static double WideBoxWidth(double difficulty, double display) =>
        Math.Max(WideBoxMinWidth, Math.Max(difficulty, display));

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

    /// <summary>An icon-only box's width: the icon plus the template's padding and drop-down glyph column.</summary>
    /// <param name="iconSize">Icon width (epx).</param>
    /// <param name="paddingLeft">The box's left content padding.</param>
    /// <param name="paddingRight">The box's right content padding.</param>
    /// <returns>The width, at least <see cref="FSTMinTarget"/>.</returns>
    public static double IconBoxWidth(double iconSize, double paddingLeft, double paddingRight) =>
        BoxWidth(iconSize, paddingLeft, paddingRight, FSTMinTarget);

    /// <summary>Chooses the compact row's arrangement: labelled, then icon-only, then stacked (issue #612).</summary>
    /// <param name="available">Row width (epx).</param>
    /// <param name="instrument">Labelled instrument box width for its longest option.</param>
    /// <param name="difficulty">Difficulty box width for its longest option.</param>
    /// <param name="display">Labelled display box width for its longest option.</param>
    /// <param name="iconInstrument">Icon-only instrument box width (<see cref="IconBoxWidth"/>).</param>
    /// <param name="iconDisplay">Icon-only display box width.</param>
    /// <param name="spacing">Gap between boxes.</param>
    /// <returns>The first arrangement whose boxes fit on one line, else <see cref="PathSelectorArrangement.Stacked"/>.</returns>
    public static PathSelectorArrangement Plan(double available, double instrument, double difficulty, double display,
        double iconInstrument, double iconDisplay, double spacing)
    {
        if (!Stacks(available, instrument, difficulty, display, spacing)) return PathSelectorArrangement.Labelled;
        return Stacks(available, iconInstrument, difficulty, iconDisplay, spacing)
            ? PathSelectorArrangement.Stacked
            : PathSelectorArrangement.IconOnly;
    }
}
#endregion
