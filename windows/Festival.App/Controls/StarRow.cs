using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Festival.App.Controls;

#region Star row
/// <summary>
/// A score's stars as the bundled web star images (web <c>MiniStars</c>): 1–5 white stars, or five gold stars ringed in
/// gold for six. One decoded bitmap per colour is shared app-wide. Named for UI Automation ("5 gold stars"); rows that
/// already speak their stars hide it with <see cref="AccessibilityView.Raw"/>.
/// </summary>
public sealed partial class StarRow : StackPanel
{
    /// <summary>Service star count (1–6; anything else draws nothing and collapses the row).</summary>
    public static readonly DependencyProperty StarsProperty = DependencyProperty.Register(
        nameof(Stars), typeof(int), typeof(StarRow), new PropertyMetadata(0, (d, _) => ((StarRow)d).Update()));

    /// <summary>Edge of each star image in epx (web <c>StarSize.icon</c> is 20; rows use 14–16).</summary>
    public static readonly DependencyProperty StarSizeProperty = DependencyProperty.Register(
        nameof(StarSize), typeof(double), typeof(StarRow), new PropertyMetadata(16.0, (d, _) => ((StarRow)d).Update()));

    private static BitmapImage? white;
    private static BitmapImage? gold;

    /// <summary>Creates an empty, collapsed row.</summary>
    public StarRow()
    {
        Orientation = Orientation.Horizontal;
        Spacing = 2;
        VerticalAlignment = VerticalAlignment.Center;
        Visibility = Visibility.Collapsed;
        // contracts/product.json star-rating control; a page may still set a more specific fst.star-rating.* ID.
        AutomationProperties.SetAutomationId(this, "fst.stars");
    }

    /// <summary>Service star count.</summary>
    public int Stars
    {
        get => (int)GetValue(StarsProperty);
        set => SetValue(StarsProperty, value);
    }

    /// <summary>Star image edge in epx.</summary>
    public double StarSize
    {
        get => (double)GetValue(StarSizeProperty);
        set => SetValue(StarSizeProperty, value);
    }

    /// <summary>Rebuilds the images (only when the count or size changes; nothing runs while idle).</summary>
    private void Update()
    {
        Children.Clear();
        if (StarRating.From(Stars) is not { } rating)
        {
            Visibility = Visibility.Collapsed;
            AutomationProperties.SetName(this, "");
            return;
        }
        var source = rating.Gold ? gold ??= Bitmap("star_gold.png") : white ??= Bitmap("star_white.png");
        var ring = rating.Gold ? (Brush)Application.Current.Resources["FSTGoldBrush"] : null;
        var circle = Math.Round(StarSize * 1.25);
        for (var i = 0; i < rating.Count; i++)
        {
            var image = new Image { Source = source, Width = StarSize, Height = StarSize, Stretch = Stretch.Uniform };
            AutomationProperties.SetAccessibilityView(image, AccessibilityView.Raw);
            Children.Add(new Border
            {
                Width = circle,
                Height = circle,
                CornerRadius = new CornerRadius(circle / 2),
                BorderThickness = new Thickness(ring is null ? 0 : 1.5),
                BorderBrush = ring,
                Child = image,
            });
        }
        AutomationProperties.SetName(this, rating.Announcement);
        ToolTipService.SetToolTip(this, rating.Announcement);
        Visibility = Visibility.Visible;
    }

    /// <summary>Decodes a bundled star image once (sources are ~40 px).</summary>
    /// <param name="file">File under <c>Assets/Stars</c>.</param>
    /// <returns>Shared bitmap.</returns>
    private static BitmapImage Bitmap(string file) => new(new Uri($"ms-appx:///Assets/Stars/{file}")) { DecodePixelWidth = 40 };
}
#endregion
