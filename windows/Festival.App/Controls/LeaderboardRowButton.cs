using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Leaderboard row button
/// <summary>
/// The full-row button behind <see cref="LeaderboardEntryRow"/>. A row with a destination is a normal UIA button
/// (Invoke, Narrator "button"). A row without one (production serves some empty account IDs) is already not
/// clickable or tabbable, and its automation peer reports it as plain text with no Invoke pattern, so assistive tech
/// doesn't present it as actionable (issue #63; Android's "Profile unavailable" text row). Rival rows on the Rivals hub
/// reuse it for anonymous leaderboard rivals (issue #213).
/// </summary>
public sealed partial class LeaderboardRowButton : Button
{
    /// <summary>Whether the row opens something; set by <see cref="LeaderboardEntryRow"/> with the row's route.</summary>
    public bool IsActionable { get; set; } = true;

    /// <summary>Creates the route-aware peer.</summary>
    /// <returns>Automation peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new RowPeer(this);

    /// <summary>Button peer that reads as static text and offers no Invoke while the row has no destination.</summary>
    /// <param name="owner">Row button.</param>
    private sealed partial class RowPeer(LeaderboardRowButton owner) : ButtonAutomationPeer(owner)
    {
        /// <inheritdoc />
        protected override AutomationControlType GetAutomationControlTypeCore() =>
            owner.IsActionable ? AutomationControlType.Button : AutomationControlType.Text;

        /// <inheritdoc />
        protected override string GetLocalizedControlTypeCore() => owner.IsActionable ? base.GetLocalizedControlTypeCore() : "text";

        /// <inheritdoc />
        protected override object? GetPatternCore(PatternInterface patternInterface) =>
            patternInterface == PatternInterface.Invoke && !owner.IsActionable ? null : base.GetPatternCore(patternInterface);
    }
}
#endregion
