namespace Festival.Core.Domain;

#region View all call to action
/// <summary>
/// Labels and accessible names of the full-width accent "View all" buttons below a card's rows (XAML
/// <c>FSTViewAllButtonStyle</c>; web <c>ViewFullLeaderboardCta</c> and Rivals <c>viewAllButton</c>).
/// Song Detail's View Full Leaderboard, the Rivals hub's View All Rivals and the Leaderboards cards' View All Rankings
/// share one name rule (issues #207, #268).
/// </summary>
public static class ViewAllCta
{
    /// <summary>Song Detail instrument and band cards (web <c>leaderboard.viewFullLeaderboard</c>, Title Case).</summary>
    public const string FullLeaderboardLabel = "View Full Leaderboard";

    /// <summary>Rivals hub cards (web <c>rivals.viewAllRivals</c>, Title Case).</summary>
    public const string RivalsLabel = "View All Rivals";

    /// <summary>Accessible name that starts with the visible label so voice control and Narrator match it (WCAG 2.5.3),
    /// then names the card so equal buttons in different cards stay distinct.</summary>
    /// <param name="label">Visible button text.</param>
    /// <param name="card">Card title, e.g. "Lead", "Duos" or "Lead Rivals".</param>
    /// <returns>For example "View Full Leaderboard, Lead".</returns>
    public static string Name(string label, string card) => $"{label}, {card}";
}
#endregion
