using System.ComponentModel;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Shop page
/// <summary>
/// Item Shop: the web's album-art grid (always at compact widths) or, by preference on wider windows, a list. Tiles and
/// rows open Song Detail for catalogue songs; the tile's context menu and the row's cart button open the validated
/// official Item Shop link. Each layout stays hidden behind a ring until its first art decodes (bounded), then staggers in
/// (web page-ready gate, operator batch 6.41), again after a List/Grid switch (6.10).
/// </summary>
public sealed partial class ShopPage : Page
{
    /// <summary>Width below which the grid is forced and the layout toggle hidden.</summary>
    private const double CompactWidth = 640;

    /// <summary>Offers whose art is decoded before a layout is revealed.</summary>
    private const int ArtworkPrimeCount = 15;

    /// <summary>Upper bound on the reveal wait.</summary>
    private static readonly TimeSpan ArtworkPrimeTimeout = TimeSpan.FromMilliseconds(900);

    private readonly Dictionary<FrameworkElement, CancellationTokenSource> artLoads = [];
    private double tileSize = 200;
    private int revealGeneration;

    /// <summary>Creates the page.</summary>
    public ShopPage()
    {
        ViewModel = new ShopViewModel(App.Session);
        InitializeComponent();
        SizeChanged += (_, e) =>
        {
            ViewModel.IsCompact = e.NewSize.Width < CompactWidth;
            // Compact: no right gutter for the overlaying scroll indicator (operator 7.24; right edge 16 → 12 epx).
            Root.Padding = ViewModel.IsCompact ? new Thickness(12, 8, 12, 0) : new Thickness(24, 12, 12, 0);
            GridScroller.Padding = OfferList.Padding = ViewModel.IsCompact ? new Thickness(0, 0, 0, 24) : new Thickness(0, 0, 12, 24);
            Header.Margin = ViewModel.IsCompact ? new Thickness(0) : new Thickness(0, 0, 12, 0);
        };
        ViewModel.PropertyChanged += OnViewModelChanged;
        ScreenReader.Attach(this, [ViewModel], () => ViewModel.IsLoading,
            () => ViewModel.ShowEmpty ? "No Item Shop songs" : ViewModel.State == LoadState.Loaded ? $"Item Shop, {ViewModel.CountText}" : null,
            "Loading Item Shop");
    }

