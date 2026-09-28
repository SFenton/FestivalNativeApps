using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Player profile view
/// <summary>
/// Player profile body shared by the player page and the Statistics section. Switch and Deselect are confirmed with a
/// <see cref="ContentDialog"/> (Fluent: confirm consequential, app-wide changes); neither navigates away.
/// </summary>
public sealed partial class PlayerProfileView : UserControl
{
    /// <summary>Card width at which charts move beside the stats.</summary>
    private const double SideBySideWidth = 780;

    /// <summary>Card width below which charts move back under the stats (hysteresis against scrollbar-width oscillation).</summary>
    private const double StackedWidth = 740;

    private readonly QuickLinksViewModel quickLinks = new("Quick Links");

    /// <summary>Creates the view with its Quick Links (the page model is replaced per navigation; the links stay).</summary>
    public PlayerProfileView()
    {
        InitializeComponent();
        _ = new QuickLinksHost(Root, Scroller, quickLinks, QuickLinksMenu, Pane);
    }

    /// <summary>Page model; set before <see cref="Bind"/>.</summary>
    public PlayerProfileViewModel ViewModel { get; private set; } = null!;

    /// <summary>Exposes the view as a UIA group so its page-root AutomationId (<c>fst.player</c>/<c>fst.statistics</c>) is findable.</summary>
    /// <returns>Group peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new GroupPeer(this);

    /// <summary>Attaches a model and refreshes bindings.</summary>
    /// <param name="model">Page model.</param>
    public void Bind(PlayerProfileViewModel model)
    {
        if (ViewModel is not null) ViewModel.PropertyChanged -= OnModelChanged;
        ViewModel = model;
        model.PropertyChanged += OnModelChanged;
        quickLinks.SetSections(model.QuickLinkSections);
        Bindings.Update();
    }

    /// <summary>Mirrors the model's Quick Links sections.</summary>
    /// <param name="sender">Model.</param>
    /// <param name="e">Change.</param>
    private void OnModelChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(PlayerProfileViewModel.QuickLinkSections) && sender is PlayerProfileViewModel model)
            quickLinks.SetSections(model.QuickLinkSections);
    }

    /// <summary>UIA group peer for the view root.</summary>
    /// <param name="owner">View.</param>
    private sealed partial class GroupPeer(FrameworkElement owner) : FrameworkElementAutomationPeer(owner)
    {
        /// <inheritdoc />
        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Group;
    }

    #region x:Bind helpers
    /// <summary>Negation for visibility bindings.</summary>
    /// <param name="value">Value.</param>
    /// <returns>Visibility.</returns>
    public static Visibility Not(bool value) => value ? Visibility.Collapsed : Visibility.Visible;

    /// <summary>Instrument card ID.</summary>
    /// <param name="key">Service instrument ID.</param>
    /// <returns><c>fst.player.instrument.&lt;key&gt;</c>.</returns>
    public static string InstrumentId(string key) => "fst.player.instrument." + key;

    /// <summary>Empty-instrument footnote ID.</summary>
    /// <param name="key">Service instrument ID.</param>
    /// <returns>Automation ID.</returns>
    public static string EmptyId(string key) => "fst.player.instrument-empty." + key;

    /// <summary>Rank-history chart ID.</summary>
    /// <param name="key">Service instrument ID.</param>
    /// <returns>Automation ID.</returns>
    public static string RankHistoryId(string key) => "fst.player.rank-history." + key;

    /// <summary>Percentile card ID.</summary>
    /// <param name="key">Service instrument ID.</param>
    /// <returns>Automation ID.</returns>
    public static string PercentilesId(string key) => "fst.player.percentiles." + key;

    /// <summary>Spoken name for a rank spinner.</summary>
    /// <param name="label">Instrument name.</param>
    /// <returns>Name.</returns>
    public static string LoadingRankName(string label) => $"Loading {label} global rank";
    #endregion

    #region Events
    /// <summary>Selects directly, or confirms a switch away from another selected player.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private async void OnSelectClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel.SelectNeedsConfirmation &&
            !await ConfirmAsync("Switch selected profile?", ViewModel.SwitchMessage, "Switch Profile"))
            return;
        ViewModel.SelectCommand.Execute(null);
    }

    /// <summary>Confirms and deselects.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private async void OnDeselectClick(object sender, RoutedEventArgs e)
    {
        if (await ConfirmDeselectAsync(XamlRoot)) ViewModel.DeselectCommand.Execute(null);
    }

    /// <summary>Opens the player's bands.</summary>
    /// <param name="sender">Link.</param>
    /// <param name="e">Unused.</param>
    private void OnBandsClick(object sender, RoutedEventArgs e) => MainWindow.Instance?.Navigate(ViewModel.BandsRoute);

    /// <summary>Starts a section's rank and history reads when it is realized.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Prepared element.</param>
    private void OnInstrumentPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (sender.ItemsSourceView?.GetAt(args.Index) is PlayerInstrumentViewModel section) _ = section.EnsureLoadedAsync();
    }

    /// <summary>Places charts beside the stats on wide cards and below them on narrow ones.</summary>
    /// <param name="sender">Card grid.</param>
    /// <param name="e">Size.</param>
    private void OnInstrumentCardSizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (sender is not Grid grid || grid.Children.Count < 2 || grid.Children[1] is not FrameworkElement charts) return;
        var isWide = grid.ColumnDefinitions[1].Width.IsStar;
        var wide = isWide ? e.NewSize.Width >= StackedWidth : e.NewSize.Width >= SideBySideWidth;
        if (wide == isWide) return;
        grid.ColumnDefinitions[1].Width = wide ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
        Grid.SetRow(charts, wide ? 0 : 1);
        Grid.SetColumn(charts, wide ? 1 : 0);
    }
    #endregion

    #region Dialogs
    /// <summary>Shows the shared Deselect confirmation.</summary>
    /// <param name="root">Host root.</param>
    /// <returns><see langword="true"/> when confirmed.</returns>
    public static Task<bool> ConfirmDeselectAsync(XamlRoot root) => ConfirmAsync(root, "Deselect profile?",
        "Scores and profile-only content will be hidden; app Settings stay saved.", "Deselect Profile");

    /// <summary>Shows a confirmation dialog.</summary>
    /// <param name="title">Title.</param>
    /// <param name="message">Body.</param>
    /// <param name="action">Primary button.</param>
    /// <returns><see langword="true"/> when confirmed.</returns>
    private Task<bool> ConfirmAsync(string title, string message, string action) => ConfirmAsync(XamlRoot, title, message, action);

    /// <summary>Shows a confirmation dialog with Cancel as the default button.</summary>
    /// <param name="root">Host root.</param>
    /// <param name="title">Title.</param>
    /// <param name="message">Body.</param>
    /// <param name="action">Primary button.</param>
    /// <returns><see langword="true"/> when confirmed.</returns>
    private static async Task<bool> ConfirmAsync(XamlRoot root, string title, string message, string action)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = title,
            Content = message,
            PrimaryButtonText = action,
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            Style = (Style)Application.Current.Resources["DefaultContentDialogStyle"],
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }
    #endregion
}
#endregion
