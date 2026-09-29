using System.ComponentModel;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Player stat tile
/// <summary>
/// One player-page stat as its own card (web <c>StatBox</c> in a frosted grid cell): the value over an uppercase label,
/// centred. A linked tile is a button with an in-card trailing chevron (web <c>StatBox</c> chevron) and a 0.985 press
/// scale; a plain tile is one static element with no chevron. Loading values keep their final size, dimmed.
/// </summary>
public sealed partial class PlayerStatTileView : ContentControl
{
    /// <summary>Tile model.</summary>
    public static readonly DependencyProperty TileProperty = DependencyProperty.Register(
        nameof(Tile), typeof(PlayerStatTile), typeof(PlayerStatTileView), new PropertyMetadata(null, (d, e) => ((PlayerStatTileView)d).OnTileChanged(e)));

    private readonly TextBlock value = new()
    {
        FontSize = 20,
        FontWeight = FontWeights.Bold,
        TextAlignment = TextAlignment.Center,
        TextWrapping = TextWrapping.Wrap,
        HorizontalAlignment = HorizontalAlignment.Center,
    };

    private readonly StarRow stars = new() { Stars = 6, StarSize = 18, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly TextBlock label = new()
    {
        FontSize = 11,
        CharacterSpacing = 60,
        TextAlignment = TextAlignment.Center,
        TextWrapping = TextWrapping.Wrap,
        HorizontalAlignment = HorizontalAlignment.Center,
    };

    private readonly StackPanel body = new() { Spacing = 4, VerticalAlignment = VerticalAlignment.Center, Padding = new Thickness(12, 18, 12, 18) };
    private readonly Grid chrome = new() { MinHeight = 88 };
    private readonly FontIcon chevron = new()
    {
        Glyph = "",
        FontSize = 12,
        HorizontalAlignment = HorizontalAlignment.Right,
        VerticalAlignment = VerticalAlignment.Center,
        Margin = new Thickness(0, 0, 16, 0),
    };

    private Button? button;
    private Border? card;
    private bool? builtLinked;

    /// <summary>Creates the view.</summary>
    public PlayerStatTileView()
    {
        IsTabStop = false;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        label.Foreground = (Brush)Application.Current.Resources["FSTSecondaryTextBrush"];
        AutomationProperties.SetAccessibilityView(stars, AccessibilityView.Raw);
        AutomationProperties.SetAccessibilityView(chevron, AccessibilityView.Raw);
        body.Children.Add(value);
        body.Children.Add(stars);
        body.Children.Add(label);
        chrome.Children.Add(body);
        chrome.Children.Add(chevron);
    }

    /// <summary>Tile.</summary>
    public PlayerStatTile? Tile
    {
        get => (PlayerStatTile?)GetValue(TileProperty);
        set => SetValue(TileProperty, value);
    }

    /// <summary>Swaps the observed model.</summary>
    /// <param name="e">Change.</param>
    private void OnTileChanged(DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is PlayerStatTile old) old.PropertyChanged -= OnTilePropertyChanged;
        if (e.NewValue is PlayerStatTile tile) tile.PropertyChanged += OnTilePropertyChanged;
        builtLinked = null;
        Render();
    }

    /// <summary>Re-renders on value, tint, pending or link changes.</summary>
    /// <param name="sender">Tile.</param>
    /// <param name="e">Change.</param>
    private void OnTilePropertyChanged(object? sender, PropertyChangedEventArgs e) => Render();

    /// <summary>Applies the model; rebuilds the container only when the tile switches between button and plain.</summary>
    private void Render()
    {
        if (Tile is not { } tile) return;
        value.Text = tile.Value;
        value.Visibility = tile.ShowValue ? Visibility.Visible : Visibility.Collapsed;
        value.Foreground = PlayerBrushes.Tint(tile.Tint);
        value.Opacity = tile.IsPending ? 0.4 : 1;
        stars.Visibility = tile.GoldStars ? Visibility.Visible : Visibility.Collapsed;
        label.Text = tile.Label.ToUpperInvariant();
        chevron.Visibility = tile.IsLinked ? Visibility.Visible : Visibility.Collapsed;
        body.Padding = tile.IsLinked ? new Thickness(12, 18, 36, 18) : new Thickness(12, 18, 12, 18);
        if (builtLinked != tile.IsLinked) Build(tile.IsLinked);
        FrameworkElement host = (FrameworkElement?)button ?? card!;
        AutomationProperties.SetName(host, tile.Announcement);
        AutomationProperties.SetHelpText(host, tile.Hint);
        AutomationProperties.SetAutomationId(host, tile.AutomationId);
    }

    /// <summary>Hosts the content in a card button (linked) or a plain card.</summary>
    /// <param name="linked">Whether the tile is a link.</param>
    private void Build(bool linked)
    {
        builtLinked = linked;
        if (button is not null) button.Content = null;
        if (card is not null) card.Child = null;
        if (linked)
        {
            button ??= CreateButton();
            button.Content = chrome;
            card = null;
            Content = button;
        }
        else
        {
            card = new Border { Style = (Style)Application.Current.Resources["FSTCardStyle"], Padding = new Thickness(0), Child = chrome };
            AutomationProperties.SetAccessibilityView(card, AccessibilityView.Content);
            button = null;
            Content = card;
        }
    }

    /// <summary>Card-styled button with press feedback.</summary>
    /// <returns>Button.</returns>
    private Button CreateButton()
    {
        var created = new Button
        {
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Stretch,
            Padding = new Thickness(0),
            Background = (Brush)Application.Current.Resources["FSTCardSurfaceBrush"],
            BorderBrush = (Brush)Application.Current.Resources["FSTCardStrokeBrush"],
            BorderThickness = new Thickness(1),
            CornerRadius = (CornerRadius)Application.Current.Resources["OverlayCornerRadius"],
        };
        created.Resources["ButtonBackgroundPointerOver"] = new SolidColorBrush(Windows.UI.Color.FromArgb(0xD9, 0x1C, 0x24, 0x36));
        created.Resources["ButtonBackgroundPressed"] = new SolidColorBrush(Windows.UI.Color.FromArgb(0xD9, 0x16, 0x1D, 0x2C));
        created.Resources["ButtonBorderBrushPointerOver"] = new SolidColorBrush(Windows.UI.Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF));
        created.Click += (_, _) =>
        {
            if (Tile is { IsLinked: true, Link: { } link }) PlayerProfileView.OwnerOf(this)?.Follow(link);
        };
        return created;
    }
}
#endregion
