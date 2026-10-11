namespace Festival.Core.Domain;

#region Wrap line layout
/// <summary>
/// Line-breaking rule for the app's left-to-right wrap panel (header tools such as Item Shop Sort, Filter and the
/// List/Grid toggle; rival pills). Items stay on one line while they fit and wrap only when they truly overflow
/// (page-tools-and-nav-chrome R11: tools wrap at large text sizes, never at the default size).
/// </summary>
public static class WrapLineLayout
{
    /// <summary>
    /// Overflow in epx still treated as a fit. Layout rounding can hand the arrange pass a width a fraction of a
    /// physical pixel narrower than the measured line (issue #516: the Item Shop List View button then broke onto a
    /// second line that measure never reserved, under the offer grid).
    /// </summary>
    public const double Tolerance = 1;

    /// <summary>Assigns each item to a line.</summary>
    /// <param name="widths">Items' desired widths in order.</param>
    /// <param name="available">Width available; infinite never wraps.</param>
    /// <param name="spacing">Gap between items on a line.</param>
    /// <returns>Zero-based line index per item.</returns>
    public static int[] Lines(IReadOnlyList<double> widths, double available, double spacing)
    {
        var lines = new int[widths.Count];
        double x = 0;
        var line = 0;
        for (var i = 0; i < widths.Count; i++)
        {
            if (x > 0 && x + widths[i] > available + Tolerance)
            {
                line++;
                x = 0;
            }
            lines[i] = line;
            x += widths[i] + spacing;
        }
        return lines;
    }
}
#endregion
