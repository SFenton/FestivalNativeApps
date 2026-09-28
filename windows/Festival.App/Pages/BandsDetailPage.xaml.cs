using Festival.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Festival.App.Services;

namespace Festival.App.Pages;

#region Band detail page
/// <summary>
/// <c>/bands/:bandId</c>: members, summary, statistics, rank history and best/worst songs, with Quick Links (a
/// persistent pane on wide pages, a header menu otherwise). Resolved only from the type and team key its originating row carried.
/// </summary>
public sealed partial class BandsDetailPage : Page
{
    /// <summary>Creates the page.</summary>
    public BandsDetailPage()
    {
        InitializeComponent();
        SizeChanged += (_, e) => ApplyWidth(e.NewSize.Width);
        QuickLinks.SetSections(BandDetailViewModel.QuickLinkSections);
        _ = new QuickLinksHost(ContentGrid, Scroller, QuickLinks, QuickLinksMenu, Pane);
    }

    /// <summary>Page Quick Links (web <c>BandPage</c>: members, summary, statistics, rank history, songs).</summary>
    public QuickLinksViewModel QuickLinks { get; } = new("Quick Links");

    /// <summary>Page model (set on navigation).</summary>
    public BandDetailViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = new BandDetailViewModel(App.Session, (AppRoute.Band)e.Parameter);
        ScreenReader.Attach(this, [ViewModel], () => ViewModel.IsLoading, () => ViewModel.ShowContent ? "Band details loaded" : null, "Loading band");
        Bindings.Update();
        RankBy.SelectedIndex = ViewModel.MetricIndex;
        await ViewModel.LoadAsync();
    }

    #region Quick links
    /// <summary>Compacts the title on narrow pages (the Quick Links host picks menu or pane).</summary>
    /// <param name="width">Page width in epx.</param>
    private void ApplyWidth(double width) =>
        TitleText.Style = (Style)Application.Current.Resources[width < 560 ? "SubtitleTextBlockStyle" : "FSTPageTitleStyle"];
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
