using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI.ViewManagement;

namespace Festival.App.Pages;

#region Settings page
/// <summary>
/// Every web Settings section plus the native Accessibility section, with Quick Links (menu or pane) in one column; from
/// <see cref="SettingsDetails.SplitWidth"/> a list/detail page whose multi-option settings open in the trailing pane (issue #371).
/// </summary>
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
        if (ServiceInfoTimeoutOverride is { } timeout) ViewModel.ServiceInfo.ReadTimeout = timeout;
        InitializeComponent();
        QuickLinksMenu.Model = ViewModel.QuickLinks;
        InitializeDetails();
        quickLinks = new QuickLinksBinder(Scroller, ViewModel.QuickLinks, () => QuickLinksBinder.ReducedMotion(App.Session.Settings.ReduceMotion));
        ViewModel.ReplayRequested += (_, page) => MainWindow.Instance?.ShowFirstRunReplay(page);
        ViewModel.ServiceInfo.ProgressAnnounced += OnServiceProgressAnnounced;
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
    }

    /// <summary>Text-size source for the Service Info state row.</summary>
    private readonly UISettings uiSettings = new();

    /// <summary>
    /// Debug/automation <c>FST_DEBUG_SERVICE_INFO_TIMEOUT_MS</c>: a longer Service Info timeout so UI Automation can check and
    /// scan the Loading card while a fixture holds the first read (the 3 s default is shorter than that journey).
    /// </summary>
    private static readonly TimeSpan? ServiceInfoTimeoutOverride =
        SettingsServiceInfoViewModel.ParseTimeoutOverride(App.LaunchEnvironment("FST_DEBUG_SERVICE_INFO_TIMEOUT_MS"));

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

    /// <summary>
    /// Speaks a newly accepted Service Info attempt count (one polite UIA notification) from the attempt line, which has
    /// an automation peer; kept-back lower counts raise nothing (issue #275).
    /// </summary>
    /// <param name="sender">Unused.</param>
    /// <param name="announcement">Complete spoken progress.</param>
    private void OnServiceProgressAnnounced(object? sender, Festival.Core.ViewModels.Announcement announcement)
    {
        if (IsLoaded) ScreenReader.Announce(ServiceAttemptText, announcement);
    }

    /// <summary>A drag reorder finished: the list moved its rows in place, so save their new order.</summary>
    /// <param name="sender">Song-row or path-column list.</param>
    /// <param name="args">Drag result.</param>
    private void OnReorderCompleted(ListViewBase sender, DragItemsCompletedEventArgs args)
    {
        if (args.DropResult == Windows.ApplicationModel.DataTransfer.DataPackageOperation.None) return;
        if (sender.ItemsSource is IEnumerable<ReorderItemViewModel> rows) ViewModel.CommitDrag(rows);
    }

    #region List/detail
    /// <summary>Whether the page shows the list/detail layout (issue #371).</summary>
    public static readonly DependencyProperty IsSplitProperty =
        DependencyProperty.Register(nameof(IsSplit), typeof(bool), typeof(SettingsPage), new PropertyMetadata(false));

    /// <summary>
    /// Whether the page is at least <see cref="SettingsDetails.SplitWidth"/> wide: the settings list beside the detail pane,
    /// multi-option settings as chevron rows, and the Quick Links menu scrolling the list (a section's link lands on its row).
    /// </summary>
    public bool IsSplit
    {
        get => (bool)GetValue(IsSplitProperty);
        private set => SetValue(IsSplitProperty, value);
    }

    /// <summary>Visibility of one-column content: shown only outside the split layout.</summary>
    /// <param name="shown">Whether the content would show in one column.</param>
    /// <param name="split">Split layout.</param>
    /// <returns>Visibility.</returns>
    public Visibility InlineVisibility(bool shown, bool split) => shown && !split ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>Visibility of a split-layout chevron row: shown only in the split layout.</summary>
    /// <param name="shown">Whether the row is available.</param>
    /// <param name="split">Split layout.</param>
    /// <returns>Visibility.</returns>
    public Visibility SplitVisibility(bool shown, bool split) => shown && split ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>Page Quick Links binder (re-reads anchors when the layout switches).</summary>
    private readonly QuickLinksBinder quickLinks;

    /// <summary>One-column section anchors by Quick Links ID (their rows take the ID in the split layout).</summary>
    private readonly Dictionary<string, FrameworkElement> sectionAnchors = [];

    /// <summary>Chevron rows by entry.</summary>
    private Dictionary<SettingsDetail, SettingsDetailRow> detailRows = [];

    /// <summary>The one-column element each entry moves into the detail pane, and whether it needs the detail card.</summary>
    private Dictionary<SettingsDetail, (FrameworkElement Element, bool InCard)> detailBodies = [];

    /// <summary>Entry the detail pane shows.</summary>
    private SettingsDetail shownDetail;

    /// <summary>The element moved into the detail pane and its one-column home.</summary>
    private (FrameworkElement Element, Panel Home, int Index)? moved;

    /// <summary>Names the rows from Core <see cref="SettingsDetails"/> and maps each entry to its body.</summary>
    private void InitializeDetails()
    {
        detailRows = new()
        {
            [SettingsDetail.SongRowOrder] = SongRowOrderRow,
            [SettingsDetail.PathDefaultView] = PathDefaultViewRow,
            [SettingsDetail.PathColumnOrder] = PathColumnOrderRow,
            [SettingsDetail.Leeway] = LeewayRow,
            [SettingsDetail.ItemShop] = ItemShopRow,
            [SettingsDetail.Instruments] = InstrumentsRow,
            [SettingsDetail.Metadata] = MetadataRow,
            [SettingsDetail.Accessibility] = AccessibilityRow,
            [SettingsDetail.Version] = VersionRow,
            [SettingsDetail.ServiceInfo] = ServiceInfoRow,
            [SettingsDetail.FirstRun] = FirstRunRow,
            [SettingsDetail.Licenses] = LicensesRow,
            [SettingsDetail.PrivacyPolicy] = PrivacyPolicyRow,
        };
        foreach (var (detail, row) in detailRows)
        {
            var item = SettingsDetails.Item(detail);
            row.Title = item.Title;
            if (item.Description is { } description) row.Description = description;
        }
        detailBodies = new()
        {
            [SettingsDetail.SongRowOrder] = (SongRowOrderBody, true),
            [SettingsDetail.PathDefaultView] = (PathDefaultViewBody, true),
            [SettingsDetail.PathColumnOrder] = (PathColumnOrderBody, true),
            [SettingsDetail.Leeway] = (LeewayBody, true),
            [SettingsDetail.ItemShop] = (ItemShopCard, false),
            [SettingsDetail.Instruments] = (InstrumentsCard, false),
            [SettingsDetail.Metadata] = (MetadataCard, false),
            [SettingsDetail.Accessibility] = (AccessibilityCard, false),
            [SettingsDetail.Version] = (VersionCard, false),
            [SettingsDetail.ServiceInfo] = (ServiceInfoCard, false),
            [SettingsDetail.FirstRun] = (FirstRunCard, false),
        };
        CollectSectionAnchors(Scroller.Content as DependencyObject);
        PlaceholderTitle.Text = SettingsDetails.PlaceholderTitle;
        PlaceholderMessage.Text = SettingsDetails.PlaceholderMessage;
        ViewModel.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is null or "" or nameof(SettingsViewModel.SelectedDetail) or nameof(SettingsViewModel.MetadataDescription)) ApplyDetail();
        };
    }

    /// <summary>Finds the one-column section anchors whose chevron rows stand in for them in the split layout.</summary>
    /// <param name="node">Page content node.</param>
    private void CollectSectionAnchors(DependencyObject? node)
    {
        if (node is FrameworkElement element && QuickLinkAnchor.GetId(element) is { Length: > 0 } id) sectionAnchors[id] = element;
        switch (node)
        {
            case Panel panel:
                foreach (var child in panel.Children) CollectSectionAnchors(child);
                break;
            case Border border:
                CollectSectionAnchors(border.Child);
                break;
        }
    }

    /// <summary>
    /// Page width changed: from <see cref="SettingsDetails.SplitWidth"/> the list/detail layout (fixed list column, Quick
    /// Links menu over the list); below it one column with the Quick Links pane when wide enough, else the header menu.
    /// </summary>
    /// <param name="sender">Root grid.</param>
    /// <param name="e">New size.</param>
    private void OnRootSizeChanged(object sender, SizeChangedEventArgs e)
    {
        var split = SettingsDetails.UsesSplit(e.NewSize.Width);
        var pane = !split && QuickLinks.UsesPane(e.NewSize.Width);
        Pane.Visibility = pane ? Visibility.Visible : Visibility.Collapsed;
        MenuHost.Visibility = pane ? Visibility.Collapsed : Visibility.Visible;
        if (split == IsSplit) return;
        IsSplit = split;
        ListColumn.Width = split ? new GridLength(SettingsDetails.ListWidth) : new GridLength(1, GridUnitType.Star);
        DetailColumn.Width = split ? new GridLength(1, GridUnitType.Star) : GridLength.Auto;
        DetailHost.Visibility = split ? Visibility.Visible : Visibility.Collapsed;
        ApplyQuickLinkAnchors(split);
        ApplyDetail();
    }

    /// <summary>
    /// Moves each section's Quick Links ID between its one-column section (shown only in one column) and its chevron row
    /// (shown only in the split layout), so the menu keeps every section and a link scrolls the list to what is on screen.
    /// </summary>
    /// <param name="split">Split layout.</param>
    private void ApplyQuickLinkAnchors(bool split)
    {
        foreach (var (detail, row) in detailRows)
        {
            if (SettingsDetails.QuickLinkId(detail) is not { } id || !sectionAnchors.TryGetValue(id, out var section)) continue;
            QuickLinkAnchor.SetId(section, split ? null : id);
            QuickLinkAnchor.SetId(row, split ? id : null);
        }
        // Laid out first, so the newly visible anchors have frames.
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, quickLinks.Refresh);
    }

    /// <summary>A chevron row: open its entry in the detail pane (the open entry stays open).</summary>
    /// <param name="sender">Row tagged with its <see cref="SettingsDetail"/>.</param>
    /// <param name="e">Unused.</param>
    private void OnDetailRowClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string tag } && Enum.TryParse<SettingsDetail>(tag, out var detail)) ViewModel.SelectDetail(detail);
    }

    /// <summary>
    /// Shows the selected entry (the placeholder when none, or outside the split layout nothing) and marks its row current.
    /// A section card or App Settings body moves from its one-column place into the pane, so there is one live copy of
    /// each control (bindings, drag lists and Service Info polling keep working), and moves back when deselected or when
    /// the page narrows to one column.
    /// </summary>
    private void ApplyDetail()
    {
        var detail = IsSplit ? ViewModel.SelectedDetail : SettingsDetail.None;
        foreach (var (key, row) in detailRows) row.IsCurrent = key == detail && detail != SettingsDetail.None;
        if (detail == SettingsDetail.Metadata) ApplyDetailHeader(detail);
        if (detail == shownDetail) return;
        shownDetail = detail;
        RestoreMoved();
        DetailBody.Children.Clear();
        DetailCard.Visibility = Visibility.Collapsed;
        DetailFrame.Content = null;
        DetailFrame.Visibility = Visibility.Collapsed;
        PlaceholderScroller.Visibility = detail == SettingsDetail.None ? Visibility.Visible : Visibility.Collapsed;
        DetailScroller.Visibility = detail is SettingsDetail.None or SettingsDetail.Licenses ? Visibility.Collapsed : Visibility.Visible;
        switch (detail)
        {
            case SettingsDetail.None:
                return;
            case SettingsDetail.Licenses:
                DetailFrame.Visibility = Visibility.Visible;
                DetailFrame.Navigate(typeof(LicensesPage), null, new Microsoft.UI.Xaml.Media.Animation.SuppressNavigationTransitionInfo());
                return;
            case SettingsDetail.PrivacyPolicy:
                DetailBody.Children.Add(new Border
                {
                    Style = (Style)Application.Current.Resources["FSTCardStyle"],
                    Padding = new Thickness(16, 12, 16, 12),
                    Child = PrivacyPolicyDialog.Body(PrivacyPolicyDialog.Load()),
                });
                break;
            default:
                if (detailBodies.TryGetValue(detail, out var body)) Move(body.Element, body.InCard);
                break;
        }
        ApplyDetailHeader(detail);
        DetailScroller.ChangeView(null, 0, null, true);
    }

    /// <summary>The pane heading and description (Show Instrument Metadata's follows the player selection).</summary>
    /// <param name="detail">Shown entry.</param>
    private void ApplyDetailHeader(SettingsDetail detail)
    {
        var item = SettingsDetails.Item(detail);
        DetailTitle.Text = item.Title;
        DetailDescription.Text = item.Description ?? (detail == SettingsDetail.Metadata ? ViewModel.MetadataDescription : "");
        DetailDescription.Visibility = DetailDescription.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>Moves a one-column element into the pane, remembering where it lives.</summary>
    /// <param name="element">Section card or App Settings body.</param>
    /// <param name="inCard">Whether it goes in the detail card.</param>
    private void Move(FrameworkElement element, bool inCard)
    {
        if (element.Parent is not Panel home) return;
        moved = (element, home, home.Children.IndexOf(element));
        home.Children.Remove(element);
        if (inCard)
        {
            DetailCard.Child = element;
            DetailCard.Visibility = Visibility.Visible;
        }
        else
        {
            DetailBody.Children.Add(element);
        }
    }

    /// <summary>Returns the moved element to its one-column place.</summary>
    private void RestoreMoved()
    {
        if (moved is not { } m) return;
        moved = null;
        if (ReferenceEquals(DetailCard.Child, m.Element)) DetailCard.Child = null;
        else DetailBody.Children.Remove(m.Element);
        m.Home.Children.Insert(Math.Min(m.Index, m.Home.Children.Count), m.Element);
    }
    #endregion

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

    /// <summary>Opens the shared Privacy Policy dialog (issue #98), then returns focus to the row.</summary>
    /// <param name="sender">Row.</param>
    /// <param name="e">Unused.</param>
    private async void OnPrivacyPolicyClick(object sender, RoutedEventArgs e)
    {
        await PrivacyPolicyDialog.ShowAsync(XamlRoot);
        (sender as Control)?.Focus(FocusState.Programmatic);
    }

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

    /// <summary>Report an Issue / Request a Feature: opens that form (issue #78).</summary>
    /// <param name="sender">Row tagged <c>Bug</c> or <c>Feature</c>.</param>
    /// <param name="e">Unused.</param>
    private async void OnFeedbackClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string tag } && Enum.TryParse<FeedbackKind>(tag, out var kind))
            await FeedbackDialog.ShowAsync(XamlRoot, kind);
    }
}
#endregion
