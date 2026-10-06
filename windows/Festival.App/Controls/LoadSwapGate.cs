using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Load-swap gate
/// <summary>
/// Hosts a board's pinned "your score/rank" row under <see cref="LoadSwapVisual"/> (Content role) while keeping its slot,
/// so the pager and floating footer don't move during a reload (load-transition R2, issues #295 and #270). Unlike a
/// panel marked <c>AccessibilityView=Raw</c>, whose children stay in the UI Automation control view, a hidden gate
/// exposes no children, so Narrator never reads the stale row beside the spinner; it is disabled once fully transparent,
/// so Tab can't reach its invisible buttons either. The gate itself is never a control or content element.
/// </summary>
public sealed partial class LoadSwapGate : ContentControl
{
    private bool contentHidden;

    /// <summary>Creates a stretching, non-focusable gate.</summary>
    public LoadSwapGate()
    {
        IsTabStop = false;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
    }

    /// <summary>Whether the gated content is hidden from UI Automation (set by <see cref="LoadSwapVisual"/>).</summary>
    internal bool ContentHidden
    {
        get => contentHidden;
        set
        {
            if (contentHidden == value) return;
            contentHidden = value;
            FrameworkElementAutomationPeer.FromElement(this)?.RaiseStructureChangedEvent(AutomationStructureChangeType.ChildrenInvalidated, null);
        }
    }

    /// <summary>Creates the gate's children-hiding peer.</summary>
    /// <returns>Peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new GatePeer(this);

    /// <summary>A transparent peer: never itself in the control/content view, and childless while the gate hides.</summary>
    /// <param name="owner">Gate.</param>
    private sealed partial class GatePeer(LoadSwapGate owner) : FrameworkElementAutomationPeer(owner)
    {
        /// <inheritdoc />
        protected override IList<AutomationPeer>? GetChildrenCore() => owner.ContentHidden ? [] : base.GetChildrenCore();

        /// <inheritdoc />
        protected override bool IsControlElementCore() => false;

        /// <inheritdoc />
        protected override bool IsContentElementCore() => false;

        /// <inheritdoc />
        protected override string GetClassNameCore() => nameof(LoadSwapGate);
    }
}
#endregion
