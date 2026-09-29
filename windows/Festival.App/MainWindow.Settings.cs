using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Pages;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Windows.UI;

namespace Festival.App;

#region Shell features: first run, notifications, dialogs, contrast
/// <summary>Settings-lane shell seams: first-run carousels, the notifications bell, serialized dialogs and contrast.</summary>
public sealed partial class MainWindow
{
    private static readonly SemaphoreSlim DialogGate = new(1, 1);
    private readonly Dictionary<Frame, Stack<AppRoute?>> routeStacks = [];
    private FirstRunCenter? firstRun;
    private bool firstRunQueued;

    /// <summary>App-wide first-run arbiter.</summary>
    public FirstRunCenter FirstRun => firstRun!;

    /// <summary>Notifications bell model.</summary>
    public NotificationsViewModel? Notifications { get; private set; }

    /// <summary>Creates first-run and notification services and the bell (called once from the constructor).</summary>
    private void InitializeSettingsFeatures()
    {
        // Debug and automation launches default to no first-run carousels; an explicit --first-run still wins.
        var mode = FirstRunModeParser.Parse(Environment.GetCommandLineArgs().Skip(1).ToArray(), App.LaunchEnvironment, App.HooksEnabled);
        firstRun = new FirstRunCenter(new FirstRunSeenStore(new FileBlobStore(FirstRunSeenStore.DefaultPath)), mode);
        Notifications = new NotificationsViewModel(session, new NotificationSeenStore(new FileBlobStore(NotificationSeenStore.DefaultPath)));
        NotificationsHost.Content = new NotificationsBell(Notifications, OpenNotification);
        _ = Notifications.RefreshAsync();
        session.PropertyChanged += OnSettingsFeatureSessionChanged;
        ApplyContrast();
    }

    #region Dialogs
    /// <summary>Shows one ContentDialog at a time (WinUI allows only one open per window).</summary>
    /// <param name="dialog">Dialog with its XamlRoot set.</param>
    /// <returns>Result.</returns>
    public static async Task<ContentDialogResult> ShowDialogAsync(ContentDialog dialog)
    {
        await DialogGate.WaitAsync();
        try
        {
            // Every modal closes on a click outside it, like Esc (operator batch 6.14; web modals).
            Controls.DialogChrome.LightDismiss(dialog);
            return await dialog.ShowAsync();
        }
        finally
        {
            DialogGate.Release();
        }
    }
    #endregion

    #region First run
    /// <summary>Settings "Show": replays every slide of a page.</summary>
    /// <param name="page">Page.</param>
    public void ShowFirstRunReplay(FirstRunPageKey page)
    {
        if (FirstRun.BeginReplay(page) is { } carousel) _ = ShowCarouselAsync(carousel);
    }

    /// <summary>Tracks each section stack's routes so the visible page's first-run key is known.</summary>
    /// <param name="frame">Section frame.</param>
    private void TrackRoutes(Frame frame)
    {
        if (routeStacks.ContainsKey(frame)) return;
        routeStacks[frame] = RootStack();
        frame.Navigated += (_, e) =>
        {
            var stack = routeStacks[frame];
            if (e.NavigationMode == NavigationMode.Back && stack.Count > 1) stack.Pop();
            else if (e.NavigationMode == NavigationMode.New) stack.Push(e.Parameter as AppRoute);
            if (frame.BackStack.Count == 0) routeStacks[frame] = RootStack();
            UpdateWindowTitle();
        };
    }

    /// <summary>A route stack holding only the section root.</summary>
    /// <returns>Stack.</returns>
    private static Stack<AppRoute?> RootStack()
    {
        var stack = new Stack<AppRoute?>();
        stack.Push(null);
        return stack;
    }

    /// <summary>Queues a first-run check after navigation settles (low priority, so the page renders first).</summary>
    private void QueueFirstRun()
    {
        if (firstRun is null || firstRunQueued) return;
        firstRunQueued = true;
        DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, () =>
        {
            firstRunQueued = false;
            EvaluateFirstRun();
        });
    }

    /// <summary>Shows unseen, gate-passing slides for the visible page (never over a placeholder or while minimized).</summary>
    private void EvaluateFirstRun()
    {
        if (!frames.TryGetValue(current, out var frame) || frame.Content is PlaceholderPage || !windowVisible || minimized) return;
        TrackRoutes(frame);
        var route = routeStacks[frame].Peek();
        firstRunEvaluated = true;
        if (FirstRunPages.For(current, route) is not { } page) return;
        if (FirstRun.TryBegin(page, session.Settings) is { } carousel) _ = ShowCarouselAsync(carousel);
    }

    /// <summary>Presents a carousel dialog.</summary>
    /// <param name="carousel">Carousel.</param>
    /// <returns>Task.</returns>
    private async Task ShowCarouselAsync(FirstRunCarouselViewModel carousel)
    {
        try
        {
            await ShowDialogAsync(FirstRunCarousel.CreateDialog(carousel, RootGrid.XamlRoot));
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            CrashLogWrite(error);
            carousel.Complete();
        }
    }
    #endregion

    #region Notifications
    /// <summary>Opens a notification destination on its owning section.</summary>
    /// <param name="destination">Destination.</param>
    private void OpenNotification(NotificationDestination destination)
    {
        switch (destination)
        {
            case NotificationDestination.Song song:
                if (current != AppSection.Songs) Show(AppSection.Songs);
                Navigate(new AppRoute.SongDetail(song.SongId, song.Instrument));
                break;
            case NotificationDestination.Rankings:
                Show(AppSection.Leaderboards);
                break;
        }
    }
    #endregion

    #region Contrast and transparency
    /// <summary>Re-checks first run and appearance when settings change.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Change.</param>
    private void OnSettingsFeatureSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(FestivalSession.Settings)) return;
        ApplyContrast();
        ApplyTransparency();
        QueueFirstRun();
    }

    /// <summary>In-app Increase Contrast: white de-emphasised text and a stronger card stroke (additive to Windows contrast themes).</summary>
    private void ApplyContrast()
    {
        var more = session.Settings.MoreContrast;
        foreach (var dictionary in Application.Current.Resources.MergedDictionaries)
        {
            if (!dictionary.ThemeDictionaries.TryGetValue("Default", out var theme) || theme is not ResourceDictionary defaults) continue;
            if (defaults.TryGetValue("FSTDeemphasisTextBrush", out var text) && text is SolidColorBrush textBrush)
                textBrush.Color = more ? Color.FromArgb(0xFF, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0xFF, 0xD7, 0xDE, 0xE8);
            if (defaults.TryGetValue("FSTCardStrokeBrush", out var stroke) && stroke is SolidColorBrush strokeBrush)
                strokeBrush.Color = more ? Color.FromArgb(0x80, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF);
        }
    }

    /// <summary>Writes a diagnostics entry.</summary>
    /// <param name="error">Error.</param>
    private static void CrashLogWrite(Exception error) => Services.CrashLog.Write(error, "First-run dialog");
    #endregion
}
#endregion
