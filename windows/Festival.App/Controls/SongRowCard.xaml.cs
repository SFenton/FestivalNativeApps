using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Festival.App.Controls;

#region Song row card
/// <summary>
/// The shared song row card used by every song list (Songs, Item Shop list), so the surface, art, marquee title and
/// subtitle, spacing and Item Shop pulse stay identical across pages. Pages bind <see cref="Title"/> and
/// <see cref="Subtitle"/>, then fill <see cref="Trailing"/> / <see cref="Secondary"/> and load <see cref="Art"/> during
/// phased realization. Decorative for UI Automation: the list item carries the row's name.
/// </summary>
public sealed partial class SongRowCard : UserControl
{
    /// <summary>Title (marquee when too long).</summary>
    public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(
        nameof(Title), typeof(string), typeof(SongRowCard), new PropertyMetadata("", (d, e) => ((SongRowCard)d).TitleText.Text = (string?)e.NewValue ?? ""));

    /// <summary>Secondary line (marquee when too long).</summary>
    public static readonly DependencyProperty SubtitleProperty = DependencyProperty.Register(
        nameof(Subtitle), typeof(string), typeof(SongRowCard), new PropertyMetadata("", (d, e) => ((SongRowCard)d).SubtitleText.Text = (string?)e.NewValue ?? ""));

    /// <summary>Art edge in epx (decode size for <see cref="Art"/>).</summary>
    public const double ArtSize = 44;

    /// <summary>Default bag outline/glyph colour (the app background, <c>#121826</c>).</summary>
    private static readonly Color BagInk = Color.FromArgb(0xFF, 0x12, 0x18, 0x26);

    /// <summary>Creates the card.</summary>
    public SongRowCard() => InitializeComponent();

    /// <summary>Title (marquee when too long).</summary>
    public string Title
    {
        get => (string)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    /// <summary>Secondary line, e.g. <c>artist · year · duration</c> (marquee when too long).</summary>
    public string Subtitle
    {
        get => (string)GetValue(SubtitleProperty);
        set => SetValue(SubtitleProperty, value);
    }

    /// <summary>Album art target.</summary>
    public Image Art => ArtImage;

    /// <summary>Trailing slot beside the text (metadata, chips, Shop badge, actions).</summary>
    public Panel Trailing => TrailingPanel;

    /// <summary>Wrapped second-row slot; show it with <see cref="SetWrapped"/>.</summary>
    public FlowPanel Secondary => SecondaryPanel;

    /// <summary>Clears art and both slots for a recycled row.</summary>
    public void Reset()
    {
        ArtImage.Source = null;
        TrailingPanel.Children.Clear();
        SecondaryPanel.Children.Clear();
        SetWrapped(false);
    }

    /// <summary>Shows or hides the second row; the art spans it only while it has content.</summary>
    /// <param name="wrapped">Second row has content.</param>
    public void SetWrapped(bool wrapped)
    {
        SecondaryPanel.Visibility = wrapped ? Visibility.Visible : Visibility.Collapsed;
        Grid.SetRowSpan(ArtHost, wrapped ? 2 : 1);
    }

    /// <summary>Shows the Item Shop pulse ring and, optionally, the bag on the art; <see langword="null"/> hides both.</summary>
    /// <param name="pulse">Pulse, or none.</param>
    /// <param name="showBag">Also show the bag (Songs); the Item Shop page names its state with text badges instead.</param>
    public void ApplyShop(SongRowShopPulse? pulse, bool showBag = true)
    {
        ShopRing.Apply(pulse);
        ShopBadge.Visibility = pulse is not null && showBag ? Visibility.Visible : Visibility.Collapsed;
        if (pulse is null || !showBag) return;
        // Contrast themes: Highlight / HighlightText instead of the brand gold/red bag.
        var contrast = Services.ContrastTheme.IsOn;
        ShopBadge.Background = contrast ? Services.ContrastTheme.Brush("FSTShopNewBrush")
            : new SolidColorBrush(Color.FromArgb(0xFF, (byte)(pulse.Argb >> 16), (byte)(pulse.Argb >> 8), (byte)pulse.Argb));
        var ink = contrast ? Services.ContrastTheme.Brush("FSTShopBadgeTextBrush") : new SolidColorBrush(BagInk);
        ShopBadge.BorderBrush = ink;
        ShopBadgeGlyph.Foreground = ink;
    }
}
#endregion
