using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Metadata pill
/// <summary>
/// One Songs-row metadata pill host (score text, accuracy box, stars, intensity meter, …). UI Automation sees exactly one
/// raw-view element per pill, named with the field's spoken text and carrying its <c>fst.songs.metadata.*</c> ID; the
/// inner text, stars and meter are decoration of that element, so a row never exposes extra stops for Narrator (the row's
/// list item already speaks every field).
/// </summary>
public sealed partial class MetadataPill : Grid
{
    /// <summary>Control type the peer reports: <see cref="AutomationControlType.Text"/> or an image (stars, meter).</summary>
    public AutomationControlType ControlType { get; set; } = AutomationControlType.Text;

    /// <summary>Names the pill for UI Automation and keeps it in the raw view (the row item speaks every field).</summary>
    /// <param name="name">Spoken text.</param>
    /// <param name="automationId">Test ID, or <see langword="null"/>.</param>
    public void Label(string name, string? automationId)
    {
        AutomationProperties.SetName(this, name);
        if (automationId is not null) AutomationProperties.SetAutomationId(this, automationId);
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
    }

    /// <summary>Exposes the pill as one element with no children (a bare panel has no automation peer).</summary>
    /// <returns>Automation peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new MetadataPillPeer(this);

    /// <summary>Text- or image-typed peer with no children.</summary>
    /// <param name="owner">Pill.</param>
    private sealed partial class MetadataPillPeer(MetadataPill owner) : FrameworkElementAutomationPeer(owner)
    {
        /// <inheritdoc />
        protected override AutomationControlType GetAutomationControlTypeCore() => owner.ControlType;

        /// <inheritdoc />
        protected override string GetClassNameCore() => nameof(MetadataPill);

        /// <inheritdoc />
        protected override IList<AutomationPeer>? GetChildrenCore() => null;
    }
}
#endregion
