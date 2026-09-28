using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Band detail page
/// <summary>
/// <c>/bands/:bandId</c>: members, summary, statistics, rank history and best/worst songs, with quick links (a rail
/// on wide windows, a pill bar otherwise). Resolved only from the type and team key its originating row carried.
/// </summary>
public sealed partial class BandsDetailPage : Page
{
    /// <summary>Creates the page.</summary>
    public BandsDetailPage() => InitializeComponent();

    /// <summary>Page model (set on navigation).</summary>
    public BandDetailViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = new BandDetailViewModel(App.Session, (AppRoute.Band)e.Parameter);
        Bindings.Update();
        RankBy.SelectedIndex = ViewModel.MetricIndex;
        BuildQuickLinks();
        await ViewModel.LoadAsync();
    }

    #region Quick links
    /// <summary>Adds one quick link per section to both the pill bar and the rail.</summary>
    private void BuildQuickLinks()
    {
        (string Id, string Label, string Glyph, FrameworkElement Target)[] links =
        [
            ("members", "Members", "", MembersSection),
            ("summary", "Summary", "", SummarySection),
            ("statistics", "Statistics", "", StatisticsSection),
            ("rank-history", "Rank History", "", HistorySection),
            ("songs", "Songs", "", SongsSection),
        ];
        PillHost.Children.Clear();
        RailHost.Children.Clear();
        foreach (var (id, label, glyph, target) in links)
        {
            PillHost.Children.Add(Link(id, label, glyph, target, "fst.band.quick-link.", pill: true));
            RailHost.Children.Add(Link(id, label, glyph, target, "fst.band.rail-link.", pill: false));
        }
    }

    /// <summary>Creates one quick-link button that scrolls its section into view.</summary>
    /// <param name="id">Section ID.</param>
    /// <param name="label">Label.</param>
    /// <param name="glyph">Segoe Fluent Icons glyph.</param>
    /// <param name="target">Section element.</param>
    /// <param name="idPrefix">Automation ID prefix.</param>
    /// <param name="pill">Pill (compact) or rail row style.</param>
    /// <returns>The button.</returns>
    private static Button Link(string id, string label, string glyph, FrameworkElement target, string idPrefix, bool pill)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        content.Children.Add(new FontIcon { Glyph = glyph, FontSize = 14 });
        content.Children.Add(new TextBlock { Text = label });
        var button = new Button
        {
            Content = content,
            CornerRadius = new CornerRadius(pill ? 16 : 6),
            Padding = pill ? new Thickness(12, 4, 12, 4) : new Thickness(12, 6, 12, 6),
            HorizontalAlignment = pill ? HorizontalAlignment.Left : HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
        };
        if (!pill)
        {
            button.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
            button.BorderThickness = new Thickness(0);
        }
        AutomationProperties.SetName(button, label);
        AutomationProperties.SetAutomationId(button, idPrefix + id);
        button.Click += (_, _) => target.StartBringIntoView(new BringIntoViewOptions
        {
            VerticalAlignmentRatio = 0,
            VerticalOffset = -12,
            AnimationDesired = true,
        });
        return button;
    }
    #endregion

    #region Navigation
    /// <summary>Applies the Rank By choice (re-projects cards and history; no new request).</summary>
    /// <param name="sender">Combo box.</param>
    /// <param name="e">Unused.</param>
    private void OnRankByChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ViewModel is not null && RankBy.SelectedIndex >= 0) ViewModel.MetricIndex = RankBy.SelectedIndex;
    }

    /// <summary>Opens a member's player profile.</summary>
    /// <param name="sender">Member card.</param>
    /// <param name="e">Unused.</param>
    private void OnMemberClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: BandMemberRow { Route: { } route } }) MainWindow.Instance?.Navigate(route);
    }

    /// <summary>Opens a linked statistic (Band Rankings or the best song).</summary>
    /// <param name="sender">Stat card.</param>
    /// <param name="e">Unused.</param>
    private void OnStatClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: BandStatCard { Route: { } route } }) MainWindow.Instance?.Navigate(route);
    }

    /// <summary>Opens Song Detail for a best/worst row.</summary>
    /// <param name="sender">Song row.</param>
    /// <param name="e">Unused.</param>
    private void OnSongClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: BandSongRow { Route: { } route } }) MainWindow.Instance?.Navigate(route);
    }
    #endregion
}
#endregion

#region Template selectors
/// <summary>Chooses the link or plain template for a statistic card.</summary>
public sealed partial class BandStatTemplateSelector : DataTemplateSelector
{
    /// <summary>Template for navigable cards.</summary>
    public DataTemplate? Link { get; set; }

    /// <summary>Template for plain cards.</summary>
    public DataTemplate? Plain { get; set; }

    /// <inheritdoc />
    protected override DataTemplate? SelectTemplateCore(object item) => item is BandStatCard { IsLink: true } ? Link : Plain;

    /// <inheritdoc />
    protected override DataTemplate? SelectTemplateCore(object item, DependencyObject container) => SelectTemplateCore(item);
}

/// <summary>Chooses the link or plain template for a best/worst song row.</summary>
public sealed partial class BandSongTemplateSelector : DataTemplateSelector
{
    /// <summary>Template for catalogue songs.</summary>
    public DataTemplate? Link { get; set; }

    /// <summary>Template for unknown songs.</summary>
    public DataTemplate? Plain { get; set; }

    /// <inheritdoc />
    protected override DataTemplate? SelectTemplateCore(object item) => item is BandSongRow { IsLink: true } ? Link : Plain;

    /// <inheritdoc />
    protected override DataTemplate? SelectTemplateCore(object item, DependencyObject container) => SelectTemplateCore(item);
}
#endregion
