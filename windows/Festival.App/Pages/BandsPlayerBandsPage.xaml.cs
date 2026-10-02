using System.ComponentModel;
using Festival.App.Controls;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Festival.App.Services;

namespace Festival.App.Pages;

#region Player bands page
/// <summary><c>/bands/player/:accountId</c>: a player's bands with a group filter and paging.</summary>
public sealed partial class BandsPlayerBandsPage : Page
{
    /// <summary>Creates the page.</summary>
    public BandsPlayerBandsPage()
    {
        InitializeComponent();
        Controls.BoardFooter.Inset(Footer, Cards);
    }

    /// <summary>Page model (set on navigation).</summary>
    public PlayerBandsViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel = new PlayerBandsViewModel(App.Session, (AppRoute.PlayerBands)e.Parameter);
        ViewModel.AnimateLoadSwaps = () => Motion.Allowed;
        ViewModel.PropertyChanged += OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed += OnContentRevealed;
        ScreenReader.Attach(this, [ViewModel, ViewModel.Pager], () => ViewModel.IsLoading,
            () => ViewModel.ShowRows ? $"{ViewModel.Title}, {ViewModel.Pager.PageAnnouncement}" : ViewModel.ShowEmpty ? ViewModel.EmptyMessage : null,
            "Loading bands");
        Bindings.Update();
        GroupBar.SelectedItem = GroupBar.Items[ViewModel.GroupIndex];
        await ViewModel.LoadAsync();
    }

    /// <summary>Applies the segmented group choice.</summary>
    /// <param name="sender">Selector bar.</param>
    /// <param name="args">Unused.</param>
    private void OnGroupChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        if (ViewModel is null || sender.SelectedItem is null) return;
        ViewModel.GroupIndex = sender.Items.IndexOf(sender.SelectedItem);
    }

    /// <summary>Scrolls back to the top when a new page or group arrives.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(PlayerBandsViewModel.Entries)) Scroller.ChangeView(null, 0, null, true);
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed -= OnContentRevealed;
        base.OnNavigatedFrom(e);
    }

    /// <summary>Replays the web card entrance after the shared load gate reveals a new page.</summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() => FadeIn.StaggerRealized(Cards));
}
#endregion
