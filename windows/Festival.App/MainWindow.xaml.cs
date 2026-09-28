using System.ComponentModel;
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
/// Shell: Mica window, WinUI TitleBar (back, pane toggle, profile avatar), NavigationView sections with one
/// frame stack per section, and the shared artwork background with its playback policy.
/// </summary>
public sealed partial class MainWindow : Window
{
    #region Fields
    private readonly FestivalSession session;
    private readonly LaunchOptions options;
    private readonly Dictionary<AppSection, Frame> frames = [];
    private readonly UISettings uiSettings = new();
    private AppSection current = AppSection.Songs;
    private bool windowVisible = true;
    private bool minimized;
    #endregion

    /// <summary>Creates the shell.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="options">Launch options (deep link, size, perf flags).</param>
    public MainWindow(FestivalSession session, LaunchOptions options)
    {
        this.session = session;
        this.options = options;
        Shell = new ShellViewModel(session);
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        Resize(options.Width ?? 1280, options.Height ?? 820);

        Instance = this;
        Nav.Loaded += (_, _) =>
        {
            if (Nav.SettingsItem is NavigationViewItem settingsItem) Configure(settingsItem);
            SelectNavItem(current);
        };
        RebuildMenu();
        Shell.Sections.CollectionChanged += (_, _) => RebuildMenu();
        session.PropertyChanged += OnSessionChanged;

        VisibilityChanged += (_, e) => { windowVisible = e.Visible; UpdateBackdropPolicy(); };
        AppWindow.Changed += OnAppWindowChanged;
        uiSettings.AdvancedEffectsEnabledChanged += (_, _) => DispatcherQueue.TryEnqueue(ApplyTransparency);
        if (ApiInformation.IsEventPresent("Windows.UI.ViewManagement.UISettings", "AnimationsEnabledChanged"))
            uiSettings.AnimationsEnabledChanged += (_, _) => DispatcherQueue.TryEnqueue(UpdateBackdropPolicy);

        RootGrid.KeyboardAccelerators.Add(Accelerator(VirtualKey.Left, VirtualKeyModifiers.Menu, () => GoBack()));
        RootGrid.KeyboardAccelerators.Add(Accelerator(VirtualKey.GoBack, VirtualKeyModifiers.None, () => GoBack()));
        RootGrid.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(RootGrid).Properties.IsXButton1Pressed && GoBack()) e.Handled = true;
        };

        ApplyTransparency();
        UpdateBackdropPolicy();
        Show(options.Tab ?? AppSection.Songs);
        if (options.Route is { } route) Navigate(route);
        _ = LoadBackdropCatalogAsync();
        Backdrop.Loaded += (_, _) => PerfLog.Mark("shell-loaded");
    }

    /// <summary>Shell view model (sections, avatar, profile search).</summary>
    public ShellViewModel Shell { get; }

    /// <summary>The current window, for pages that need it.</summary>
    public static MainWindow? Instance { get; private set; }

    #region Navigation
    /// <summary>Pushes a route onto the current section's stack.</summary>
    /// <param name="route">Destination.</param>
    public void Navigate(AppRoute route) => frames[current].Navigate(PageFor(route), route);

    /// <summary>Page type for a route; unported routes use the placeholder page.</summary>
    /// <param name="route">Route.</param>
    /// <returns>Page type.</returns>
    private static Type PageFor(AppRoute route) => route switch
    {
        AppRoute.SongDetail => typeof(SongDetailPage),
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
            frame.Navigated += (_, _) => OnFrameNavigated();
            frames[section] = frame;
            frame.Navigate(RootPage(section), section);
        }
        else if (section == current)
        {
            while (frame.CanGoBack) frame.GoBack();
        }
        current = section;
        FrameHost.Children.Clear();
        FrameHost.Children.Add(frame);
        SelectNavItem(section);
        OnFrameNavigated();
    }

    /// <summary>Root page type for a section.</summary>
    /// <param name="section">Section.</param>
    /// <returns>Page type.</returns>
    private static Type RootPage(AppSection section) => section switch
    {
        AppSection.Songs => typeof(SongsPage),
        AppSection.Settings => typeof(SettingsPage),
        _ => typeof(PlaceholderPage),
    };

    /// <summary>Goes back in the current section.</summary>
    /// <returns><see langword="true"/> when a page was popped.</returns>
    private bool GoBack()
    {
        if (!frames.TryGetValue(current, out var frame) || !frame.CanGoBack) return false;
        frame.GoBack();
        return true;
    }

    /// <summary>Updates back state and the background mode after any navigation.</summary>
    private void OnFrameNavigated()
    {
        var frame = frames.GetValueOrDefault(current);
        AppTitleBar.IsBackButtonEnabled = frame?.CanGoBack == true;
        if (frame?.Content is IBackdropPage { UsesSongCover: true } page) Backdrop.ShowSong(page.BackdropArt);
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
    private void OnPaneToggleRequested(TitleBar sender, object args) => Nav.IsPaneOpen = !Nav.IsPaneOpen;

    /// <summary>Rebuilds pane items from the visible sections (Settings is the footer item).</summary>
    private void RebuildMenu()
    {
        Nav.MenuItems.Clear();
        foreach (var section in Shell.Sections.Where(s => s != AppSection.Settings))
        {
            Nav.MenuItems.Add(Configure(new NavigationViewItem { Content = section.Label(), Icon = new FontIcon { Glyph = Glyph(section) } }, section));
        }
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
    private static string Glyph(AppSection section) => section switch
    {
        AppSection.Songs => "",
        AppSection.Suggestions => "",
        AppSection.Leaderboards => "",
        AppSection.Rivals => "",
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
    /// <summary>Focuses the search box when the profile flyout opens.</summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnProfileFlyoutOpened(object sender, object e) => ProfileSearchBox.Focus(FocusState.Programmatic);

    /// <summary>Selects a search result and closes the flyout.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked result.</param>
    private void OnProfileResultClick(object sender, ItemClickEventArgs e)
    {
        Shell.SelectProfileCommand.Execute(e.ClickedItem as PlayerSearchResult);
        ProfileFlyout.Hide();
    }
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

    /// <summary>Tracks minimize/restore.</summary>
    /// <param name="sender">App window.</param>
    /// <param name="args">Change flags.</param>
    private void OnAppWindowChanged(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (!args.DidPresenterChange && !args.DidSizeChange) return;
        minimized = sender.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized };
        UpdateBackdropPolicy();
    }

    /// <summary>Resolves and applies the background mode.</summary>
    private void UpdateBackdropPolicy()
    {
        var settings = session.Settings;
        var mode = ArtworkPlaybackPolicy.Resolve(new ArtworkPolicyInputs(
            SystemAnimationsEnabled: uiSettings.AnimationsEnabled,
            WindowVisible: windowVisible && !minimized,
            WindowOccluded: false,
            ReduceMotion: settings.ReduceMotion || options.ReduceMotion,
            DisableAnimatedArtwork: settings.DisableAnimatedArtwork,
            SaveData: settings.SaveData || options.NoArt));
        Backdrop.ApplyMode(mode);
    }

    /// <summary>Makes cards opaque when Windows transparency effects are off (Mica falls back on its own).</summary>
    private void ApplyTransparency()
    {
        var dictionaries = Application.Current.Resources.MergedDictionaries;
        foreach (var dictionary in dictionaries)
        {
            if (dictionary.ThemeDictionaries.TryGetValue("Default", out var theme) &&
                theme is ResourceDictionary defaults && defaults.TryGetValue("FSTCardSurfaceBrush", out var value) &&
                value is SolidColorBrush brush)
            {
                var color = brush.Color;
                color.A = uiSettings.AdvancedEffectsEnabled ? (byte)0xC7 : (byte)0xFF;
                brush.Color = color;
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

#region Backdrop contract
/// <summary>Pages that replace the carousel with a static song cover (Song Detail, leaderboards).</summary>
public interface IBackdropPage
{
    /// <summary>Whether this page shows a song cover.</summary>
    bool UsesSongCover { get; }

    /// <summary>Song art reference, once known.</summary>
    string? BackdropArt { get; }
}
#endregion
