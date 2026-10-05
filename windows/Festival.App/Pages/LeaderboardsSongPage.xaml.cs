using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Song leaderboard page
/// <summary>Solo song leaderboard (<c>/songs/:songId/:instrument</c>) over the song's static cover.</summary>
public sealed partial class LeaderboardsSongPage : Page, IBackdropPage
{
    private CancellationTokenSource headerArt = new();
    private int shownPage;
    private bool spotlightShown;
    private readonly BoardFooterFade footerFade;
    private readonly Windows.UI.ViewManagement.UISettings fadeUiSettings = new();

    /// <summary>Creates the page.</summary>
    public LeaderboardsSongPage()
    {
        InitializeComponent();
        BoardFooter.Inset(Footer, ScrollContent);
        footerFade = new BoardFooterFade(BoardFadeSource, BoardFadeHost);
        Scroller.ViewChanged += (_, _) => UpdateFooterFade();
        Footer.SizeChanged += (_, _) => UpdateFooterFade();
        BoardFadeSource.SizeChanged += (_, _) => UpdateFooterFade();
        BoardFadeSource.RegisterPropertyChangedCallback(VisibilityProperty, (_, _) => UpdateFooterFade());
        Loaded += (_, _) => AttachFooterFadeSettings();
        Unloaded += (_, _) => DetachFooterFadeSettings();
    }

    /// <summary>Page model (set on navigation).</summary>
    public SongLeaderboardViewModel ViewModel { get; private set; } = null!;

    /// <inheritdoc />
    public bool UsesSongCover => true;

