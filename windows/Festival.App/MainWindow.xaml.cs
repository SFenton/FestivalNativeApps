using System.ComponentModel;
using System.Net.NetworkInformation;
using Festival.App.Controls;
using Festival.App.Pages;
using Festival.App.Services;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation.Metadata;
using Windows.Graphics;
using Windows.System;
using Windows.UI.ViewManagement;

namespace Festival.App;

#region Main window
/// <summary>
/// Shell: artwork-backed window, WinUI TitleBar (back, pane toggle, profile avatar), NavigationView sections with one
/// frame stack per section, and the shared artwork background with its playback policy.
/// </summary>
public sealed partial class MainWindow : Window
{
    #region Fields
    private readonly FestivalSession session;
    private readonly LaunchOptions options;
    private readonly Dictionary<AppSection, Frame> frames = [];
    private readonly Dictionary<AppSection, OnDemandSplitHost> splits = [];
    private readonly UISettings uiSettings = new();
    private AppSection current = AppSection.Songs;
    private bool windowVisible = true;
    private bool minimized;
    private bool modalOpen;
    private OcclusionTracker? occlusion;
    private bool expandedPaneCollapsed;
    #endregion

    /// <summary>Creates the shell.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="options">Launch options (deep link, size, perf flags).</param>
    public MainWindow(FestivalSession session, LaunchOptions options)
    {
        this.session = session;
        this.options = options;
        Shell = new ShellViewModel(session);
        Shell.RouteRequested += OnShellRouteRequested;
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        Resize(options.Width ?? 1280, options.Height ?? 820);

        Instance = this;
        InitializeSettingsFeatures();
        InitializeGlobalSearch();
        Shell.ProfileSearch.ResultsAnnounced += OnProfileResultsAnnounced;
        InitializeAccessibility();
        InitializeTitleBarInset();
        InitializeRoutePolicy();
        InitializeWhatsNew();
        Nav.Loaded += (_, _) =>
        {
            if (Nav.SettingsItem is NavigationViewItem settingsItem) Configure(settingsItem);
            ApplySectionShortcuts();
            SelectNavItem(current);
        };
        RebuildMenu();
        Shell.Sections.CollectionChanged += (_, _) => RebuildMenu();
        session.PropertyChanged += OnSessionChanged;
        session.FeatureStateReset += (_, files) => DropCachedSections(files.Select(f => f.Owner).OfType<AppSection>());

        VisibilityChanged += (_, e) =>
        {
            windowVisible = e.Visible;
            UpdateBackdropPolicy();
            UpdateLiveUpdates();
            // A first-run check skipped while hidden runs once the window shows again (issue #232).
            if (e.Visible) QueueFirstRun();
        };
        AppWindow.Changed += OnAppWindowChanged;
        occlusion = new OcclusionTracker(WinRT.Interop.WindowNative.GetWindowHandle(this), DispatcherQueue);
        occlusion.Changed += (_, _) => UpdateBackdropPolicy();
        Activated += (_, e) =>
        {
            occlusion?.Invalidate();
            // First-run demos rotate only while the app is in the foreground (issue #258).
            Motion.UpdateForeground(e.WindowActivationState != WindowActivationState.Deactivated);
        };
        Closed += (_, _) =>
        {
            occlusion?.Dispose();
            occlusion = null;
            NetworkChange.NetworkAvailabilityChanged -= OnNetworkAvailabilityChanged;
            App.LiveUpdates?.Dispose();
        };
        NetworkChange.NetworkAvailabilityChanged += OnNetworkAvailabilityChanged;
        uiSettings.AdvancedEffectsEnabledChanged += (_, _) => DispatcherQueue.TryEnqueue(ApplyTransparency);
        if (ApiInformation.IsEventPresent("Windows.UI.ViewManagement.UISettings", "AnimationsEnabledChanged"))
            uiSettings.AnimationsEnabledChanged += (_, _) => DispatcherQueue.TryEnqueue(UpdateBackdropPolicy);

        RootGrid.KeyboardAccelerators.Add(Accelerator(VirtualKey.Left, VirtualKeyModifiers.Menu, () => GoBack()));
        RootGrid.KeyboardAccelerators.Add(Accelerator(VirtualKey.GoBack, VirtualKeyModifiers.None, () => GoBack()));
        RootGrid.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(RootGrid).Properties.IsXButton1Pressed && GoBack()) e.Handled = true;
        };
        // A press or focus outside the page area (title bar, navigation pane) is never "from the split pane".
        RootGrid.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler((_, e) => NoteOutsideSplit(e.OriginalSource)), true);
        RootGrid.GotFocus += (_, e) => NoteOutsideSplit(e.OriginalSource);

        ApplyTransparency();
        UpdateBackdropPolicy();
        UpdateLiveUpdates();
        Show(options.Tab ?? AppSection.Songs);
        // A launch deep link shows its own page full width, never a pane beside its section root.
        if (options.Route is { } route) Navigate(route, onDemand: false);
        _ = LoadBackdropCatalogAsync();
        Backdrop.Loaded += (_, _) => PerfLog.Mark("shell-loaded");
    }

    /// <summary>Shell view model (sections, avatar, profile search).</summary>
    public ShellViewModel Shell { get; }

    /// <summary>The current window, for pages that need it.</summary>
    public static MainWindow? Instance { get; private set; }

    #region Navigation
    /// <summary>
    /// Pushes a route onto the current section's stack, or opens it beside the list page in the section's on-demand split
    /// (split-panes R7 Windows variant, issue #652).
    /// </summary>
    /// <param name="route">Destination.</param>
    public void Navigate(AppRoute route) => Navigate(route, onDemand: true);

    /// <summary>Pushes a route, optionally through the section's on-demand split.</summary>
    /// <param name="route">Destination.</param>
    /// <param name="onDemand">Whether the split may open or extend a pane; false always pushes full width.</param>
    private void Navigate(AppRoute route, bool onDemand)
    {
        // Player-only routes redirect to the Songs root without a profile, like the web's RequirePlayer guards.
        if (AppRouteParser.ForProfile(route, session.HasPlayer) is null)
        {
            ShowSongsRoot();
            return;
        }
        // Windows has no Compete section (wide split: Leaderboards + Rivals); /compete and /rivals open the Rivals root.
        if (route is AppRoute.Compete or AppRoute.Rivals && session.HasPlayer)
        {
            Show(AppSection.Rivals);
            return;
        }
        if (route is AppRoute.Shop)
        {
            Show(AppSection.Shop);
            return;
        }
        if (route is AppRoute.Statistics && session.HasPlayer)
        {
            Show(AppSection.Statistics);
            return;
        }
        var page = PageFor(route);
        var split = splits[current];
        switch (onDemand ? split.Decide(route) : SplitAction.PushFull)
        {
            case SplitAction.OpenPane:
                split.OpenPane(page, route);
                break;
            case SplitAction.PushInPane:
                split.PushInPane(page, route);
                break;
            default:
                frames[current].Navigate(page, route);
                break;
        }
    }

    /// <summary>Marks the current split's last interaction as outside it when the source is outside the page area.</summary>
    /// <param name="source">Pressed or focused element.</param>
    private void NoteOutsideSplit(object source)
    {
        if (splits.GetValueOrDefault(current) is { } split && (source is not DependencyObject element || !OnDemandSplitHost.IsInside(element, split)))
            split.NoteOutside();
    }

    /// <summary>Opens the title-bar profile picker (pages' "Select Player" actions, the context menu and Ctrl+Shift+P).</summary>
    public void OpenProfilePicker() => ProfileFlyout.ShowAt(ProfileButton);

    /// <summary>The avatar's click: the selected player's Statistics, or the picker when anonymous (issue #290).</summary>
    /// <param name="sender">Profile button.</param>
    /// <param name="e">Unused.</param>
    private void OnProfileButtonClick(object sender, RoutedEventArgs e)
    {
        if (Shell.ProfileButtonAction == ProfileButtonAction.ShowStatistics) Show(AppSection.Statistics);
        else OpenProfilePicker();
    }

    /// <summary>Right-click, Shift+F10 or the Menu key on the avatar opens the picker anchored to it.</summary>
    /// <param name="sender">Profile button.</param>
    /// <param name="e">Request.</param>
    private void OnProfileButtonContextRequested(UIElement sender, ContextRequestedEventArgs e)
    {
        e.Handled = true;
        OpenProfilePicker();
    }

    /// <summary>Page type for a route; unported routes use the placeholder page.</summary>
    /// <param name="route">Route.</param>
    /// <returns>Page type.</returns>
    private static Type PageFor(AppRoute route) => route switch
    {
        AppRoute.SongDetail => typeof(SongDetailPage),
        AppRoute.Bands => typeof(BandsPage),
        AppRoute.PlayerBands => typeof(BandsPlayerBandsPage),
        AppRoute.Band => typeof(BandsDetailPage),
        AppRoute.SongBandLeaderboard => typeof(BandsSongLeaderboardPage),
        AppRoute.Player => typeof(PlayerProfilePage),
        AppRoute.PlayerHistory => typeof(PlayerHistoryPage),
        AppRoute.SongLeaderboard => typeof(LeaderboardsSongPage),
        AppRoute.Leaderboards => typeof(LeaderboardsPage),
        AppRoute.FullRankings => typeof(LeaderboardsFullRankingsPage),
        AppRoute.BandRankings => typeof(LeaderboardsBandRankingsPage),
        AppRoute.Licenses => typeof(LicensesPage),
        AppRoute.Rivals or AppRoute.Compete => typeof(RivalsPage),
        AppRoute.AllRivals => typeof(AllRivalsPage),
        AppRoute.RivalDetail => typeof(RivalDetailPage),
        AppRoute.Rivalry => typeof(RivalryPage),
        AppRoute.Suggestions => typeof(SuggestionsPage),
        AppRoute.Statistics => typeof(StatisticsPage),
        AppRoute.Search => typeof(SearchPage),
        _ => typeof(PlaceholderPage),
    };

    /// <summary>Shows a section, creating its frame on first use; re-invoking the current section pops to root.</summary>
    /// <param name="section">Section.</param>
    private void Show(AppSection section)
    {
        if (section.RequiresPlayer() && !session.HasPlayer) section = AppSection.Songs;
        if (!frames.TryGetValue(section, out var frame))
        {
            frame = new Frame { CacheSize = 4 };
            // The split host follows the section's navigations before the shell does (Back and first run read its pane).
            var host = new OnDemandSplitHost(frame);
            host.Changed += (_, _) => OnFrameNavigated();
            frame.Navigated += (_, _) => OnFrameNavigated();
            CachedPageScroll.Attach(frame);
            frames[section] = frame;
            splits[section] = host;
            frame.Navigate(RootPage(section), section);
        }
        else if (section == current)
        {
            while (frame.CanGoBack) frame.GoBack();
            splits[section].CloseAll();
        }
        current = section;
        FrameHost.Children.Clear();
        FrameHost.Children.Add(splits[section]);
        SelectNavItem(section);
        OnFrameNavigated();
    }

    /// <summary>Shows the Songs list itself (the anonymous redirect target), popping any Songs stack.</summary>
    private void ShowSongsRoot()
    {
        Show(AppSection.Songs);
        var frame = frames[AppSection.Songs];
        while (frame.CanGoBack) frame.GoBack();
        splits[AppSection.Songs].CloseAll();
    }

    /// <summary>Drops cached section stacks whose pages hold reset state, so they reload from defaults on next visit.</summary>
    /// <param name="sections">Owning sections (the visible one is kept: Reset runs from Settings).</param>
    private void DropCachedSections(IEnumerable<AppSection> sections)
    {
        foreach (var section in sections.Distinct())
        {
            if (section == current || !frames.Remove(section, out var frame)) continue;
            splits.Remove(section);
            routeStacks.Remove(frame);
        }
    }

    /// <summary>Root page type for a section.</summary>
    /// <param name="section">Section.</param>
    /// <returns>Page type.</returns>
    private static Type RootPage(AppSection section) => section switch
    {
        AppSection.Songs => typeof(SongsPage),
        AppSection.Settings => typeof(SettingsPage),
        AppSection.Statistics => typeof(StatisticsPage),
        AppSection.Leaderboards => typeof(LeaderboardsPage),
        AppSection.Rivals => typeof(RivalsPage),
        AppSection.Shop => typeof(ShopPage),
        AppSection.Suggestions => typeof(SuggestionsPage),
        _ => typeof(PlaceholderPage),
    };

    /// <summary>Goes back in the current section: an open split pane's stack, then the pane, then the section's stack.</summary>
    /// <returns><see langword="true"/> when a page was popped or a pane closed.</returns>
    private bool GoBack()
    {
        if (!frames.TryGetValue(current, out var frame)) return false;
        // A page-level overlay (the Songs jump index) closes before the stack pops (operator batch 6.1).
        if (frame.Content is IPageBack page && page.TryGoBack()) return true;
        // Back closes the trailing pane first (back-keeps-place R6, issue #652).
        if (splits.GetValueOrDefault(current)?.TryGoBack() == true) return true;
        if (!frame.CanGoBack) return false;
        frame.GoBack();
        return true;
    }

    /// <summary>Updates back state and the background mode after any navigation.</summary>
    private void OnFrameNavigated()
    {
        var frame = frames.GetValueOrDefault(current);
        var split = splits.GetValueOrDefault(current);
        // Back shows only when there is somewhere to go (like Windows 11 Settings), so the chrome never shows a gray
        // disabled arrow (operator batch 6.6: Back, the pane toggle and the title are white). An open pane closes on Back.
        var canGoBack = frame?.CanGoBack == true || split?.VisiblePane is not null;
        AppTitleBar.IsBackButtonEnabled = canGoBack;
        AppTitleBar.IsBackButtonVisible = canGoBack;
        if (frame is not null) TrackRoutes(frame);
        UpdateWindowTitle();
        QueueFirstRun();
        var pages = split?.Pages ?? Enumerable.Empty<object>();
        if (pages.OfType<IBackdropPage>().FirstOrDefault(p => p.UsesSongCover) is { } page) Backdrop.ShowSong(page.BackdropArt);
        else Backdrop.ShowCarousel();
    }

    /// <summary>Re-applies the backdrop when a page's art becomes known.</summary>
    public void RefreshBackdrop() => OnFrameNavigated();

    /// <summary>Handles pane item invocation.</summary>
    /// <param name="sender">Navigation view.</param>
    /// <param name="args">Invoked item.</param>
    private void OnNavItemInvoked(NavigationView sender, NavigationViewItemInvokedEventArgs args)
    {
        if (args.InvokedItemContainer?.Tag is AppSection section) Show(section);
    }

    /// <summary>Title bar back button.</summary>
    /// <param name="sender">Title bar.</param>
    /// <param name="args">Unused.</param>
    private void OnBackRequested(TitleBar sender, object args) => GoBack();

    /// <summary>Title bar pane toggle.</summary>
    /// <param name="sender">Title bar.</param>
    /// <param name="args">Unused.</param>
    private void OnPaneToggleRequested(TitleBar sender, object args)
    {
        Nav.IsPaneOpen = !Nav.IsPaneOpen;
        if (Nav.DisplayMode == NavigationViewDisplayMode.Expanded) expandedPaneCollapsed = !Nav.IsPaneOpen;
    }

    /// <summary>
    /// Re-applies the user's expanded-pane choice when a resize returns to Expanded: opening and closing the overlay
    /// pane in a compact window must not leave a wide window with only the icon rail.
    /// </summary>
    /// <param name="sender">Navigation view.</param>
    /// <param name="args">New mode.</param>
    private void OnNavDisplayModeChanged(NavigationView sender, NavigationViewDisplayModeChangedEventArgs args)
    {
        if (args.DisplayMode == NavigationViewDisplayMode.Expanded) sender.IsPaneOpen = !expandedPaneCollapsed;
    }

    /// <summary>Rebuilds pane items from the visible sections (Settings is the footer item).</summary>
    private void RebuildMenu()
    {
        Nav.MenuItems.Clear();
        foreach (var section in Shell.Sections.Where(s => s != AppSection.Settings))
        {
            Nav.MenuItems.Add(Configure(new NavigationViewItem { Content = section.Label(), Icon = new FontIcon { Glyph = Glyph(section) } }, section));
        }
        ApplySectionShortcuts();
        if (!Shell.Sections.Contains(current)) Show(AppSection.Songs);
        else SelectNavItem(current);
    }

    /// <summary>Tags a pane item with its section and automation ID.</summary>
    /// <param name="item">Item.</param>
    /// <param name="section">Section.</param>
    /// <returns>The item.</returns>
    private static NavigationViewItem Configure(NavigationViewItem item, AppSection section = AppSection.Settings)
    {
        item.Tag = section;
        AutomationProperties.SetAutomationId(item, section.AutomationId());
        return item;
    }

    /// <summary>Selects the pane item for a section.</summary>
    /// <param name="section">Section.</param>
    private void SelectNavItem(AppSection section)
    {
        Nav.SelectedItem = section == AppSection.Settings
            ? Nav.SettingsItem
            : Nav.MenuItems.OfType<NavigationViewItem>().FirstOrDefault(i => i.Tag is AppSection s && s == section);
    }

    /// <summary>Segoe Fluent Icons glyph per section.</summary>
    /// <param name="section">Section.</param>
    /// <returns>Glyph.</returns>
    internal static string Glyph(AppSection section) => section switch
    {
        AppSection.Songs => "",
        AppSection.Suggestions => "",
        AppSection.Leaderboards => "",
        AppSection.Rivals => "",
        AppSection.Shop => "",
        AppSection.Statistics => "",
        _ => "",
    };

    /// <summary>Creates a keyboard accelerator.</summary>
    /// <param name="key">Key.</param>
    /// <param name="modifiers">Modifiers.</param>
    /// <param name="action">Action.</param>
    /// <returns>Accelerator.</returns>
    private static KeyboardAccelerator Accelerator(VirtualKey key, VirtualKeyModifiers modifiers, Action action)
    {
        var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
        accelerator.Invoked += (_, e) => { action(); e.Handled = true; };
        return accelerator;
    }
    #endregion

    #region Profile
    /// <summary>
    /// Focuses the search box when the profile flyout opens, shows the model's scope (opening a result resets it to All)
    /// and resumes a search stopped when it closed.
    /// </summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnProfileFlyoutOpened(object sender, object e)
    {
        var index = ProfileScopeIndex(Shell.ProfileScope);
        if (ProfileScope.Items.IndexOf(ProfileScope.SelectedItem) != index) ProfileScope.SelectedItem = ProfileScope.Items[index];
        ProfileSearchBox.Focus(FocusState.Programmatic);
        if (!Shell.ProfileSearch.IsSettled) _ = Shell.ProfileSearch.RetryCommand.ExecuteAsync(null);
    }

    /// <summary>
    /// Escape in Find Player closes the flyout (focus returns to the profile button) unless the box's own suggestion
    /// list is open, which Escape closes first. The AutoSuggestBox otherwise swallows the key inside the flyout.
    /// </summary>
    /// <param name="sender">Search box.</param>
    /// <param name="e">Key.</param>
    private void OnProfileSearchKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != Windows.System.VirtualKey.Escape || ProfileSearchBox.IsSuggestionListOpen) return;
        e.Handled = true;
        ProfileFlyout.Hide();
    }

    /// <summary>Stops the flyout's pending search (no automatic retry keeps running behind a closed flyout).</summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnProfileFlyoutClosed(object sender, object e) => Shell.ProfileSearch.Deactivate();

    /// <summary>
    /// Speaks a settled profile search ("3 players", "No players found." or the failure) while the flyout is open:
    /// the hint's live region alone does not make Narrator announce.
    /// </summary>
    /// <param name="sender">Search model.</param>
    /// <param name="text">Announcement.</param>
    private void OnProfileResultsAnnounced(object? sender, string text)
    {
        if (ProfileFlyout.IsOpen) Announce(ProfileSearchBox, text);
    }

    /// <summary>Names result rows for UI Automation (the item is a record, so the container would read its type).</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container.</param>
    private void OnProfileResultContainer(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.Item is not GlobalPlayerResult player) return;
        AutomationProperties.SetName(args.ItemContainer, player.AccessibleName);
        AutomationProperties.SetAutomationId(args.ItemContainer, "fst.profile.result." + player.AccountId);
    }

    /// <summary>Opens a search result's player page (viewing, not selecting) and closes the flyout.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked result.</param>
    private void OnProfileResultClick(object sender, ItemClickEventArgs e)
    {
        ProfileFlyout.Hide();
        Shell.ViewProfileCommand.Execute(e.ClickedItem as GlobalPlayerResult);
    }

    /// <summary>Opens a band result's page (viewing; Windows can't select a band as the profile) and closes the flyout.</summary>
    /// <param name="sender">Band card.</param>
    /// <param name="route">Band route.</param>
    private void OnProfileBandRouteRequested(object? sender, AppRoute route)
    {
        ProfileFlyout.Hide();
        Shell.ViewBand(route);
    }

    /// <summary>Enter (or the search glyph) opens the first result shown (players before bands).</summary>
    /// <param name="sender">Search box.</param>
    /// <param name="e">Unused.</param>
    private void OnProfileSearchSubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs e)
    {
        if (!Shell.HasAnyProfileResult) return;
        ProfileFlyout.Hide();
        Shell.OpenFirstResult();
    }

    /// <summary>Opens the selected player's page.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnViewSelectedProfile(object sender, RoutedEventArgs e)
    {
        ProfileFlyout.Hide();
        Shell.ViewSelectedProfileCommand.Execute(null);
    }

    /// <summary>Confirms and deselects (the flyout closes first so the dialog is not stacked on it).</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private async void OnDeselectProfile(object sender, RoutedEventArgs e)
    {
        ProfileFlyout.Hide();
        if (await PlayerProfileView.ConfirmDeselectAsync(RootGrid.XamlRoot)) Shell.DeselectProfileCommand.Execute(null);
    }

    /// <summary>Switches the All/Players/Bands scope.</summary>
    /// <param name="sender">Selector bar.</param>
    /// <param name="args">Unused.</param>
    private void OnProfileScopeChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        var index = sender.Items.IndexOf(sender.SelectedItem);
        if (index >= 0) Shell.ProfileScope = ProfileScopes[index];
    }

    /// <summary>The profile scope bar's items in order.</summary>
    private static readonly SearchScope[] ProfileScopes = [SearchScope.All, SearchScope.Players, SearchScope.Bands];

    /// <summary>The scope bar index of a profile scope.</summary>
    /// <param name="scope">Scope.</param>
    /// <returns>Item index (All for anything else).</returns>
    private static int ProfileScopeIndex(SearchScope scope) => Math.Max(0, Array.IndexOf(ProfileScopes, scope));

    /// <summary>Pushes a flyout route onto the current section.</summary>
    /// <param name="sender">Shell model.</param>
    /// <param name="route">Route.</param>
    private void OnShellRouteRequested(object? sender, AppRoute route) => Navigate(route);
    #endregion

    #region Background policy
    /// <summary>Loads the catalogue for the carousel independently of the Songs page.</summary>
    /// <returns>Load task.</returns>
    private async Task LoadBackdropCatalogAsync()
    {
        try
        {
            await session.LoadCatalogAsync();
        }
        catch (FestivalApiException)
        {
            // The Songs page shows the failure; the brand surface stays.
        }
    }

    /// <summary>Feeds catalogue and settings changes into the background.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(FestivalSession.Catalog) && session.Catalog is { } catalog)
        {
            ArtworkImages.Clear();
            Backdrop.SetCatalog(catalog.Songs.Select(s => s.AlbumArt));
        }
        if (e.PropertyName == nameof(FestivalSession.Settings)) UpdateBackdropPolicy();
    }

    /// <summary>Tracks minimize/restore; own moves, resizes and Z-order changes re-check occlusion.</summary>
    /// <param name="sender">App window.</param>
    /// <param name="args">Change flags.</param>
    private void OnAppWindowChanged(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (args.DidPositionChange || args.DidSizeChange || args.DidZOrderChange || args.DidVisibilityChange) occlusion?.Invalidate();
        if (!args.DidPresenterChange && !args.DidSizeChange) return;
        var wasMinimized = minimized;
        minimized = sender.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized };
        UpdateBackdropPolicy();
        UpdateLiveUpdates();
        // The visible page's first-run check was skipped while minimized; run it on restore (issue #232).
        if (wasMinimized && !minimized) QueueFirstRun();
    }

    /// <summary>
    /// Holds the live publication socket while the window is shown and not minimized, like the web socket's
    /// visible-document lifetime (issue #616). Showing the window again starts a fresh round, which re-reads the publication.
    /// </summary>
    private void UpdateLiveUpdates() => App.LiveUpdates?.SetActive(windowVisible && !minimized);

    /// <summary>The network came back: reconnect now instead of waiting out the backoff (web <c>online</c> recovery).</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Availability.</param>
    private void OnNetworkAvailabilityChanged(object? sender, NetworkAvailabilityEventArgs e)
    {
        if (e.IsAvailable) DispatcherQueue.TryEnqueue(() => App.LiveUpdates?.Restart());
    }

    /// <summary>Resolves and applies the background mode.</summary>
    private void UpdateBackdropPolicy()
    {
        var settings = session.Settings;
        var mode = ArtworkPlaybackPolicy.Resolve(new ArtworkPolicyInputs(
            SystemAnimationsEnabled: uiSettings.AnimationsEnabled,
            WindowVisible: windowVisible && !minimized,
            WindowOccluded: occlusion?.IsHidden == true,
            ReduceMotion: settings.ReduceMotion || options.ReduceMotion,
            DisableAnimatedArtwork: settings.DisableAnimatedArtwork,
            SaveData: settings.SaveData || options.NoArt,
            HighContrast: accessibilitySettings.HighContrast,
            ModalOpen: modalOpen));
        Backdrop.ApplyMode(mode);
        Motion.Update(hidden: !windowVisible || minimized || occlusion?.IsHidden == true);
    }

    /// <summary>App acrylic surfaces that switch to their solid fallback with <see cref="ApplyTransparency"/>.</summary>
    private static readonly string[] AcrylicSurfaceKeys = ["FSTOverlayPaneBrush", "FSTFlyoutSurfaceBrush"];

    /// <summary>
    /// Makes cards opaque and the overlay pane's and flyout surface's acrylic use their solid fallbacks when Windows
    /// transparency effects are off or the in-app Less Transparency or Increase Contrast setting is on
    /// (<see cref="CardSurfaceOpacity"/>, surface-materials R4).
    /// </summary>
    private void ApplyTransparency()
    {
        var settings = session.Settings;
        var transparent = CardSurfaceOpacity.IsTranslucent(uiSettings.AdvancedEffectsEnabled, settings.LessTransparency, settings.MoreContrast);
        foreach (var dictionary in Application.Current.Resources.MergedDictionaries)
        {
            if (!dictionary.ThemeDictionaries.TryGetValue("Default", out var theme) || theme is not ResourceDictionary defaults) continue;
            if (defaults.TryGetValue("FSTCardSurfaceBrush", out var value) && value is SolidColorBrush brush)
            {
                var color = brush.Color;
                color.A = transparent ? CardSurfaceOpacity.TranslucentAlpha : CardSurfaceOpacity.OpaqueAlpha;
                brush.Color = color;
            }
            foreach (var key in AcrylicSurfaceKeys)
            {
                if (defaults.TryGetValue(key, out var surface) && surface is AcrylicBrush acrylic)
                    acrylic.AlwaysUseFallback = !transparent;
            }
        }
    }
    #endregion

    /// <summary>Sizes the window in DIPs.</summary>
    /// <param name="width">Width.</param>
    /// <param name="height">Height.</param>
    private void Resize(int width, int height)
    {
        var scale = (double)Win32.GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96;
        AppWindow.Resize(new SizeInt32((int)(width * scale), (int)(height * scale)));
    }
}
#endregion

#region Page contracts
/// <summary>A page with an overlay that Back (title-bar Back, Alt+Left, the Back key, XButton1) closes first.</summary>
public interface IPageBack
{
    /// <summary>Closes a page-level overlay instead of navigating back.</summary>
    /// <returns><see langword="true"/> when Back was consumed.</returns>
    bool TryGoBack();
}

/// <summary>Pages that replace the carousel with a static song cover (Song Detail, leaderboards).</summary>
public interface IBackdropPage
{
    /// <summary>Whether this page shows a song cover.</summary>
    bool UsesSongCover { get; }

    /// <summary>Song art reference, once known.</summary>
    string? BackdropArt { get; }
}
#endregion
