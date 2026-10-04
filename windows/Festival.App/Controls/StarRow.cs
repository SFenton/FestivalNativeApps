using Festival.App.Services;
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
/// gold for six or more. One decoded bitmap per colour is shared app-wide. UI Automation sees one <c>Image</c> named
/// with the spoken count ("5 gold stars"), automation ID <c>fst.star-rating.&lt;state&gt;</c> and the state name as its
/// item status; rows that already speak their stars hide it with <see cref="AccessibilityView.Raw"/>.
/// </summary>
public sealed partial class StarRow : StackPanel
{
    /// <summary>Service star count (1–5 white, 6 or more gold; anything else draws nothing and collapses the row).</summary>
    public static readonly DependencyProperty StarsProperty = DependencyProperty.Register(
        nameof(Stars), typeof(int), typeof(StarRow), new PropertyMetadata(0, (d, _) => ((StarRow)d).Update()));

    /// <summary>Edge of each star image in epx (web <c>StarSize.icon</c> is 20; rows use 14–16).</summary>
    public static readonly DependencyProperty StarSizeProperty = DependencyProperty.Register(
        nameof(StarSize), typeof(double), typeof(StarRow), new PropertyMetadata(16.0, (d, _) => ((StarRow)d).Update()));

    private static BitmapImage? white;
    private static BitmapImage? gold;
    private StarRating? rating;

    /// <summary>Creates an empty, collapsed row.</summary>
    public StarRow()
    {
        Orientation = Orientation.Horizontal;
        Spacing = 2;
        VerticalAlignment = VerticalAlignment.Center;
        Visibility = Visibility.Collapsed;
        // The gold ring brush is set from code, so a contrast-theme switch must re-resolve it (theme-accessibility:
        // inline brush assignments do not follow {ThemeResource}).
        Loaded += (_, _) =>
        {
            ContrastTheme.Changed -= OnColorsChanged;
            ContrastTheme.Changed += OnColorsChanged;
            ApplyRing();
        };
        Unloaded += (_, _) => ContrastTheme.Changed -= OnColorsChanged;
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

    /// <summary>Exposes the row as one image with its spoken count (a bare panel has no automation peer).</summary>
    /// <returns>Automation peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new StarRowPeer(this);

    /// <summary>Re-resolves the gold ring on the UI thread after a system colour change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(ApplyRing);

    /// <summary>Rebuilds the images (only when the count or size changes; nothing runs while idle).</summary>
    private void Update()
    {
        Children.Clear();
        rating = StarRating.From(Stars);
        if (rating is not { } shown)
        {
            Visibility = Visibility.Collapsed;
            AutomationProperties.SetName(this, "");
            AutomationProperties.SetItemStatus(this, "");
            AutomationProperties.SetAutomationId(this, "");
            ToolTipService.SetToolTip(this, null);
            return;
        }
        var source = shown.Gold ? gold ??= Bitmap("star_gold.png") : white ??= Bitmap("star_white.png");
        var circle = Math.Round(StarSize * 1.25);
        for (var i = 0; i < shown.Count; i++)
        {
            var image = new Image { Source = source, Width = StarSize, Height = StarSize, Stretch = Stretch.Uniform };
            AutomationProperties.SetAccessibilityView(image, AccessibilityView.Raw);
            Children.Add(new Border
            {
                Width = circle,
                Height = circle,
                CornerRadius = new CornerRadius(circle / 2),
                Child = image,
            });
        }
        ApplyRing();
        AutomationProperties.SetName(this, shown.Announcement);
        AutomationProperties.SetItemStatus(this, shown.StateName);
        AutomationProperties.SetAutomationId(this, shown.AutomationId);
        ToolTipService.SetToolTip(this, shown.Announcement);
        Visibility = Visibility.Visible;
    }

    /// <summary>
    /// Rings gold stars with <c>FSTEmphasisBrush</c> (gold, or WindowText under a contrast theme). Only the ring changes:
    /// visibility belongs to the host (e.g. the profile tile hides its gold row below a six-star average).
    /// </summary>
    private void ApplyRing()
    {
        var ring = rating is { Gold: true } ? ContrastTheme.Brush("FSTEmphasisBrush") : null;
        foreach (var child in Children)
        {
            if (child is not Border circle) continue;
            circle.BorderBrush = ring;
            circle.BorderThickness = new Thickness(ring is null ? 0 : 1.5);
        }
    }

    /// <summary>Decodes a bundled star image once (sources are ~40 px).</summary>
    /// <param name="file">File under <c>Assets/Stars</c>.</param>
    /// <returns>Shared bitmap.</returns>
    private static BitmapImage Bitmap(string file) => new(new Uri($"ms-appx:///Assets/Stars/{file}")) { DecodePixelWidth = 40 };

    /// <summary>Image-typed peer with no children (the star images are decoration of the one named element).</summary>
    /// <param name="owner">Star row.</param>
    private sealed partial class StarRowPeer(StarRow owner) : FrameworkElementAutomationPeer(owner)
    {
        /// <inheritdoc />
        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Image;

        /// <inheritdoc />
        protected override string GetClassNameCore() => nameof(StarRow);

        /// <inheritdoc />
        protected override bool IsControlElementCore() => true;

        /// <inheritdoc />
        protected override IList<AutomationPeer>? GetChildrenCore() => null;
    }
}
#endregion
