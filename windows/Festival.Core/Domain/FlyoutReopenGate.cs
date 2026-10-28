namespace Festival.Core.Domain;

#region Gate
/// <summary>
/// Keeps a request to show a flyout that arrives while the same flyout is still closing, so it opens once it has
/// closed instead of being dropped (issue #684).
/// </summary>
/// <remarks>
/// WinUI's <c>FlyoutBase.ShowAt</c> ignores a request for the flyout and placement target that its flyout metadata
/// still records as open. <c>Hide</c> (Esc, a picked result) sets <c>IsOpen</c> to <see langword="false"/> at once,
/// but the metadata is only cleared after the presenter unloads at the end of the exit transition, just after
/// <c>Closed</c> is raised (<c>FlyoutBase::CheckAndHandleOpenFlyout</c> and <c>OnPresenterUnloaded</c> in
/// microsoft-ui-xaml). A click in that window did nothing; a slow host stretched it past a second.
/// </remarks>
public sealed class FlyoutReopenGate
{
    private bool presented;
    private bool pending;

    /// <summary>Whether the flyout is closing: shown, no longer open, and not yet closed.</summary>
    /// <param name="isOpen">The flyout's current <c>IsOpen</c>.</param>
    /// <returns><see langword="true"/> while a <c>ShowAt</c> would be ignored.</returns>
    public bool IsClosing(bool isOpen) => presented && !isOpen;

    /// <summary>Records the flyout's <c>Opened</c> event.</summary>
    public void Opened() => presented = true;

    /// <summary>Asks to show the flyout now; while it is closing the request is kept for <see cref="Closed"/>.</summary>
    /// <param name="isOpen">The flyout's current <c>IsOpen</c>.</param>
    /// <returns><see langword="true"/> when the caller should call <c>ShowAt</c> now.</returns>
    public bool RequestShow(bool isOpen)
    {
        if (!IsClosing(isOpen)) return true;
        pending = true;
        return false;
    }

    /// <summary>Records the flyout's <c>Closed</c> event and takes any request kept while it was closing.</summary>
    /// <returns>
    /// <see langword="true"/> when a request arrived while closing; the caller shows the flyout on a later dispatcher
    /// turn, because WinUI clears its open-flyout record only after the <c>Closed</c> handlers return.
    /// </returns>
    public bool Closed()
    {
        presented = false;
        var reopen = pending;
        pending = false;
        return reopen;
    }
}
#endregion
