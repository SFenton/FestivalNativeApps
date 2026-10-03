using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Song art
/// <summary>
/// Decorative album-art thumbnail that loads itself through the shared bounded caches when <see cref="Art"/> changes
/// and cancels on change or unload. Hidden from UI Automation.
/// </summary>
public sealed partial class SongArt : ContentControl
{
    /// <summary>Song <c>albumArt</c> reference.</summary>
    public static readonly DependencyProperty ArtProperty = DependencyProperty.Register(
        nameof(Art), typeof(string), typeof(SongArt), new PropertyMetadata(null, (d, _) => ((SongArt)d).Reload()));

    private readonly Image image = new() { Stretch = Stretch.UniformToFill };
    private CancellationTokenSource? load;

    /// <summary>Creates a 44 px thumbnail.</summary>
    public SongArt()
    {
        Width = Height = 44;
        IsTabStop = false;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        Content = new Border
        {
            CornerRadius = new CornerRadius(6),
            Background = (Brush)Application.Current.Resources["FSTSurfaceMutedBrush"],
            Child = image,
        };
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        // Raw on the host does not hide its children: without this the image leaks as an unnamed Image (issue #200).
        AutomationProperties.SetAccessibilityView(image, AccessibilityView.Raw);
        Unloaded += (_, _) => load?.Cancel();
        Loaded += (_, _) =>
        {
            if (image.Source is null) Reload();
        };
    }

    /// <summary>Art reference.</summary>
    public string? Art
    {
        get => (string?)GetValue(ArtProperty);
        set => SetValue(ArtProperty, value);
    }

    /// <summary>Starts a decode at the current size and scale.</summary>
    private async void Reload()
    {
        load?.Cancel();
        image.Source = null;
        if (Art is not { Length: > 0 } art || XamlRoot is null) return;
        var cts = load = new CancellationTokenSource();
        var pixels = (int)Math.Ceiling(Width * XamlRoot.RasterizationScale);
        var bitmap = await ArtworkImages.LoadAsync(art, pixels, cts.Token);
        if (!cts.IsCancellationRequested) image.Source = bitmap;
    }
}
#endregion
