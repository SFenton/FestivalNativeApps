using Microsoft.UI.Xaml;

namespace Festival.App.Controls;

#region Board footer
/// <summary>
/// The web's fixed leaderboard footer (<c>FixedLeaderboardPlayerFooter</c> + <c>FixedLeaderboardPagination</c>): the pinned
/// "your rank" row and the pager float over the bottom of the scrolling rows, which scroll on beneath their frosted
/// surfaces. <see cref="Inset"/> keeps the last row reachable by giving the rows a bottom margin as tall as the footer
/// (web <c>useLeaderboardFooterScrollMargin</c>).
/// </summary>
public static class BoardFooter
{
    /// <summary>Gap between the last row and the footer when scrolled to the end, epx (web <c>Gap.sm</c>).</summary>
    private const double Gap = 4;

    /// <summary>Keeps <paramref name="content"/>'s bottom margin equal to <paramref name="footer"/>'s height.</summary>
    /// <param name="footer">Overlay footer (bottom-aligned in the same cell as the list).</param>
    /// <param name="content">The scrolled rows.</param>
    public static void Inset(FrameworkElement footer, FrameworkElement content)
    {
        footer.SizeChanged += (_, _) => Apply(footer, content);
        footer.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => Apply(footer, content));
    }

    /// <summary>Applies the margin.</summary>
    /// <param name="footer">Footer.</param>
    /// <param name="content">Rows.</param>
    private static void Apply(FrameworkElement footer, FrameworkElement content)
    {
        var height = footer.Visibility == Visibility.Visible ? footer.ActualHeight + footer.Margin.Bottom + Gap : 0;
        // A scrolling control (ListView) pads inside its scroller; plain content (a repeater in a ScrollViewer) gets a margin.
        if (content is Microsoft.UI.Xaml.Controls.Control control)
        {
            var padding = control.Padding;
            if (Math.Abs(padding.Bottom - height) >= 0.5) control.Padding = new Thickness(padding.Left, padding.Top, padding.Right, height);
            return;
        }
        var margin = content.Margin;
        if (Math.Abs(margin.Bottom - height) < 0.5) return;
        content.Margin = new Thickness(margin.Left, margin.Top, margin.Right, height);
    }
}
#endregion
