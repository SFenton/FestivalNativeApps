using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Spotlight
/// <summary>Selected-player spotlight shown under an overview card or pinned above the Full Rankings pager.</summary>
public sealed partial class LeaderboardsSpotlight : UserControl
{
    /// <summary>Whether the spotlight sits inside an overview card (issue #643).</summary>
    private bool inCard;

    /// <summary>Spotlight model.</summary>
    public static readonly DependencyProperty SpotlightProperty = DependencyProperty.Register(
        nameof(Spotlight), typeof(RankingSpotlightViewModel), typeof(LeaderboardsSpotlight),
        new PropertyMetadata(null, (d, _) => ((LeaderboardsSpotlight)d).Bindings.Update()));

    /// <summary>Automation ID of the row host; loading and unranked states append <c>.loading</c> / <c>.unranked</c>.</summary>
    public static readonly DependencyProperty IdPrefixProperty = DependencyProperty.Register(
        nameof(IdPrefix), typeof(string), typeof(LeaderboardsSpotlight), new PropertyMetadata(null, (d, _) => ((LeaderboardsSpotlight)d).ApplyIds()));

    /// <summary>Creates the control.</summary>
    public LeaderboardsSpotlight()
    {
        InitializeComponent();
        IsTabStop = false;
    }

    /// <summary>
    /// Whether the spotlight floats over a board's rows (Full Rankings footer): gives the pinned row and the loading,
    /// failure and unranked cards an opaque backplate so rows scrolling underneath never show through.
    /// </summary>
    public bool IsFloating
    {
        get => PinnedRow.IsFloating;
        set
        {
            PinnedRow.IsFloating = LoadingRow.IsFloating = value;
            var backplate = value ? Visibility.Visible : Visibility.Collapsed;
            FailedBackplate.Visibility = UnrankedBackplate.Visibility = backplate;
        }
    }

    /// <summary>
    /// Whether the spotlight sits inside an overview card with the board's rows (Leaderboards, issue #643): the loading
    /// placeholder and the pinned row draw in-card <see cref="GroupedRowSlice"/>s after the card's rows (the placeholder
    /// under a hairline, the pinned row in its purple fill), and the failure and unranked note drop their own card for a
    /// hairline inset like the rows' and text aligned with the rows' content. Set once from markup (it only turns on).
    /// </summary>
    public bool InCard
    {
        get => inCard;
        set
        {
            if (inCard || !value) return;
            inCard = true;
            LoadingRow.Slice = GroupedRowSlice.For(1, 2, false, false, inCard: true);
            PinnedRow.Slice = GroupedRowSlice.For(1, 2, true, false, inCard: true);
            FailedLine.Visibility = UnrankedLine.Visibility = Visibility.Visible;
            foreach (var surface in new[] { FailedSurface, UnrankedSurface })
            {
                // No surface or outline in the card: the hairline Border above draws the only line.
                surface.Background = null;
                surface.BorderThickness = new Thickness(0);
                surface.Padding = new Thickness(GroupedRowSlice.SeparatorInset, 10, GroupedRowSlice.SeparatorInset, 10);
            }
        }
    }

    /// <summary>Spotlight model.</summary>
    public RankingSpotlightViewModel? Spotlight
    {
        get => (RankingSpotlightViewModel?)GetValue(SpotlightProperty);
        set => SetValue(SpotlightProperty, value);
    }

    /// <summary>Automation ID prefix.</summary>
    public string? IdPrefix
    {
        get => (string?)GetValue(IdPrefixProperty);
        set => SetValue(IdPrefixProperty, value);
    }

    /// <summary>
    /// Applies automation IDs to each state. The prefix goes on the pinned row's own UIA element (its Button) and the
    /// loading ring, since the StackPanels around them are not in the UIA control view; the inline failure's Retry gets
    /// <c>.retry</c> so several spotlights on one page stay distinct. The placeholder under the ring gets
    /// <c>.loading-row</c>: it stays raw-view only, so the ID only lets tests measure it (issue #527).
    /// </summary>
    private void ApplyIds()
    {
        if (IdPrefix is { } prefix)
        {
            PinnedRow.RowAutomationId = prefix;
            LoadingRow.RowAutomationId = prefix + ".loading-row";
            AutomationProperties.SetAutomationId(LoadingRing, prefix + ".loading");
            AutomationProperties.SetAutomationId(Unranked, prefix + ".unranked");
            Failed.RetryAutomationId = prefix + ".retry";
        }
    }
}
#endregion
