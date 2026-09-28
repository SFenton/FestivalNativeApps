using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Accessible group
/// <summary>
/// A content wrapper that appears in the UIA control view as a named <c>Group</c> (Borders and panels have no automation
/// peer). Wrapping a card in it lets Narrator announce "Lead, group" on entry and keeps rows that share a name (the same
/// player topping several charts) from being ambiguous siblings. Not focusable; content stretches.
/// </summary>
public sealed partial class AccessibleGroup : ContentControl
{
    /// <summary>Creates the group.</summary>
    public AccessibleGroup()
    {
        IsTabStop = false;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
    }

    /// <inheritdoc />
    protected override AutomationPeer OnCreateAutomationPeer() => new GroupPeer(this);

    /// <summary>Group peer named by <c>AutomationProperties.Name</c>.</summary>
    /// <param name="owner">Group.</param>
    private sealed partial class GroupPeer(AccessibleGroup owner) : FrameworkElementAutomationPeer(owner)
    {
        /// <inheritdoc />
        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Group;

        /// <inheritdoc />
        protected override string GetClassNameCore() => nameof(AccessibleGroup);
    }
}
#endregion
