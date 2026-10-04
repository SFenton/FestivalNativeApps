using System.ComponentModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Navigation;
using Festival.App.Services;

namespace Festival.App.Pages;

#region All rivals page
/// <summary>
/// All Rivals (<c>/rivals/all</c>): one scope's full list in a virtualized, centred column; at wide widths the chosen
/// rival's detail fills a second column (like Songs).
/// </summary>
public sealed partial class AllRivalsPage : Page
{
    /// <summary>Page width from which the list and a rival's detail sit side by side.</summary>
    public const double SplitWidth = 1100;

    /// <summary>List column width in the split layout.</summary>
    private const double SplitListWidth = 520;

    private bool split;
    private string? detailAccountId;

    /// <summary>Creates the page.</summary>
    public AllRivalsPage()
    {
        InitializeComponent();
        SizeChanged += (_, e) => ApplySplit(e.NewSize.Width >= SplitWidth);
        KeyboardAccelerators.Add(RivalsPage.Accelerator(Windows.System.VirtualKey.F5, Windows.System.VirtualKeyModifiers.None,
            () => ViewModel.RefreshCommand.Execute(null)));
    }

    /// <summary>Page model (set on navigation).</summary>
    public AllRivalsViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = new AllRivalsViewModel(App.Session, (AppRoute.AllRivals)e.Parameter);
        ScreenReader.Attach(this, [ViewModel], () => ViewModel.IsLoading,
            () => ViewModel.ShowContent ? ViewModel.Title : ViewModel.ShowEmpty ? ViewModel.EmptyTitle : null, "Loading rivals");
        ViewModel.PropertyChanged += OnViewModelChanged;
        Bindings.Update();
        ViewModel.Activate();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.Deactivate();
        base.OnNavigatedFrom(e);
    }

    /// <summary>Rows arriving or clearing re-evaluate the split.</summary>
    /// <param name="sender">Model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AllRivalsViewModel.Rows) or nameof(AllRivalsViewModel.ShowContent)) EnsureSplitSelection();
    }

    #region Split layout
    /// <summary>
    /// List + Rival Detail columns (never an empty detail): the list keeps a fixed column and the rival fills the rest.
    /// Below the width, or without rows, it is the single centred column again.
    /// </summary>
    /// <param name="wanted">Whether the page is wide enough.</param>
    private void ApplySplit(bool wanted)
    {
        var on = wanted && ViewModel is { ShowContent: true } && ViewModel.Rows.Any(r => r.HasProfile);
        if (on == split) return;
        split = on;
        ListColumn.Width = on ? new GridLength(SplitListWidth) : new GridLength(1, GridUnitType.Star);
        DetailColumn.Width = on ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
        DetailFrame.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        RivalList.SelectionMode = on ? ListViewSelectionMode.Single : ListViewSelectionMode.None;
        if (on)
        {
            EnsureSplitSelection();
            return;
        }
        detailAccountId = null;
        DetailFrame.Content = null;
    }

    /// <summary>Keeps a rival showing: the current one if still listed, else the first.</summary>
    private void EnsureSplitSelection()
    {
        if (!split)
        {
            ApplySplit(ActualWidth >= SplitWidth);
            return;
        }
        if (!ViewModel.ShowContent || !ViewModel.Rows.Any(r => r.HasProfile))
        {
            ApplySplit(false);
            return;
        }
        var target = ViewModel.Rows.FirstOrDefault(r => r.HasProfile && r.AccountId == detailAccountId) ?? ViewModel.Rows.First(r => r.HasProfile);
        if (!ReferenceEquals(RivalList.SelectedItem, target)) RivalList.SelectedItem = target;
        Show(target);
    }

    /// <summary>The detail column follows the selected row.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Selection change.</param>
    private void OnRivalSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!split || RivalList.SelectedItem is not RivalRowItem row) return;
        if (row.HasProfile) Show(row);
        else RivalList.SelectedItem = e.RemovedItems.Count > 0 ? e.RemovedItems[0] : null;
    }

    /// <summary>Opens a rival in the detail column (once per rival).</summary>
    /// <param name="row">Row.</param>
    private void Show(RivalRowItem row)
    {
        if (row.AccountId == detailAccountId && DetailFrame.Content is not null) return;
        detailAccountId = row.AccountId;
        DetailFrame.Navigate(typeof(RivalDetailPage), row.Route, new SuppressNavigationTransitionInfo());
    }
    #endregion

    /// <summary>Names each row container for UI Automation.</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container.</param>
    private void OnContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.Item is not RivalRowItem row) return;
        AutomationProperties.SetName(args.ItemContainer, row.AccessibleName);
        AutomationProperties.SetAutomationId(args.ItemContainer, "fst.all-rivals.row." + row.RowKey);
        args.ItemContainer.IsHitTestVisible = row.HasProfile;
        args.ItemContainer.IsTabStop = row.HasProfile;
    }

    /// <summary>Opens the rival.</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked row.</param>
    private void OnRivalClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not RivalRowItem { HasProfile: true } row) return;
        if (split) Show(row);
        else MainWindow.Instance?.Navigate(row.Route);
    }
}
#endregion
