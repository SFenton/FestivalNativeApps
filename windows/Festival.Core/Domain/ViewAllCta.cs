namespace Festival.Core.Domain;

#region View all call to action
/// <summary>
/// Labels and accessible names of the full-width accent "View all" buttons below a card's rows (XAML
/// <c>FSTViewAllButtonStyle</c>; web <c>ViewFullLeaderboardCta</c>, Rivals <c>viewAllButton</c> and <c>GraphCard</c>).
/// Song Detail's View Full Leaderboard and View All Scores, the Rivals hub's View All Rivals and the Leaderboards cards'
/// View All Rankings share one name rule (issues #207, #268; pattern <c>view-all-cta</c>).
/// </summary>
public static class ViewAllCta
{
    /// <summary>Song Detail instrument and band cards (web <c>leaderboard.viewFullLeaderboard</c>, Title Case).</summary>
    public const string FullLeaderboardLabel = "View Full Leaderboard";

    /// <summary>Rivals hub cards (web <c>rivals.viewAllRivals</c>, Title Case).</summary>
    public const string RivalsLabel = "View All Rivals";

    /// <summary>Leaderboards cards before the optional count (web <c>viewAllRankingsWithCount</c>, Title Case).</summary>
    public const string RankingsLabel = "View All Rankings";

    /// <summary>Song Detail Score History list (web <c>chart.viewAllScores</c>, Title Case).</summary>
    public const string ScoresLabel = "View All Scores";

    /// <summary>Profile Bands groups before the count (web <c>player.viewAllBands</c>, Title Case; issue #312). Shown on the
    /// frosted <c>ViewAllCard</c> (surface-materials R7), not the accent button; only the label and name rule are shared.</summary>
    public const string BandsLabel = "View All Bands";

    /// <summary>Plain label where the title already names the list, e.g. the Profile Bands title-row link
    /// (section-headers R8; "View All", never "See All", owner #321).</summary>
    public const string ListLabel = "View All";

    /// <summary>Accessible name that starts with the visible label so voice control and Narrator match it (WCAG 2.5.3),
    /// then names the card so equal buttons in different cards stay distinct.</summary>
    /// <param name="label">Visible button text.</param>
    /// <param name="card">Card title, e.g. "Lead", "Duos" or "Lead Rivals".</param>
    /// <returns>For example "View Full Leaderboard, Lead".</returns>
    public static string Name(string label, string card) => $"{label}, {card}";
}
#endregion
