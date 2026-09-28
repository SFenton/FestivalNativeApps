using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;
using Windows.System;

namespace Festival.App.Pages;

#region Rivals page
/// <summary>
/// Rivals hub (<c>/rivals</c>, also <c>/compete</c> on Windows): Song/Leaderboard tabs, Find Rival, Jump To and
/// independently loading section cards in a masonry grid (one column compact, two to four as the window widens).
/// </summary>
public sealed partial class RivalsPage : Page
{
    /// <summary>Width below which the header stacks (compact windows and narrow snaps).</summary>
    private const double NarrowWidth = 640;

    /// <summary>Creates the page and its (cached) model.</summary>
    public RivalsPage()
    {
        ViewModel = new RivalsHubViewModel(App.Session);
        InitializeComponent();
        SizeChanged += (_, e) => VisualStateManager.GoToState(this, e.NewSize.Width < NarrowWidth ? "Narrow" : "Wide", false);
        ViewModel.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(RivalsHubViewModel.Tab)) SyncTab();
        };
        KeyboardAccelerators.Add(Accelerator(VirtualKey.F5, VirtualKeyModifiers.None, () => ViewModel.RefreshCommand.Execute(null)));
        KeyboardAccelerators.Add(Accelerator(VirtualKey.F, VirtualKeyModifiers.Control, () => FindRivalBox.Focus(FocusState.Keyboard)));
    }

    /// <summary>Hub model.</summary>
    public RivalsHubViewModel ViewModel { get; }

    /// <inheritdoc />
    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel.Activate();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.Deactivate();
        base.OnNavigatedFrom(e);
    }

    /// <summary>Applies the SelectorBar choice.</summary>
    /// <param name="sender">Selector bar.</param>
    /// <param name="args">Unused.</param>
    private void OnTabChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        var tab = sender.SelectedItem == LeaderboardTab ? RivalsTab.Leaderboard : RivalsTab.Song;
        if (tab == ViewModel.Tab) return;
        ViewModel.Tab = tab;
        ScrollToTop();
        // Again after the new sections lay out: an in-flight Jump To scroll animation would otherwise win.
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, ScrollToTop);
    }

    /// <summary>Scrolls the sections to the top without animation.</summary>
    private void ScrollToTop() => Scroller.ChangeView(null, 0, null, disableAnimation: true);

    /// <summary>Keeps the SelectorBar in step with the model.</summary>
    private void SyncTab()
    {
        var wanted = ViewModel.Tab == RivalsTab.Leaderboard ? LeaderboardTab : SongTab;
        if (TabBar.SelectedItem != wanted) TabBar.SelectedItem = wanted;
    }

    /// <summary>Navigates to a row's or link's route.</summary>
    /// <param name="sender">Element whose <c>Tag</c> is an <see cref="AppRoute"/>.</param>
    /// <param name="e">Unused.</param>
    private void OnRouteClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: AppRoute route }) MainWindow.Instance?.Navigate(route);
    }

    /// <summary>Feeds typed text to the Find Rival search.</summary>
    /// <param name="sender">Search box.</param>
    /// <param name="args">Change reason.</param>
    private void OnFindTextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        if (args.Reason == AutoSuggestionBoxTextChangeReason.UserInput) ViewModel.FindRival.Query = sender.Text;
    }

    /// <summary>Opens the chosen (or only) result's Rival Detail.</summary>
    /// <param name="sender">Search box.</param>
    /// <param name="args">Chosen suggestion.</param>
    private void OnFindSubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
    {
        var chosen = args.ChosenSuggestion as PlayerSearchResult ?? ViewModel.FindRival.Results.FirstOrDefault();
        if (chosen is null) return;
        sender.Text = "";
        ViewModel.FindRival.Reset();
        MainWindow.Instance?.Navigate(FindRivalViewModel.RouteFor(chosen));
    }

    /// <summary>Lists visible sections in the Jump To menu.</summary>
    /// <param name="sender">Menu.</param>
    /// <param name="e">Unused.</param>
    private void OnJumpMenuOpening(object sender, object e)
    {
        JumpMenu.Items.Clear();
        for (var i = 0; i < ViewModel.Sections.Count; i++)
        {
            var index = i;
            var section = ViewModel.Sections[i];
            var item = new MenuFlyoutItem { Text = section.Title };
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(item, section.AutomationId.Replace("fst.rivals.section.", "fst.rivals.jump.", StringComparison.Ordinal));
            item.Click += (_, _) => JumpTo(index);
            JumpMenu.Items.Add(item);
        }
    }

    /// <summary>Scrolls a section card to the top and moves focus into it.</summary>
    /// <param name="index">Section index.</param>
    private void JumpTo(int index)
    {
        if (SectionsRepeater.TryGetElement(index) is not UIElement element) return;
        element.StartBringIntoView(new BringIntoViewOptions { VerticalAlignmentRatio = 0, AnimationDesired = App.Session.Settings.ReduceMotion is false });
        if (FocusManager.FindFirstFocusableElement(element) is Control control) control.Focus(FocusState.Keyboard);
    }

    /// <summary>Opens the title-bar profile picker.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnSelectPlayer(object sender, RoutedEventArgs e) => MainWindow.Instance?.OpenProfilePicker();

    /// <summary>Creates a page keyboard accelerator.</summary>
    /// <param name="key">Key.</param>
    /// <param name="modifiers">Modifiers.</param>
    /// <param name="action">Action.</param>
    /// <returns>Accelerator.</returns>
    internal static KeyboardAccelerator Accelerator(VirtualKey key, VirtualKeyModifiers modifiers, Action action)
    {
        var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
        accelerator.Invoked += (_, e) =>
        {
            action();
            e.Handled = true;
        };
        return accelerator;
    }
}
#endregion
