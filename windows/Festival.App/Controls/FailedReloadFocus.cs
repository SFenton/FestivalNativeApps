using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Failed reload focus
/// <summary>
/// Keeps keyboard focus on a paged board when a reload hides the control that had it. A board's pager and pinned row
/// hide when a page fails (load-transition R4), and its failure's Retry hides while it reloads; WinUI then drops focus on
/// the first focusable element, the title bar's Back button, far from the board. Once the reload settles this moves
/// focus to the failure's Retry, or back into the pager when the board loaded (issue #283). Focus that you move away
/// yourself is left alone.
/// </summary>
internal sealed class FailedReloadFocus
{
    private readonly ServiceStatusView status;
    private readonly Control pager;
    private readonly Func<bool> settled;
    private readonly Func<bool> failed;
    private bool pending;

    /// <summary>Follows the footer and the failure for hidden focus.</summary>
    /// <param name="chrome">The board's floating footer (pinned row and pager).</param>
    /// <param name="pager">Where focus returns when the reload succeeds.</param>
    /// <param name="status">The failure shown in the rows' place.</param>
    /// <param name="settled">Whether the reload has committed and its content is revealed.</param>
    /// <param name="failed">Whether the committed state is the failure.</param>
    private FailedReloadFocus(UIElement chrome, Control pager, ServiceStatusView status, Func<bool> settled, Func<bool> failed)
    {
        (this.pager, this.status, this.settled, this.failed) = (pager, status, settled, failed);
        chrome.LosingFocus += (_, args) => OnLosingFocus(args, chrome);
        status.LosingFocus += (_, args) => OnLosingFocus(args, status);
    }

    /// <summary>Gives a board's footer and failure the focus hand-off.</summary>
    /// <param name="chrome">The board's floating footer (pinned row and pager).</param>
    /// <param name="pager">Where focus returns when the reload succeeds.</param>
    /// <param name="status">The failure shown in the rows' place.</param>
    /// <param name="settled">Whether the reload has committed and its content is revealed.</param>
    /// <param name="failed">Whether the committed state is the failure.</param>
    /// <returns>The hand-off; call <see cref="Settle"/> when the board's load swap reveals content.</returns>
    public static FailedReloadFocus Attach(UIElement chrome, Control pager, ServiceStatusView status, Func<bool> settled, Func<bool> failed) =>
        new(chrome, pager, status, settled, failed);

    /// <summary>Hands pending focus on once the reload has settled; call from the load swap's <c>ContentRevealed</c>.</summary>
    public void Settle() => status.DispatcherQueue.TryEnqueue(Resolve);

    /// <summary>Notes focus taken by a collapse (not by the user moving it) and resolves it if the board already settled.</summary>
    /// <param name="args">Focus change.</param>
    /// <param name="root">Watched element.</param>
    private void OnLosingFocus(LosingFocusEventArgs args, UIElement root)
    {
        if (args.OldFocusedElement is not UIElement old || IsShown(old, root)) return;
        pending = true;
        Settle();
    }

    /// <summary>Focuses Retry after a failure, or the pager after a load, when a collapse took focus.</summary>
    private void Resolve()
    {
        if (!pending || !settled()) return;
        pending = false;
        if (failed()) status.FocusRetryWhenShown();
        else status.DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, () =>
        {
            if (FocusManager.FindFirstFocusableElement(pager) is Control first) first.Focus(FocusState.Programmatic);
        });
    }

    /// <summary>Whether <paramref name="element"/> and its ancestors up to <paramref name="root"/> are all visible.</summary>
    /// <param name="element">Element that is losing focus.</param>
    /// <param name="root">Topmost ancestor to check.</param>
    /// <returns><see langword="false"/> when a collapse took focus away.</returns>
    private static bool IsShown(DependencyObject element, UIElement root)
    {
        for (DependencyObject? node = element; node is not null; node = VisualTreeHelper.GetParent(node))
        {
            if (node is UIElement { Visibility: Visibility.Collapsed }) return false;
            if (ReferenceEquals(node, root)) return true;
        }
        return true;
    }
}
#endregion