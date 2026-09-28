using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Artwork thumbnail
/// <summary>
/// Decorative rounded album-art thumbnail for band song rows. Loads through the shared bounded caches, cancels when
/// the reference changes or the control unloads, and shows only the muted tile in Save Data mode.
/// </summary>
public sealed partial class BandsArtworkThumb : ContentControl
{
    /// <summary>Song <c>albumArt</c> reference.</summary>
    public static readonly DependencyProperty RawProperty = DependencyProperty.Register(
        nameof(Raw), typeof(string), typeof(BandsArtworkThumb), new PropertyMetadata(null, (d, _) => ((BandsArtworkThumb)d).Reload()));

    private readonly Image image = new() { Stretch = Stretch.UniformToFill };
    private CancellationTokenSource? load;

    /// <summary>Creates a 40 px thumbnail.</summary>
    public BandsArtworkThumb()
    {
        Width = Height = 40;
        IsTabStop = false;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAccessibilityView(this, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        Content = new Border
        {
            CornerRadius = new CornerRadius(6),
            Background = BandsResources.Brush("FSTSurfaceMutedBrush"),
            Child = image,
        };
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        Unloaded += (_, _) => load?.Cancel();
        Loaded += (_, _) => Reload();
    }

    /// <summary>Art reference.</summary>
    public string? Raw
    {
        get => (string?)GetValue(RawProperty);
        set => SetValue(RawProperty, value);
    }

    /// <summary>Starts (or cancels) the thumbnail load.</summary>
    private async void Reload()
    {
        load?.Cancel();
        image.Source = null;
        if (Raw is not { Length: > 0 } raw || !IsLoaded || App.Session.Settings.SaveData || App.Options.NoArt) return;
        load = new CancellationTokenSource();
        var token = load.Token;
        var pixels = (int)Math.Ceiling(Width * (XamlRoot?.RasterizationScale ?? 1));
        var bitmap = await ArtworkImages.LoadAsync(raw, pixels, token);
        if (!token.IsCancellationRequested) image.Source = bitmap;
    }
}
#endregion
