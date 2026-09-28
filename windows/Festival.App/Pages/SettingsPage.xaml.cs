using Festival.App.Controls;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

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
        ViewModel = new SettingsViewModel(App.Session, typeof(App).Assembly.GetName().Version?.ToString(3) ?? "", debugBuild);
        InitializeComponent();
        QuickLinksMenu.Model = ViewModel.QuickLinks;
        _ = new QuickLinksBinder(Scroller, ViewModel.QuickLinks, () => QuickLinksBinder.ReducedMotion(App.Session.Settings.ReduceMotion));
        ViewModel.ReplayRequested += (_, page) => MainWindow.Instance?.ShowFirstRunReplay(page);
    }

    /// <summary>Page model.</summary>
    public SettingsViewModel ViewModel { get; }

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
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "Reset Settings",
            Content = "Are you sure you want to restore all settings to their default values? Your profile, song filters and navigation stay.",
            PrimaryButtonText = "Reset",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            RequestedTheme = ElementTheme.Dark,
        };
        if (await MainWindow.ShowDialogAsync(dialog) == ContentDialogResult.Primary) ViewModel.ResetAppSettingsCommand.Execute(null);
    }
}
#endregion