    /// <inheritdoc />
    public string? BackdropArt => ViewModel?.Song?.AlbumArt;

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        var route = (AppRoute.SongLeaderboard)e.Parameter;
        ViewModel = LeaderboardsPageState<SongLeaderboardViewModel>.GetOrCreate(e.Parameter,
            () => new SongLeaderboardViewModel(App.Session, route), out var created);
        ViewModel.AnimateLoadSwaps = () => Motion.Allowed;
        ViewModel.PropertyChanged += OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed += OnContentRevealed;
        // An arrival from Song Detail's spotlight row (navToPlayer) brings the highlighted row into view on first load.
        shownPage = created && route.RevealSelected ? 0 : ViewModel.Page;
        spotlightShown = ViewModel.ShowSpotlight;
        ScreenReader.Attach(this, [ViewModel, ViewModel.Pager], () => ViewModel.IsLoading,
            () => ViewModel.ShowRows ? $"{ViewModel.Title} leaderboard, {ViewModel.Pager.InfoAnnouncement}" : ViewModel.ShowEmpty ? $"{ViewModel.Title} leaderboard, no entries" : null,
            "Loading leaderboard");
        Bindings.Update();
        if (ViewModel.Song is not null) _ = ShowSongAsync();
        await ViewModel.ActivateAsync();
    }

    /// <inheritdoc />
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        headerArt.Cancel();
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.LoadSwap.ContentRevealed -= OnContentRevealed;
        ViewModel.Deactivate();
        base.OnNavigatedFrom(e);
    }

    /// <summary>Loads art once the song resolves, reveals the selected row (else scrolls to the top) on page changes and fades in a late pinned row.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SongLeaderboardViewModel.Song)) _ = ShowSongAsync();
        else if (e.PropertyName == nameof(SongLeaderboardViewModel.ShowSpotlight))
        {
            var shown = ViewModel.ShowSpotlight;
            if (PinnedRowReveal.FadesOnArrival(spotlightShown, shown, ViewModel.LoadSwap.Phase))
                DispatcherQueue.TryEnqueue(() => FadeIn.Play(SpotlightPanel, TimeSpan.Zero));
            spotlightShown = shown;
        }
        else if (e.PropertyName == nameof(SongLeaderboardViewModel.Rows) && ViewModel.Page != shownPage)
        {
            shownPage = ViewModel.Page;
            Scroller.ChangeView(null, 0, null, true);
            var selected = ViewModel.Rows.FindIndex(r => r.IsSelected);
            if (selected >= 0)
            {
                DispatcherQueue.TryEnqueue(() =>
                {
                    if (RowsRepeater.GetOrCreateElement(selected) is Microsoft.UI.Xaml.UIElement row)
                        row.StartBringIntoView(new Microsoft.UI.Xaml.BringIntoViewOptions { VerticalAlignmentRatio = 0.5, AnimationDesired = false });
                });
            }
        }
    }

    /// <summary>
    /// Replays the web row entrance after the shared load gate reveals a new page, with the pinned "your score" row
    /// entering alongside the first row (issue #295).
    /// </summary>
    /// <param name="sender">Swap.</param>
    /// <param name="e">Unused.</param>
    private void OnContentRevealed(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(() =>
        {
            FadeIn.StaggerRealized(RowsRepeater);
            if (ViewModel.ShowSpotlight) FadeIn.Play(SpotlightPanel, PinnedRowReveal.RevealDelay);
        });

    /// <summary>Updates the backdrop and header art for the resolved song.</summary>
    /// <returns>Load task.</returns>
    private async Task ShowSongAsync()
    {
        if (ViewModel.Song is not { } song) return;
        MainWindow.Instance?.RefreshBackdrop();
        headerArt.Cancel();
        headerArt = new CancellationTokenSource();
        var pixels = (int)Math.Ceiling(80 * (XamlRoot?.RasterizationScale ?? 1));
        HeaderArt.Source = await ArtworkImages.LoadAsync(song.AlbumArt, pixels, headerArt.Token);
    }

    /// <summary>F5 reloads the current page.</summary>
    /// <param name="sender">Accelerator.</param>
    /// <param name="args">Handled here.</param>
    private void OnRefreshInvoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        _ = ViewModel.LoadAsync();
    }

    #region Footer fade
    /// <summary>
    /// Fades rows out above the floating "your score" row and pager while more rows lie below, and hides them beneath
    /// the footer (issue #93, web <c>useScrollMask</c>), unless a contrast theme, Windows transparency effects off or the
    /// in-app Increase Contrast or Less Transparency setting asks for the plain list. Under a contrast theme a
    /// window-colour plate behind the footer hides the rows there instead. Runs on scroll and size changes only.
    /// </summary>
    private void UpdateFooterFade()
    {
        var settings = App.Session.Settings;
        var contrast = ContrastTheme.IsOn;
        var shown = BoardFadeSource.Visibility == Visibility.Visible && Footer.ActualHeight > 0;
        FooterPlate.Visibility = contrast && shown ? Visibility.Visible : Visibility.Collapsed;
        if (contrast && shown) FooterPlate.Height = Footer.ActualHeight;
        var enabled = shown &&
                      SongHeaderEdgeFade.IsEnabled(contrast, fadeUiSettings.AdvancedEffectsEnabled, settings.LessTransparency, settings.MoreContrast);
        double? top = enabled ? Footer.TransformToVisual(BoardFadeSource).TransformPoint(default).Y : null;
        footerFade.Update(top, BoardFooterEdgeFade.Strength(Scroller.ScrollableHeight, Scroller.VerticalOffset));
    }

    /// <summary>Follows appearance changes that switch the fade on or off while the page is shown.</summary>
    private void AttachFooterFadeSettings()
    {
        App.Session.PropertyChanged += OnFooterFadeSettingsChanged;
        fadeUiSettings.AdvancedEffectsEnabledChanged += OnFooterFadeSystemChanged;
        // HighContrastChanged needs a CoreWindow; a contrast-theme switch raises ColorValuesChanged instead.
        fadeUiSettings.ColorValuesChanged += OnFooterFadeSystemChanged;
        UpdateFooterFade();
    }

    /// <summary>Stops following appearance changes.</summary>
    private void DetachFooterFadeSettings()
    {
        App.Session.PropertyChanged -= OnFooterFadeSettingsChanged;
        fadeUiSettings.AdvancedEffectsEnabledChanged -= OnFooterFadeSystemChanged;
        fadeUiSettings.ColorValuesChanged -= OnFooterFadeSystemChanged;
    }

    /// <summary>Re-evaluates the fade when the in-app settings change.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnFooterFadeSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == "Settings") DispatcherQueue.TryEnqueue(UpdateFooterFade);
    }

    /// <summary>Re-evaluates the fade when Windows transparency effects or the contrast theme change (any thread).</summary>
    /// <param name="sender">Settings source.</param>
    /// <param name="args">Ignored.</param>
    private void OnFooterFadeSystemChanged(object sender, object args) => DispatcherQueue.TryEnqueue(UpdateFooterFade);
    #endregion
}
#endregion
