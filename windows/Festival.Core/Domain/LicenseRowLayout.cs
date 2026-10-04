namespace Festival.Core.Domain;

#region Licenses layout
/// <summary>
/// Layout rules for the Licenses page (issue #215): when a row is narrow for the current Windows text size, the license
/// badge moves under the package name (Fluent "reposition": side details move below the main content on narrow widths),
/// so the name keeps the row's width instead of truncating; the detail dialog's license text gets a window-capped scroller.
/// </summary>
public static class LicenseRowLayout
{
    /// <summary>Row content width (epx at 100% text) below which the badge stacks under the name.</summary>
    public const double StackWidth = 440;

    /// <summary>Tallest the detail dialog's license text scroller gets (epx).</summary>
    public const double DetailTextMaxHeight = 420;

    /// <summary>Shortest the detail dialog's license text scroller gets (epx), even in a short window.</summary>
    public const double DetailTextMinHeight = 160;

    /// <summary>Window height (epx) the dialog chrome, title, subtitle, project link and Close take around the text.</summary>
    public const double DetailChromeHeight = 320;

    /// <summary>Whether the license badge sits under the package name rather than trailing it.</summary>
    /// <param name="contentWidth">Row content width in epx (inside the row padding); 0 or less before layout.</param>
    /// <param name="textScale">Windows text size factor (1–2.25).</param>
    /// <returns><see langword="true"/> to stack the badge under the name.</returns>
    public static bool StacksBadge(double contentWidth, double textScale) =>
        contentWidth > 0 && contentWidth < StackWidth * (double.IsFinite(textScale) ? Math.Max(1, textScale) : 1);

    /// <summary>Maximum height of the detail dialog's license text scroller for a window.</summary>
    /// <param name="windowHeight">Window content height in epx (NaN or 0 before layout).</param>
    /// <returns>Height between <see cref="DetailTextMinHeight"/> and <see cref="DetailTextMaxHeight"/>.</returns>
    public static double DetailTextHeight(double windowHeight) =>
        double.IsFinite(windowHeight) && windowHeight > 0
            ? Math.Clamp(windowHeight - DetailChromeHeight, DetailTextMinHeight, DetailTextMaxHeight)
            : DetailTextMaxHeight;
}
#endregion