    /// <summary>Page model.</summary>
    public ShopViewModel ViewModel { get; }

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        UpdateToggleGlyph();
        await ViewModel.AppearCommand.ExecuteAsync(null);
    }

    /// <summary>Keeps the toggle glyph naming the other layout.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ShopViewModel.ToggleLabel)) UpdateToggleGlyph();
        if (e.PropertyName == nameof(ShopViewModel.Offers)) PerfLog.Mark("shop-rendered");
        // Offers are projected before the state turns Loaded; a re-projection while loaded (settings) reveals again.
        if (e.PropertyName is nameof(ShopViewModel.Offers) or nameof(ShopViewModel.State) && ViewModel.ShowOffers) _ = RevealAsync();
    }

    /// <summary>List icon when the grid shows, grid icon when the list shows.</summary>
    private void UpdateToggleGlyph() => ToggleGlyph.Glyph = ViewModel.ToggleLabel == "List View" ? "" : "";

    /// <summary>Switches grid/list.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnToggleView(object sender, RoutedEventArgs e)
    {
        ViewModel.ToggleViewCommand.Execute(null);
        // The new layout starts at the top and replays the entrance, like the web's view toggle (operator batch 6.10).
        GridScroller.ChangeView(null, 0, null, true);
        if (ViewModel.Offers.Count > 0) OfferList.ScrollIntoView(ViewModel.Offers[0]);
        _ = RevealAsync();
    }

    /// <summary>
    /// Hides the visible layout behind the ring until the first offers' art has decoded (at most
    /// <see cref="ArtworkPrimeTimeout"/>, so Shop art is fetched ahead of anything else the page would show), then fades
    /// its realized tiles or rows in with the shared stagger. A newer reveal supersedes an older one.
    /// </summary>
    /// <returns>Reveal task.</returns>
    private async Task RevealAsync()
    {
        var generation = ++revealGeneration;
        if (!ViewModel.ShowOffers) return;
        var grid = ViewModel.ShowGrid;
        UIElement target = grid ? GridScroller : OfferList;
        target.Opacity = 0;
        RevealRing.IsActive = true;
        if (!App.Session.Settings.SaveData && !App.Options.NoArt)
        {
            var pixels = (int)Math.Ceiling((grid ? tileSize : SongRowCard.ArtSize) * (XamlRoot?.RasterizationScale ?? 1));
            using var cancellation = new CancellationTokenSource(ArtworkPrimeTimeout);
            var loads = ViewModel.Offers.Take(ArtworkPrimeCount)
                .Select(o => ArtworkImages.LoadAsync(o.Offer.AlbumArt, pixels, cancellation.Token));
            await Task.WhenAny(Task.WhenAll(loads), Task.Delay(ArtworkPrimeTimeout));
        }
        if (generation != revealGeneration) return;
        RevealRing.IsActive = false;
        target.Opacity = 1;
        if (grid) FadeIn.StaggerRealized(OfferGrid);
        else FadeIn.StaggerRealized(OfferList);
    }

    /// <summary>Styles and loads art for a realized grid tile.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Prepared element.</param>
    private void OnGridPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (args.Element is not Grid tile || sender.ItemsSourceView?.GetAt(args.Index) is not ShopOfferItem item) return;
        SizeTile(tile);
        ApplyBadge(tile, item, "BadgePill", "BadgeLabel");
        ((ShopPulseRing)tile.FindName("ShopRing")).Apply(item.Pulse);
        var image = (Image)tile.FindName("Art");
        image.Source = null;
        _ = LoadArtAsync(tile, image, item, tileSize);
    }

    /// <summary>
    /// Square tiles in the web's 2-5 columns for the scroller's content width (not the repeater's own width, which the
    /// layout itself sets).
    /// </summary>
    /// <param name="sender">Grid scroller.</param>
    /// <param name="e">Size change.</param>
    private void OnGridSizeChanged(object sender, SizeChangedEventArgs e)
    {
        var width = e.NewSize.Width - GridScroller.Padding.Left - GridScroller.Padding.Right;
        var tile = ShopGridMetrics.TileSize(width);
        TileLayout.MaximumRowsOrColumns = ShopGridMetrics.Columns(width);
        OfferGrid.MaxWidth = ShopGridMetrics.ContentWidth(width);
        if (tile == tileSize) return;
        tileSize = tile;
        TileLayout.MinItemWidth = tile;
        TileLayout.MinItemHeight = tile;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(OfferGrid); i++)
            if (VisualTreeHelper.GetChild(OfferGrid, i) is FrameworkElement child) SizeTile(child);
    }

    /// <summary>Gives a tile the current square size (explicit: the layout's Fill stretch rounds columns away).</summary>
    /// <param name="tile">Tile root.</param>
    private void SizeTile(FrameworkElement tile)
    {
        tile.Width = tileSize;
        tile.Height = tileSize;
    }

    /// <summary>Cancels art for a recycled grid card.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Clearing element.</param>
    private void OnElementClearing(ItemsRepeater sender, ItemsRepeaterElementClearingEventArgs args)
    {
        if (args.Element is FrameworkElement element && artLoads.Remove(element, out var pending)) pending.Cancel();
    }

    /// <summary>Fills the shared song row card with the offer's badge, cart button, pulse and art.</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container info.</param>
    private void OnListContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.ItemContainer is not ListViewItem container || args.Item is not ShopOfferItem item) return;
        if (container.ContentTemplateRoot is not SongRowCard card) return;
        if (artLoads.Remove(container, out var pending)) pending.Cancel();
        if (args.InRecycleQueue)
        {
            card.ApplyShop(null);
            return;
        }
        card.Reset();
        AutomationProperties.SetName(container, item.Announcement);
        AutomationProperties.SetAutomationId(container, $"fst.shop.song.{item.Offer.SongId}");
        // The text badge names the Shop state here, so the Songs bag on the art is not repeated.
        card.ApplyShop(item.Pulse, showBag: false);
        if (item.HasBadge)
        {
            var label = new TextBlock { Text = item.BadgeText, FontSize = 12, FontWeight = Microsoft.UI.Text.FontWeights.Bold };
            var badge = new Border { Padding = new Thickness(8, 2, 8, 2), CornerRadius = new CornerRadius(10), VerticalAlignment = VerticalAlignment.Center, Child = label };
            ApplyBadge(badge, label, item);
            card.Trailing.Children.Add(badge);
        }
        var external = new Button
        {
            Width = 44,
            Height = 44,
            Padding = new Thickness(0),
            CornerRadius = new CornerRadius(22),
            Tag = item,
            Content = new FontIcon { Glyph = "\uE719", FontSize = 16 },
        };
        external.Click += OnExternalClick;
        AutomationProperties.SetName(external, item.ExternalName);
        AutomationProperties.SetAutomationId(external, item.ExternalAutomationId);
        ToolTipService.SetToolTip(external, "Open official Item Shop");
        card.Trailing.Children.Add(external);
        _ = LoadArtAsync(container, card.Art, item, SongRowCard.ArtSize);
    }

    /// <summary>Colors a grid tile's New (gold on dark) or Leaving Tomorrow (white on red) badge.</summary>
    /// <param name="root">Template root.</param>
    /// <param name="item">Offer.</param>
    /// <param name="badgeName">Badge border name.</param>
    /// <param name="textName">Badge text name.</param>
    private static void ApplyBadge(FrameworkElement root, ShopOfferItem item, string badgeName, string textName)
    {
        if (root.FindName(badgeName) is Border badge && root.FindName(textName) is TextBlock text) ApplyBadge(badge, text, item);
    }

    /// <summary>Colors a New (gold on dark) or Leaving Tomorrow (white on red) badge.</summary>
    /// <param name="badge">Badge pill.</param>
    /// <param name="text">Badge text.</param>
    /// <param name="item">Offer.</param>
    private static void ApplyBadge(Border badge, TextBlock text, ShopOfferItem item)
    {
        badge.Background = item.IsLeaving ? Brush("FSTShopLeavingBrush")
            : Services.ContrastTheme.IsOn ? Brush("FSTShopNewBrush") : new SolidColorBrush(Windows.UI.Color.FromArgb(0xE6, 0x12, 0x18, 0x26));
        text.Foreground = item.IsLeaving || Services.ContrastTheme.IsOn ? Brush("FSTShopBadgeTextBrush") : Brush("FSTShopNewBrush");
        AutomationProperties.SetAutomationId(text, item.IsLeaving ? $"fst.shop.badge.leaving.{item.Offer.SongId}" : $"fst.shop.badge.new.{item.Offer.SongId}");
    }

    /// <summary>Loads cover art for a card or row.</summary>
    /// <param name="owner">Card or container.</param>
    /// <param name="image">Target.</param>
    /// <param name="item">Offer.</param>
    /// <param name="size">Display size in epx.</param>
    /// <returns>Load task.</returns>
    private async Task LoadArtAsync(FrameworkElement owner, Image image, ShopOfferItem item, double size)
    {
        if (App.Session.Settings.SaveData || App.Options.NoArt) return;
        var cancellation = new CancellationTokenSource();
        if (artLoads.Remove(owner, out var previous)) previous.Cancel();
        artLoads[owner] = cancellation;
        var pixels = (int)Math.Ceiling(size * (XamlRoot?.RasterizationScale ?? 1));
        var bitmap = await ArtworkImages.LoadAsync(item.Offer.AlbumArt, pixels, cancellation.Token);
        // A recycled tile may already show another offer: only the load it still owns may set its art.
        if (!cancellation.IsCancellationRequested && artLoads.TryGetValue(owner, out var current) && current == cancellation)
        {
            artLoads.Remove(owner);
            image.Source = bitmap;
        }
    }

    /// <summary>Opens the validated official Item Shop page in the browser.</summary>
    /// <param name="sender">Button tagged with its offer.</param>
    /// <param name="e">Unused.</param>
    private async void OnExternalClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: ShopOfferItem item } && item.Offer.ShopUri is { } uri)
            await Windows.System.Launcher.LaunchUriAsync(uri);
    }

    /// <summary>Tile: Song Detail for a catalogue song, otherwise the official Item Shop.</summary>
    /// <param name="sender">Tile button tagged with its offer.</param>
    /// <param name="e">Unused.</param>
    private void OnTileClick(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: ShopOfferItem item }) return;
        if (item.HasSongDetail) MainWindow.Instance?.Navigate(item.DetailRoute);
        else OnExternalClick(sender, e);
    }

    /// <summary>Opens Song Detail from a list row (when the song is in the catalogue).</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Clicked offer.</param>
    private void OnListClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is ShopOfferItem { HasSongDetail: true } item) MainWindow.Instance?.Navigate(item.DetailRoute);
    }

    /// <summary>Looks up an app brush.</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Brush.</returns>
    private static Brush Brush(string key) => (Brush)Application.Current.Resources[key];
}
#endregion
