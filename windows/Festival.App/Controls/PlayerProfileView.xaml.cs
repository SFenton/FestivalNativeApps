using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Player profile view
/// <summary>
/// Player profile body shared by the player page and the Statistics section. Switch and Deselect are confirmed with a
/// <see cref="ContentDialog"/> (Fluent: confirm consequential, app-wide changes); neither navigates away.
/// </summary>
public sealed partial class PlayerProfileView : UserControl
{
    private readonly QuickLinksViewModel quickLinks = new("Quick Links");

    /// <summary>Creates the view with its Quick Links (the page model is replaced per navigation; the links stay).</summary>
    public PlayerProfileView()
    {
        InitializeComponent();
        var host = new QuickLinksHost(Root, Scroller, quickLinks, QuickLinksMenu, Pane);
        // Every instrument section is realized (non-virtualizing stack, #533); resolve the target's element for a jump.
        host.Binder.Resolve = id => ViewModel?.Instruments.FindIndex(i => i.QuickLinkId == id) is >= 0 and var index
            ? InstrumentsRepeater.GetOrCreateElement(index) as FrameworkElement
            : null;
        // Bands sits below that repeater: land the last instrument card first, then aim at Bands from its settled position.
        host.Binder.LeadIn = id => id == PlayerProfileViewModel.BandsQuickLinkId && ViewModel?.Instruments.Count is > 0 and var count
            ? InstrumentsRepeater.GetOrCreateElement(count - 1) as FrameworkElement
            : null;
        // Web PlayerPage: spinner until the profile is ready, then title, Overview and sections fade in, staggered.
        Scroller.RegisterPropertyChangedCallback(VisibilityProperty, (_, _) => StaggerIn());
        Scroller.Loaded += (_, _) => StaggerIn();
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

    /// <summary>Instrument section group ID.</summary>
    /// <param name="key">Service instrument ID.</param>
    /// <returns><c>fst.player.section.&lt;key&gt;</c>.</returns>
    public static string SectionId(string key) => "fst.player.section." + key;

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

    /// <summary>Rank-history placeholder ID.</summary>
    /// <param name="key">Service instrument ID.</param>
    /// <returns>Automation ID.</returns>
    public static string RankHistoryLoadingId(string key) => "fst.player.rank-history." + key + ".loading";

    /// <summary>Spoken name for a rank-history spinner.</summary>
    /// <param name="label">Instrument name.</param>
    /// <returns>Name.</returns>
    public static string LoadingHistoryName(string label) => $"Loading {label} rank history";

    /// <summary>Spoken name for a rank spinner.</summary>
    /// <param name="label">Instrument name.</param>
    /// <returns>Name.</returns>
    public static string LoadingRankName(string label) => $"Loading {label} global rank";
    #endregion

    #region Events
    /// <summary>The profile view that hosts an element (stat tiles and percentile rows route their links here).</summary>
    /// <param name="element">Descendant.</param>
    /// <returns>Owning view, or <see langword="null"/>.</returns>
    internal static PlayerProfileView? OwnerOf(DependencyObject element)
    {
        for (var node = element; node is not null; node = VisualTreeHelper.GetParent(node))
            if (node is PlayerProfileView view) return view;
        return null;
    }

    /// <summary>
    /// Follows a stat link: a viewed player is selected first (after the Switch confirmation when another player is
    /// selected, web <c>withProfileSwitch</c>), then Songs opens with the preset or the destination is pushed.
    /// </summary>
    /// <param name="link">Link.</param>
    internal async void Follow(PlayerStatLink link)
    {
        var step = ViewModel.PlanLink(link);
        if (step == PlayerLinkStep.Blocked) return;
        if (step == PlayerLinkStep.ConfirmSwitchThenGo &&
            !await ConfirmAsync("Switch Selected Profile?", ViewModel.SwitchMessage, "Switch Profile"))
            return;
        var (followed, route) = ViewModel.FollowLink(link);
        if (!followed) return;
        if (route is null) MainWindow.Instance?.ShowFilteredSongs();
        else MainWindow.Instance?.Navigate(route);
    }

    /// <summary>
    /// Fades the title row, Overview heading and Overview cards in, 125 ms apart, as the page's own entrance (sections
    /// stagger themselves): an early drag or Quick Links jump rushes whatever hasn't started (issue #323).
    /// </summary>
    private void StaggerIn()
    {
        if (Scroller.Visibility != Visibility.Visible || !Scroller.IsLoaded) return;
        FadeIn.BeginEntrance(Scroller);
        FadeIn.Enter(Scroller, TitleRow, TimeSpan.Zero);
        FadeIn.Enter(Scroller, OverviewHeading, FadeInTiming.Interval);
        FadeIn.Enter(Scroller, OverviewGrid, FadeInTiming.Interval * 2);
    }

    /// <summary>Selects directly, or confirms a switch away from another selected player.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private async void OnSelectClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel.SelectNeedsConfirmation &&
            !await ConfirmAsync("Switch Selected Profile?", ViewModel.SwitchMessage, "Switch Profile"))
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

    /// <summary>Title-row View All: opens the player's bands on All.</summary>
    /// <param name="sender">Link.</param>
    /// <param name="e">Unused.</param>
    private void OnBandsListLinkClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel.Bands is { } bands) MainWindow.Instance?.Navigate(bands.ListLinkRoute);
    }

    /// <summary>View All Bands (N): opens the player's bands on that group.</summary>
    /// <param name="sender">Button tagged with the group's route.</param>
    /// <param name="e">Unused.</param>
    private void OnBandsViewAllClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: AppRoute route }) MainWindow.Instance?.Navigate(route);
    }

    /// <summary>
    /// Starts a section's rank and history reads once it comes within a viewport of the visible area. The sections no
    /// longer virtualize (#533), so realization alone would read every played chart at once.
    /// </summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Prepared element.</param>
    private void OnInstrumentPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (args.Element is not FrameworkElement element) return;
        element.EffectiveViewportChanged -= OnInstrumentViewportChanged;
        element.EffectiveViewportChanged += OnInstrumentViewportChanged;
    }

    /// <summary>Loads a section when its effective viewport is within one viewport height of it.</summary>
    /// <param name="sender">Section element.</param>
    /// <param name="args">Viewport, in the section's coordinates.</param>
    private void OnInstrumentViewportChanged(FrameworkElement sender, EffectiveViewportChangedEventArgs args)
    {
        var viewport = args.EffectiveViewport;
        if (viewport.IsEmpty || !LazySectionReach.IsNear(viewport.Y, viewport.Height, sender.ActualHeight)) return;
        // The x:Bind template root has no DataContext: resolve the section from the element's current index.
        var index = InstrumentsRepeater.GetElementIndex(sender);
        if (index >= 0 && InstrumentsRepeater.ItemsSourceView?.GetAt(index) is PlayerInstrumentViewModel section)
            _ = section.EnsureLoadedAsync();
    }
    #endregion

    #region Dialogs
    /// <summary>Shows the shared Deselect confirmation.</summary>
    /// <param name="root">Host root.</param>
    /// <returns><see langword="true"/> when confirmed.</returns>
    public static Task<bool> ConfirmDeselectAsync(XamlRoot root) => ConfirmAsync(root, "Deselect Profile?",
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
        var dialog = FestivalDialog.Create(root, title, message, "fst.profile.confirm", closeText: "Cancel", primaryText: action);
        return await FestivalDialog.ShowAsync(dialog) == ContentDialogResult.Primary;
    }
    #endregion
}
#endregion
