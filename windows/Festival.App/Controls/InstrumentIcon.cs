using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Festival.App.Controls;

#region Instrument icon
/// <summary>Bundled instrument icon (copied from the Apple asset catalogue) with the instrument name as its label.</summary>
public sealed partial class InstrumentIcon : ContentControl
{
    /// <summary>Icon file name, e.g. <c>instrument_guitar.png</c>.</summary>
    public static readonly DependencyProperty FileProperty = DependencyProperty.Register(
        nameof(File), typeof(string), typeof(InstrumentIcon), new PropertyMetadata(null, (d, _) => ((InstrumentIcon)d).Update()));

    /// <summary>Accessible label, e.g. <c>Pro Lead</c>.</summary>
    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label), typeof(string), typeof(InstrumentIcon), new PropertyMetadata(null, (d, _) => ((InstrumentIcon)d).Update()));

    private static readonly Dictionary<string, BitmapImage> Shared = [];
    private readonly Image image = new() { Stretch = Microsoft.UI.Xaml.Media.Stretch.Uniform };

    /// <summary>Creates a 24 px icon.</summary>
    public InstrumentIcon()
    {
        Width = Height = 24;
        IsTabStop = false;
        Content = image;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
    }

    /// <summary>Icon file name.</summary>
    public string? File
    {
        get => (string?)GetValue(FileProperty);
        set => SetValue(FileProperty, value);
    }

    /// <summary>Accessible label.</summary>
    public string? Label
    {
        get => (string?)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    /// <summary>Resolves a shared decoded bitmap (icons are 144 px; decoded once at 72 px).</summary>
    private void Update()
    {
        AutomationProperties.SetName(this, Label ?? "");
        if (File is not { Length: > 0 } file) return;
        if (!Shared.TryGetValue(file, out var bitmap))
        {
            bitmap = new BitmapImage(new Uri($"ms-appx:///Assets/Instruments/{file}")) { DecodePixelWidth = 72 };
            Shared[file] = bitmap;
        }
        image.Source = bitmap;
    }
}
#endregion
