using System.ComponentModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Pager
/// <summary>Shared paginator for Full Rankings, Band Rankings and the song leaderboard (IDs <c>&lt;prefix&gt;.page-*</c>).</summary>
public sealed partial class LeaderboardsPager : UserControl
{
    /// <summary>Pager model.</summary>
    public static readonly DependencyProperty PagerProperty = DependencyProperty.Register(
        nameof(Pager), typeof(RankingsPagerViewModel), typeof(LeaderboardsPager),
        new PropertyMetadata(null, (d, e) => ((LeaderboardsPager)d).Attach(e.OldValue as RankingsPagerViewModel)));

    /// <summary>Creates the pager.</summary>
    public LeaderboardsPager() => InitializeComponent();

    /// <summary>Pager model.</summary>
    public RankingsPagerViewModel? Pager
    {
        get => (RankingsPagerViewModel?)GetValue(PagerProperty);
        set => SetValue(PagerProperty, value);
    }

    /// <summary>Hides First/Last when the available width is below the full plate (compact windows).</summary>
    /// <param name="availableSize">Width offered by the page.</param>
    /// <returns>Desired size.</returns>
    protected override Windows.Foundation.Size MeasureOverride(Windows.Foundation.Size availableSize)
    {
        compact = availableSize.Width < FullWidth;
        UpdateCompact();
        return base.MeasureOverride(availableSize);
    }

    /// <summary>Width the full five-control plate needs.</summary>
    private const double FullWidth = 380;

    private bool compact;

    /// <summary>Applies the compact arrangement.</summary>
    private void UpdateCompact()
    {
        var visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        if (First.Visibility != visibility) First.Visibility = Last.Visibility = visibility;
    }

    /// <summary>Wires commands, IDs and the page text to a new model.</summary>
    /// <param name="old">Previous model.</param>
    private void Attach(RankingsPagerViewModel? old)
    {
        if (old is not null) old.PropertyChanged -= OnPagerChanged;
        if (Pager is not { } pager) return;
        pager.PropertyChanged += OnPagerChanged;
        First.Command = pager.FirstCommand;
        Previous.Command = pager.PreviousCommand;
        Next.Command = pager.NextCommand;
        Last.Command = pager.LastCommand;
        AutomationProperties.SetAutomationId(First, pager.IdPrefix + ".page-first");
        AutomationProperties.SetAutomationId(Previous, pager.IdPrefix + ".page-previous");
        AutomationProperties.SetAutomationId(Info, pager.IdPrefix + ".page-info");
        AutomationProperties.SetAutomationId(Next, pager.IdPrefix + ".page-next");
        AutomationProperties.SetAutomationId(Last, pager.IdPrefix + ".page-last");
        UpdateText();
    }

    /// <summary>Refreshes the page text.</summary>
    /// <param name="sender">Pager.</param>
    /// <param name="e">Changed property.</param>
    private void OnPagerChanged(object? sender, PropertyChangedEventArgs e) => UpdateText();

    /// <summary>Writes "page / total" and its spoken form.</summary>
    private void UpdateText()
    {
        if (Pager is not { } pager) return;
        Info.Text = pager.InfoText;
        AutomationProperties.SetName(Info, pager.InfoAnnouncement);
    }
}
#endregion
