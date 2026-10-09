using System.ComponentModel;
using Festival.App.Pages;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.System;

namespace Festival.App;

#region Global search
/// <summary>
/// Global search in the shell (global-search spec, windows.md): a title-bar <c>AutoSuggestBox</c> at ≥ 720 epx with
/// mixed song/player/band suggestions, a magnifier button below that width, Ctrl+E / Ctrl+F, and the Search page.
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>Window width (epx) below which the box collapses to a button.</summary>
    public const double CompactSearchWidth = 720;
    /// <summary>Window width (epx) from which the box gets its full width.</summary>
    public const double WideSearchWidth = 1008;

    private DependencyObject? focusBeforeSearch;

    /// <summary>The title-bar search model (the Search page reuses its settled results).</summary>
    public GlobalSearchViewModel TitleBarSearch { get; private set; } = null!;

    /// <summary>Wires the title-bar box, the compact button, width breakpoints and accelerators.</summary>
    private void InitializeGlobalSearch()
    {
        TitleBarSearch = new GlobalSearchViewModel(session);
        TitleBarSearch.PropertyChanged += OnTitleBarSearchChanged;
        TitleBarSearch.ResultsAnnounced += (_, text) =>
        {
            if (GlobalSearchBox.FocusState != FocusState.Unfocused) Announce(GlobalSearchBox, text);
        };
        GlobalSearchBox.TextChanged += OnGlobalSearchTextChanged;
        GlobalSearchBox.SuggestionChosen += OnGlobalSuggestionChosen;
        GlobalSearchBox.QuerySubmitted += OnGlobalSearchSubmitted;
        GlobalSearchBox.PreviewKeyDown += OnGlobalSearchKeyDown;
        GlobalSearchButton.Click += (_, _) => OpenSearchPage();
        RootGrid.SizeChanged += (_, e) => ApplySearchWidth(e.NewSize.Width);
        // The window-wide accelerators belong to no visible control; their automatic key tip would float over content.
        RootGrid.KeyboardAcceleratorPlacementMode = KeyboardAcceleratorPlacementMode.Hidden;
        RootGrid.KeyboardAccelerators.Add(Accelerator(VirtualKey.E, VirtualKeyModifiers.Control, FocusGlobalSearch));
        RootGrid.KeyboardAccelerators.Add(Accelerator(VirtualKey.F, VirtualKeyModifiers.Control, FindInPage));
    }

    #region Layout
    /// <summary>Box (≥ 720 epx; wider from 1008) or magnifier button (&lt; 720 epx).</summary>
    /// <param name="width">Window content width in epx.</param>
    private void ApplySearchWidth(double width)
    {
        var compact = width < CompactSearchWidth;
        // The host is the box's passthrough rect (issue #536); collapsed with it so no empty strip stays clickable.
        GlobalSearchBoxHost.Visibility = GlobalSearchBox.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        GlobalSearchButton.Visibility = compact ? Visibility.Visible : Visibility.Collapsed;
        // Responsive box: ~36% of the window, 240 (medium) or 320 (wide) to 580 epx as in the WinUI Gallery.
        var min = width >= WideSearchWidth ? 320 : 240;
        GlobalSearchBox.MinWidth = min;
        GlobalSearchBox.Width = Math.Clamp(width * 0.36, min, 580);
    }

    /// <summary>Whether the title-bar box is the visible entry point.</summary>
    private bool UsesTitleBarBox => GlobalSearchBox.Visibility == Visibility.Visible;
    #endregion

    #region Title-bar box
    /// <summary>Feeds user typing into the model (suggestion browsing does not re-query).</summary>
    /// <param name="sender">Box.</param>
    /// <param name="args">Reason.</param>
    private void OnGlobalSearchTextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        if (args.Reason == AutoSuggestionBoxTextChangeReason.UserInput) TitleBarSearch.Query = sender.Text;
    }

    /// <summary>Shows the highlighted suggestion's title while arrowing (the box doesn't use <c>ToString</c>, the UIA name).</summary>
    /// <param name="sender">Box.</param>
    /// <param name="args">Chosen item.</param>
    private void OnGlobalSuggestionChosen(AutoSuggestBox sender, AutoSuggestBoxSuggestionChosenEventArgs args)
    {
        if (args.SelectedItem is GlobalSuggestion { IsViewAll: false } item) sender.Text = item.Title;
    }

    /// <summary>A chosen suggestion opens its destination; typed text (Enter / query icon) opens the Search page.</summary>
    /// <param name="sender">Box.</param>
    /// <param name="args">Chosen suggestion, if any.</param>
    private void OnGlobalSearchSubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
    {
        var route = args.ChosenSuggestion is GlobalSuggestion chosen
            ? chosen.Route
            : new AppRoute.Search(GlobalSearchResults.Normalize(args.QueryText));
        // Open first: the Search page reuses the settled title-bar results before the box is reset.
        GlobalSearchBox.IsSuggestionListOpen = false;
        OpenSearchRoute(route);
        ClearTitleBarText();
    }

    /// <summary>Escape: the box closes its popup itself; then clears the text; then returns focus.</summary>
    /// <param name="sender">Box.</param>
    /// <param name="e">Key.</param>
    private void OnGlobalSearchKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != VirtualKey.Escape) return;
        if (GlobalSearchBox.IsSuggestionListOpen)
        {
            GlobalSearchBox.IsSuggestionListOpen = false;
            e.Handled = true;
            return;
        }
        e.Handled = true;
        if (GlobalSearchBox.Text.Length > 0)
        {
            ClearTitleBarText();
            return;
        }
        RestoreFocus();
    }

    /// <summary>Pushes model changes into the box.</summary>
    /// <param name="sender">Model.</param>
    /// <param name="e">Property.</param>
    private void OnTitleBarSearchChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(GlobalSearchViewModel.Suggestions)) return;
        GlobalSearchBox.ItemsSource = TitleBarSearch.Suggestions;
        if (GlobalSearchBox.FocusState != FocusState.Unfocused)
            GlobalSearchBox.IsSuggestionListOpen = TitleBarSearch.Suggestions.Count > 0;
    }

    /// <summary>Resets the box text and the model (nothing is remembered).</summary>
    private void ClearTitleBarText()
    {
        GlobalSearchBox.Text = "";
        TitleBarSearch.Reset();
        GlobalSearchBox.ItemsSource = null;
    }

    /// <summary>Returns focus to where it was before Ctrl+E, or to the page.</summary>
    private void RestoreFocus()
    {
        var target = focusBeforeSearch as Control;
        focusBeforeSearch = null;
        if (target is { IsLoaded: true } && target.Focus(FocusState.Keyboard)) return;
        if (frames.GetValueOrDefault(current)?.Content is Control page) page.Focus(FocusState.Programmatic);
    }
    #endregion

    #region Commands
    /// <summary>Ctrl+E: focus the title-bar box (text selected); compact → the Search page.</summary>
    private void FocusGlobalSearch()
    {
        if (!UsesTitleBarBox)
        {
            OpenSearchPage();
            return;
        }
        var focused = FocusManager.GetFocusedElement(RootGrid.XamlRoot) as DependencyObject;
        if (focused is not null && !IsInside(focused, GlobalSearchBox)) focusBeforeSearch = focused;
        FocusAndSelect(GlobalSearchBox);
    }

    /// <summary>Ctrl+F: the page's own find (Songs filter, Find Rival, the Search field) or else global search.</summary>
    private void FindInPage()
    {
        if (frames.GetValueOrDefault(current)?.Content is IPageFind page && page.FocusFind()) return;
        FocusGlobalSearch();
    }

    /// <summary>Opens (or focuses) the Search page from the compact button.</summary>
    private void OpenSearchPage()
    {
        if (frames.GetValueOrDefault(current)?.Content is SearchPage page)
        {
            page.FocusFind();
            return;
        }
        Navigate(new AppRoute.Search());
    }

    /// <summary>
    /// Opens a search destination (every result and suggestion: songs, players, bands): the selected player →
    /// Statistics; a search on the Search page updates it. A result opened from the Search page closes it, then
    /// pushes the destination (global-search spec), so Back returns to the page Search was opened from.
    /// </summary>
    /// <param name="route">Destination.</param>
    public void OpenSearchRoute(AppRoute route)
    {
        var origin = frames.GetValueOrDefault(current);
        if (route is AppRoute.Search search && origin?.Content is SearchPage page)
        {
            page.Show(search);
            return;
        }
        var fromSearchPage = origin?.Content is SearchPage;
        if (route is AppRoute.Statistics && session.HasPlayer) Show(AppSection.Statistics);
        else Navigate(route);
        if (fromSearchPage && origin is not null) CloseSearchPage(origin);
    }

    /// <summary>Removes the Search page a result was opened from, from its section's stack.</summary>
    /// <param name="frame">Section frame that showed the Search page.</param>
    private void CloseSearchPage(Frame frame)
    {
        if (frame.Content is SearchPage)
        {
            // The result opened another section (the selected player's Statistics): pop Search off the hidden stack.
            if (frame.CanGoBack) frame.GoBack(new SuppressNavigationTransitionInfo());
            return;
        }
        var back = frame.BackStack;
        if (back.Count == 0 || back[^1].SourcePageType != typeof(SearchPage)) return;
        back.RemoveAt(back.Count - 1);
        if (routeStacks.TryGetValue(frame, out var routes)) GlobalSearchResults.CloseSearchBelowTop(routes);
        OnFrameNavigated();
    }
    #endregion

    #region Helpers
    /// <summary>Raises a Narrator notification (a live region alone does not announce).</summary>
    /// <param name="element">Element whose peer speaks.</param>
    /// <param name="text">Announcement.</param>
    public static void Announce(UIElement element, string text)
    {
        var peer = FrameworkElementAutomationPeer.FromElement(element) ?? FrameworkElementAutomationPeer.CreatePeerForElement(element);
        peer?.RaiseNotificationEvent(AutomationNotificationKind.ActionCompleted, AutomationNotificationProcessing.ImportantMostRecent,
            text, "fst.global-search.results");
    }

    /// <summary>Focuses an <c>AutoSuggestBox</c> and selects its text.</summary>
    /// <param name="box">Box.</param>
    /// <returns><see langword="true"/> when the box took focus.</returns>
    public static bool FocusAndSelect(AutoSuggestBox box)
    {
        var focused = box.Focus(FocusState.Keyboard);
        if (FindTextBox(box) is { } text) text.SelectAll();
        return focused;
    }

    /// <summary>Finds the inner text box of a control.</summary>
    /// <param name="root">Control.</param>
    /// <returns>The first descendant <see cref="TextBox"/>.</returns>
    private static TextBox? FindTextBox(DependencyObject root)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is TextBox text) return text;
            if (FindTextBox(child) is { } nested) return nested;
        }
        return null;
    }

    /// <summary>Whether an element is inside another.</summary>
    /// <param name="element">Element.</param>
    /// <param name="ancestor">Candidate ancestor.</param>
    /// <returns><see langword="true"/> when nested.</returns>
    private static bool IsInside(DependencyObject element, DependencyObject ancestor)
    {
        for (var node = element; node is not null; node = VisualTreeHelper.GetParent(node))
            if (ReferenceEquals(node, ancestor)) return true;
        return false;
    }
    #endregion
}
#endregion

#region Page find
/// <summary>Pages with a page-local find field (Ctrl+F focuses it instead of global search).</summary>
public interface IPageFind
{
    /// <summary>Focuses the page's find field.</summary>
    /// <returns><see langword="true"/> when a field took focus.</returns>
    bool FocusFind();
}
#endregion
