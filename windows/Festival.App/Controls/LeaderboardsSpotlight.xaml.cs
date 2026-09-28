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

    /// <summary>Automation ID of the jump button.</summary>
    public static readonly DependencyProperty JumpAutomationIdProperty = DependencyProperty.Register(
        nameof(JumpAutomationId), typeof(string), typeof(LeaderboardsSpotlight), new PropertyMetadata(null, (d, _) => ((LeaderboardsSpotlight)d).ApplyIds()));

    /// <summary>Creates the control.</summary>
    public LeaderboardsSpotlight()
    {
        InitializeComponent();
        IsTabStop = false;
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

    /// <summary>Jump button automation ID.</summary>
    public string? JumpAutomationId
    {
        get => (string?)GetValue(JumpAutomationIdProperty);
        set => SetValue(JumpAutomationIdProperty, value);
    }

    /// <summary>Applies automation IDs to each state.</summary>
    private void ApplyIds()
    {
        if (IdPrefix is { } prefix)
        {
            AutomationProperties.SetAutomationId(RowHost, prefix);
            AutomationProperties.SetAutomationId(LoadingRow, prefix + ".loading");
            AutomationProperties.SetAutomationId(Unranked, prefix + ".unranked");
        }
        AutomationProperties.SetAutomationId(Jump, JumpAutomationId ?? (IdPrefix is null ? "" : IdPrefix + "-jump"));
    }
}
#endregion
