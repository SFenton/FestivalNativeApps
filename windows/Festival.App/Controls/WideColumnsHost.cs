using Festival.Core.Domain;
using Microsoft.UI.Xaml;

namespace Festival.App.Controls;

#region Window inputs
/// <summary>
/// The app side of pattern <c>wide-columns</c> (issue #653): feeds <see cref="WideColumns.Count"/> the element's window
/// width and the live Windows text size, so Player Profile's instrument sections
/// (<see cref="LeaderboardsCardGridLayout.UsesWideColumns"/>) and Suggestions' cards decide columns the same way.
/// </summary>
public static class WideColumnsHost
{
    /// <summary>Columns for cards sharing a width inside an element's window.</summary>
    /// <param name="element">Any element in the window (no window yet: one column).</param>
    /// <param name="contentWidth">Width the cards share, in epx.</param>
    /// <param name="spacing">Gutter between the columns, in epx.</param>
    /// <returns>1 or 2.</returns>
    public static int Count(UIElement? element, double contentWidth, double spacing) =>
        element?.XamlRoot is { } root
            ? WideColumns.Count(root.Size.Width, contentWidth, OnDemandSplitHost.TextScale, spacing)
            : 1;
}
#endregion
