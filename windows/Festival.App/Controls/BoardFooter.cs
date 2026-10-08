using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Board footer
/// <summary>
/// The web's fixed leaderboard footer (<c>FixedLeaderboardPlayerFooter</c> + <c>FixedLeaderboardPagination</c>): the pinned
/// "your rank" row and the pager float over the bottom of the scrolling rows, which scroll on beneath their frosted
/// surfaces. <see cref="Inset"/> keeps the last row reachable by giving the rows a bottom margin as tall as the footer
/// (web <c>useLeaderboardFooterScrollMargin</c>), and keeps a focused row clear of the footer.
/// </summary>
public static class BoardFooter
{
    /// <summary>Gap between the last row and the footer when scrolled to the end, epx (web <c>Gap.sm</c>).</summary>
    private const double Gap = 4;

    /// <summary>
    /// Keeps <paramref name="content"/>'s bottom margin equal to <paramref name="footer"/>'s height, and a focused row
    /// (Tab, arrows, Narrator) out from under the footer (<see cref="KeepFocusClear"/>).
    /// </summary>
    /// <param name="footer">Overlay footer (bottom-aligned in the same cell as the list).</param>
    /// <param name="content">The scrolled rows.</param>
    public static void Inset(FrameworkElement footer, FrameworkElement content)
    {
        footer.SizeChanged += (_, _) => Apply(footer, content);
        footer.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => Apply(footer, content));
        KeepFocusClear(footer, content);
    }

    /// <summary>The footer's height plus the end gap, epx; 0 while it is collapsed.</summary>
    /// <param name="footer">Footer.</param>
    /// <returns>Inset height.</returns>
    private static double Height(FrameworkElement footer) =>
        footer.Visibility == Visibility.Visible ? footer.ActualHeight + footer.Margin.Bottom + Gap : 0;

    /// <summary>
    /// The footer floats over the bottom of the scroller's viewport, so a focus scroll that only reaches the viewport's
    /// bottom edge leaves the row under the pinned row and pager. Each unaligned bring-into-view request from the rows
    /// grows downwards by the footer's height before the scroller handles it (WCAG 2.4.11, focus not obscured; issue
    /// #409). Explicit alignments, such as the centred jump to the selected row, are left alone. A list control's own
    /// scroller sits inside it, so its items panel takes the handler.
    /// </summary>
    /// <param name="footer">Footer.</param>
    /// <param name="content">Rows: content inside a <see cref="ScrollViewer"/>, or a list view.</param>
    private static void KeepFocusClear(FrameworkElement footer, FrameworkElement content)
    {
        void Grow(UIElement sender, BringIntoViewRequestedEventArgs args)
        {
            if (!double.IsNaN(args.VerticalAlignmentRatio)) return;
            var target = args.TargetRect;
            args.TargetRect = new Windows.Foundation.Rect(target.X, target.Y, target.Width,
                LeaderboardPaging.RevealAboveFooter(target.Height, Height(footer)));
        }

        if (content is not ListViewBase list)
        {
            content.BringIntoViewRequested += Grow;
            return;
        }
        // The items panel exists only once the list has items (it stays collapsed until rows arrive), so it is hooked
        // when containers are prepared rather than on Loaded.
        UIElement? hooked = null;
        list.ContainerContentChanging += (_, _) =>
        {
            if (list.ItemsPanelRoot is not { } panel || ReferenceEquals(panel, hooked)) return;
            panel.BringIntoViewRequested += Grow;
            hooked = panel;
        };
    }

    /// <summary>Applies the margin.</summary>
    /// <param name="footer">Footer.</param>
    /// <param name="content">Rows.</param>
    private static void Apply(FrameworkElement footer, FrameworkElement content)
    {
        var height = Height(footer);
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
