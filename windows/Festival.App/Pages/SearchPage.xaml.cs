using Festival.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;
using Windows.System;

namespace Festival.App.Pages;

#region Search page
/// <summary>
/// Global search results (<c>/search</c>): its own field, All/Songs/Players/Bands scopes and Songs → Players → Bands
/// sections.
/// Pushed on the current section's stack, so Back returns to where the user was.
/// </summary>
public sealed partial class SearchPage : Page, IPageFind
{
    /// <summary>Creates the page.</summary>
    public SearchPage()
    {
        InitializeComponent();
        Loaded += (_, _) => PageField.Focus(FocusState.Programmatic);
    }

    /// <summary>Page model (set on navigation).</summary>
    public GlobalSearchViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        var route = e.Parameter as AppRoute.Search ?? new AppRoute.Search();
        ViewModel = new GlobalSearchViewModel(App.Session, route, MainWindow.Instance?.TitleBarSearch);
        ViewModel.ResultsAnnounced += OnResultsAnnounced;
        ViewModel.SectionShown += OnSectionShown;
        Bindings.Update();
        ScopeBar.SelectedItem = ScopeBar.Items[(int)ViewModel.Scope];
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.ResultsAnnounced -= OnResultsAnnounced;
        ViewModel.SectionShown -= OnSectionShown;
        ViewModel.Deactivate();
        base.OnNavigatedFrom(e);
    }

    /// <summary>Replaces the query (title-bar submit while this page is showing).</summary>
    /// <param name="route">New query and scope.</param>
    public void Show(AppRoute.Search route)
    {
        ViewModel.Query = route.Text;
        ViewModel.SubmitCommand.Execute(null);
        PageField.Focus(FocusState.Programmatic);
    }

    /// <inheritdoc />
    public bool FocusFind()
    {
        MainWindow.FocusAndSelect(PageField);
        return true;
    }

    /// <summary>
    /// Re-arms a section's row stagger when it appears: rows stay collapsed behind the one spinner until every read
    /// settles, which is usually after the stagger armed when the items arrived, so they fade as the spinner clears
    /// (web: "rows fade up with a stagger"; the fade journey in <c>tools/windows/search_journey.py</c> checks it).
    /// The All scope's section title fades with it (web: the heading takes the section's first stagger slot).
    /// </summary>
    /// <param name="sender">Model.</param>
    /// <param name="section">Section that appeared.</param>
    private void OnSectionShown(object? sender, SearchScope section)
    {
        var (heading, list) = section switch
        {
            SearchScope.Songs => (SongsHeading, (UIElement)SongsList),
            SearchScope.Players => (PlayersHeading, PlayersList),
            _ => (BandsHeading, BandsList),
        };
        if (ViewModel.ShowSectionTitles) FadeIn.Play(heading);
        FadeIn.Restagger(list);
    }

    /// <summary>Speaks the settled counts.</summary>
    /// <param name="sender">Model.</param>
    /// <param name="text">Announcement.</param>
    private void OnResultsAnnounced(object? sender, string text) => MainWindow.Announce(PageField, text);

    /// <summary>Enter / query icon runs now.</summary>
    /// <param name="sender">Field.</param>
    /// <param name="args">Unused.</param>
    private void OnQuerySubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args) =>
        ViewModel.SubmitCommand.Execute(null);

    /// <summary>Escape clears the text, then goes back.</summary>
    /// <param name="sender">Field.</param>
    /// <param name="e">Key.</param>
    private void OnFieldKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != VirtualKey.Escape) return;
        e.Handled = true;
        if (ViewModel.Query.Length > 0) ViewModel.Query = "";
        else if (Frame.CanGoBack) Frame.GoBack();
    }

    /// <summary>Maps the selector bar to the model scope.</summary>
    /// <param name="sender">Selector bar.</param>
    /// <param name="args">Unused.</param>
    private void OnScopeChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        var index = sender.Items.IndexOf(sender.SelectedItem);
        if (index >= 0) ViewModel.Scope = (SearchScope)index;
    }

    /// <summary>Opens a song.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked row.</param>
    private void OnSongClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is GlobalSongResult song) MainWindow.Instance?.OpenSearchRoute(song.Route);
    }

    /// <summary>Opens a player (the selected player → Statistics).</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked row.</param>
    private void OnPlayerClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is GlobalPlayerResult player) MainWindow.Instance?.OpenSearchRoute(player.Route);
    }

    /// <summary>Opens a band card's page through the shared result navigation (Search closes first).</summary>
    /// <param name="sender">Card.</param>
    /// <param name="route">Band route.</param>
    private void OnBandRouteRequested(object? sender, AppRoute route) => MainWindow.Instance?.OpenSearchRoute(route);

    /// <summary>Names song rows for UI Automation.</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container.</param>
    private void OnSongContainer(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.Item is not GlobalSongResult song) return;
        AutomationProperties.SetName(args.ItemContainer, song.AccessibleName);
        AutomationProperties.SetAutomationId(args.ItemContainer, "fst.global-search.result.song");
        if (args.ItemContainer.ContentTemplateRoot is UIElement root) RowSeparators.Apply(root, args.ItemIndex);
    }

    /// <summary>Names player rows for UI Automation.</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container.</param>
    private void OnPlayerContainer(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.Item is not GlobalPlayerResult player) return;
        AutomationProperties.SetName(args.ItemContainer, player.AccessibleName);
        AutomationProperties.SetAutomationId(args.ItemContainer, "fst.global-search.result.player");
        if (args.ItemContainer.ContentTemplateRoot is UIElement root) RowSeparators.Apply(root, args.ItemIndex);
    }
}
#endregion
