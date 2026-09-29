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
/// rows open Song Detail for catalogue songs; the cart button opens the validated official Item Shop link.
/// </summary>
public sealed partial class ShopPage : Page
{
    /// <summary>Width below which the grid is forced and the layout toggle hidden.</summary>
    private const double CompactWidth = 640;

    private readonly Dictionary<FrameworkElement, CancellationTokenSource> artLoads = [];
    private double tileSize = 200;

    /// <summary>Creates the page.</summary>
    public ShopPage()
    {
        ViewModel = new ShopViewModel(App.Session);
        InitializeComponent();
        SizeChanged += (_, e) =>
        {
            ViewModel.IsCompact = e.NewSize.Width < CompactWidth;
            Root.Padding = ViewModel.IsCompact ? new Thickness(12, 8, 4, 0) : new Thickness(24, 12, 12, 0);
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
    }

    /// <summary>List icon when the grid shows, grid icon when the list shows.</summary>
    private void UpdateToggleGlyph() => ToggleGlyph.Glyph = ViewModel.ToggleLabel == "List View" ? "" : "";

    /// <summary>Switches grid/list.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnToggleView(object sender, RoutedEventArgs e) => ViewModel.ToggleViewCommand.Execute(null);

    /// <summary>Styles and loads art for a realized grid tile.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Prepared element.</param>
    private void OnGridPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (args.Element is not Grid tile || sender.ItemsSourceView?.GetAt(args.Index) is not ShopOfferItem item) return;
        SizeTile(tile);
        ApplyBadge(tile, item, "BadgePill", "BadgeLabel");
        ((ShopPulseRing)tile.FindName("ShopRing")).Apply(item.Pulse);
        AutomationProperties.SetAutomationId((FrameworkElement)tile.FindName("TileButton"), $"fst.shop.song.{item.Offer.SongId}");
        AutomationProperties.SetAutomationId((FrameworkElement)tile.FindName("ArtButton"), $"fst.shop.external.{item.Offer.SongId}");
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

    /// <summary>Styles and loads art for a realized list row.</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container info.</param>
    private void OnListContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.ItemContainer is not ListViewItem container || args.Item is not ShopOfferItem item) return;
        if (container.ContentTemplateRoot is not Grid row) return;
        if (artLoads.Remove(container, out var pending)) pending.Cancel();
        if (args.InRecycleQueue) return;
        AutomationProperties.SetName(container, item.Announcement);
        AutomationProperties.SetAutomationId(container, $"fst.shop.song.{item.Offer.SongId}");
        ApplyBadge(row, item, "BadgePill", "BadgeLabel");
        row.BorderBrush = BorderFor(item);
        row.BorderThickness = new Thickness(item.HasBadge ? 2 : 1);
        var image = (Image)row.FindName("Art");
        image.Source = null;
        _ = LoadArtAsync(container, image, item, 56);
    }

    /// <summary>Colors a New (gold on dark) or Leaving Tomorrow (white on red) badge.</summary>
    /// <param name="root">Template root.</param>
    /// <param name="item">Offer.</param>
    /// <param name="badgeName">Badge border name.</param>
    /// <param name="textName">Badge text name.</param>
    private static void ApplyBadge(FrameworkElement root, ShopOfferItem item, string badgeName, string textName)
    {
        if (root.FindName(badgeName) is not Border badge || root.FindName(textName) is not TextBlock text) return;
        badge.Background = item.IsLeaving ? Brush("FSTStatusRedBrush") : new SolidColorBrush(Windows.UI.Color.FromArgb(0xE6, 0x12, 0x18, 0x26));
        text.Foreground = item.IsLeaving ? new SolidColorBrush(Colors.White) : Brush("FSTGoldBrush");
        AutomationProperties.SetAutomationId(text, item.IsLeaving ? $"fst.shop.badge.leaving.{item.Offer.SongId}" : $"fst.shop.badge.new.{item.Offer.SongId}");
    }

    /// <summary>Accent border for an offer.</summary>
    /// <param name="item">Offer.</param>
    /// <returns>Brush.</returns>
    private static Brush BorderFor(ShopOfferItem item) => item.Highlight switch
    {
        ShopHighlight.LeavingTomorrow => Brush("FSTStatusRedBrush"),
        ShopHighlight.New => Brush("FSTGoldBrush"),
        _ => Brush("FSTCardStrokeBrush"),
    };

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
        artLoads[owner] = cancellation;
        var pixels = (int)Math.Ceiling(size * (XamlRoot?.RasterizationScale ?? 1));
        var bitmap = await ArtworkImages.LoadAsync(item.Offer.AlbumArt, pixels, cancellation.Token);
        if (!cancellation.IsCancellationRequested) image.Source = bitmap;
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
