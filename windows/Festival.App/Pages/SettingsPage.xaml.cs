using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI.ViewManagement;

namespace Festival.App.Pages;

#region Settings page
/// <summary>Every web Settings section plus the native Accessibility section, with Quick Links (menu or wide pane).</summary>
public sealed partial class SettingsPage : Page
{
    /// <summary>Creates the page.</summary>
    public SettingsPage()
    {
#if DEBUG
        const bool debugBuild = true;
#else
        const bool debugBuild = false;
#endif
        ViewModel = new SettingsViewModel(App.Session, Festival.Core.Domain.AppVersionInfo.SettingsText(typeof(App).Assembly), debugBuild);
        InitializeComponent();
        QuickLinksMenu.Model = ViewModel.QuickLinks;
        _ = new QuickLinksBinder(Scroller, ViewModel.QuickLinks, () => QuickLinksBinder.ReducedMotion(App.Session.Settings.ReduceMotion));
        ViewModel.ReplayRequested += (_, page) => MainWindow.Instance?.ShowFirstRunReplay(page);
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
    }

    /// <summary>Text-size source for the Service Info state row.</summary>
    private readonly UISettings uiSettings = new();

    /// <summary>Page model.</summary>
    public SettingsViewModel ViewModel { get; }

    /// <summary>
    /// In the tree (section shown, or popped back to): start Service Info polling, slower while the window is hidden.
    /// Section switches swap frames without navigation events, so Loaded/Unloaded is the visibility signal.
    /// </summary>
    /// <param name="sender">Page.</param>
    /// <param name="e">Unused.</param>
    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        Motion.Changed -= OnMotionChanged;
        Motion.Changed += OnMotionChanged;
        ViewModel.ServiceInfo.Background = Motion.Paused;
        uiSettings.TextScaleFactorChanged -= OnTextScaleChanged;
        uiSettings.TextScaleFactorChanged += OnTextScaleChanged;
        ApplyServiceStateLayout();
        ViewModel.Activate();
    }

    /// <summary>Windows text size changed (raised off the UI thread).</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="args">Unused.</param>
    private void OnTextScaleChanged(UISettings sender, object args) => DispatcherQueue.TryEnqueue(ApplyServiceStateLayout);

    /// <summary>
    /// At 150%+ text the Service Info process state moves under "Leaderboard Service State" (row 1, column 0) so the label
    /// and description keep the full width; otherwise it sits trailing in column 1.
    /// </summary>
    private void ApplyServiceStateLayout()
    {
        var stacked = Festival.Core.Domain.ServiceInfoText.StacksStateRow(uiSettings.TextScaleFactor);
        Grid.SetRow(ServiceProcessPanel, stacked ? 1 : 0);
        Grid.SetColumn(ServiceProcessPanel, stacked ? 0 : 1);
        ServiceProcessPanel.HorizontalAlignment = stacked ? HorizontalAlignment.Left : HorizontalAlignment.Stretch;
        ServiceStateGrid.RowSpacing = stacked ? 4 : 0;
    }

    /// <summary>Out of the tree (another section, or Licenses pushed): stop polling.</summary>
    /// <param name="sender">Page.</param>
    /// <param name="e">Unused.</param>
    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        Motion.Changed -= OnMotionChanged;
        uiSettings.TextScaleFactorChanged -= OnTextScaleChanged;
        ViewModel.Deactivate();
    }

    /// <summary>Window hidden/shown: switch the Service Info cadence.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnMotionChanged(object? sender, EventArgs e) => ViewModel.ServiceInfo.Background = Motion.Paused;

    /// <summary>A drag reorder finished: the list moved its rows in place, so save their new order.</summary>
    /// <param name="sender">Song-row or path-column list.</param>
    /// <param name="args">Drag result.</param>
    private void OnReorderCompleted(ListViewBase sender, DragItemsCompletedEventArgs args)
    {
        if (args.DropResult == Windows.ApplicationModel.DataTransfer.DataPackageOperation.None) return;
        if (sender.ItemsSource is IEnumerable<ReorderItemViewModel> rows) ViewModel.CommitDrag(rows);
    }

    /// <summary>Wide page area: persistent Quick Links pane; otherwise the header menu.</summary>
    /// <param name="sender">Root grid.</param>
    /// <param name="e">New size.</param>
    private void OnRootSizeChanged(object sender, SizeChangedEventArgs e)
    {
        var wide = QuickLinks.UsesPane(e.NewSize.Width);
        Pane.Visibility = wide ? Visibility.Visible : Visibility.Collapsed;
        MenuHost.Visibility = wide ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>First Run Guides "Show".</summary>
    /// <param name="sender">Button tagged with its page.</param>
    /// <param name="e">Unused.</param>
    private void OnReplayClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: FirstRunPageKey page }) ViewModel.ReplayFirstRunCommand.Execute(page);
    }

    /// <summary>Opens Licenses on the Settings stack.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnLicensesClick(object sender, RoutedEventArgs e) => MainWindow.Instance?.Navigate(new AppRoute.Licenses());

    /// <summary>Confirms, then restores app settings only (the web's confirm dialog).</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private async void OnResetClick(object sender, RoutedEventArgs e)
    {
        var dialog = Controls.FestivalDialog.Create(
            XamlRoot,
            "Reset Settings",
            "Are you sure you want to restore all settings to their default values? Your profile, song filters and navigation stay.",
            "fst.settings.reset.dialog",
            closeText: "Cancel",
            primaryText: "Reset");
        if (await Controls.FestivalDialog.ShowAsync(dialog) == ContentDialogResult.Primary) ViewModel.ResetAppSettingsCommand.Execute(null);
    }

    /// <summary>Replays What's New.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnShowWhatsNew(object sender, RoutedEventArgs e) => MainWindow.Instance?.ShowWhatsNew();
}
#endregion
