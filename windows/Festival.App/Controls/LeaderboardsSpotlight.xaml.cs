using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Spotlight
/// <summary>Selected-player spotlight shown under an overview card or pinned above the Full Rankings pager.</summary>
public sealed partial class LeaderboardsSpotlight : UserControl
{
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
            PinnedRow.IsFloating = value;
            var backplate = value ? Visibility.Visible : Visibility.Collapsed;
            LoadingBackplate.Visibility = FailedBackplate.Visibility = UnrankedBackplate.Visibility = backplate;
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
    /// <c>.retry</c> so several spotlights on one page stay distinct.
    /// </summary>
    private void ApplyIds()
    {
        if (IdPrefix is { } prefix)
        {
            PinnedRow.RowAutomationId = prefix;
            AutomationProperties.SetAutomationId(LoadingRing, prefix + ".loading");
            AutomationProperties.SetAutomationId(Unranked, prefix + ".unranked");
            Failed.RetryAutomationId = prefix + ".retry";
        }
    }
}
#endregion
