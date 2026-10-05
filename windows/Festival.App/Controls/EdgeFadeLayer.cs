using Festival.Core.Domain;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Edge fade layer
/// <summary>
/// The hit-test-invisible host that paints <see cref="TopEdgeFade"/>'s masked copy of the Songs list. Decorative: it is
/// in the UIA raw view only (Narrator and the control view skip it) and reports the edge state
/// (<see cref="SongHeaderEdgeFade.Status"/>) as ItemStatus, so UI tests can assert the fade, the hard-edge fallback and
/// the hidden state without reading pixels.
/// </summary>
public sealed partial class EdgeFadeLayer : Grid
{
    /// <summary>Creates the layer in the raw view with the hidden state.</summary>
    public EdgeFadeLayer()
    {
        IsHitTestVisible = false;
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        AutomationProperties.SetItemStatus(this, SongHeaderEdgeFade.StatusHidden);
    }

    /// <summary>Publishes the edge state to UI Automation.</summary>
    /// <param name="status">A <c>SongHeaderEdgeFade.Status*</c> value.</param>
    public void SetStatus(string status)
    {
        if (AutomationProperties.GetItemStatus(this) != status) AutomationProperties.SetItemStatus(this, status);
    }

    /// <summary>A panel has no peer by default; this one exposes the raw-view state element for UI tests.</summary>
    /// <returns>Automation peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new FrameworkElementAutomationPeer(this);
}
#endregion
