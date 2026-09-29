using System.ComponentModel;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Streams;
using Windows.UI;

namespace Festival.App.Controls;

#region Paths view
/// <summary>
/// CHOpt Paths content hosted in a modal <see cref="ContentDialog"/> (focus is contained and restored by the dialog):
/// selectors, the Karaoke warning, a zoomable image and an activation table in the saved column order.
/// </summary>
public sealed partial class SongPathsView : UserControl
{
    private static readonly (string Name, Color Color)[] Frets =
    [
        ("green", Color.FromArgb(255, 46, 204, 113)),
        ("red", Color.FromArgb(255, 231, 76, 60)),
        ("yellow", Color.FromArgb(255, 241, 196, 15)),
        ("blue", Color.FromArgb(255, 52, 152, 219)),
        ("orange", Color.FromArgb(255, 230, 126, 34)),
    ];

    private bool applyingZoom;

    /// <summary>Creates the view for a Paths session.</summary>
    /// <param name="viewModel">Paths model.</param>
    public SongPathsView(SongPathsViewModel viewModel)
    {
        ViewModel = viewModel;
        InitializeComponent();
        viewModel.PropertyChanged += OnViewModelChanged;
        // The notice is modal over the chart: start keyboard focus on OK.
        Loaded += (_, _) => { if (ViewModel.ShowWarning) WarningOk.Focus(FocusState.Programmatic); };
    }

    /// <summary>Paths model.</summary>
    public SongPathsViewModel ViewModel { get; }

    /// <summary>Decodes a new image and applies zoom changes.</summary>
    /// <param name="sender">View model.</param>
    /// <param name="e">Changed property.</param>
    private async void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(SongPathsViewModel.Image) when ViewModel.Image is { } picture:
                var bitmap = new BitmapImage { DecodePixelWidth = Math.Min(picture.Width, 4096), DecodePixelType = DecodePixelType.Physical };
                using (var stream = new InMemoryRandomAccessStream())
                {
                    await stream.WriteAsync(picture.Bytes.AsBuffer());
                    stream.Seek(0);
                    await bitmap.SetSourceAsync(stream);
                }
                if (!ReferenceEquals(picture, ViewModel.Image)) return;
                PathImage.Source = bitmap;
                FitImage();
                break;
            case nameof(SongPathsViewModel.Zoom) when !applyingZoom:
                ImageScroller.ChangeView(null, null, (float)ViewModel.Zoom);
                break;
        }
    }

    /// <summary>Fits the image to the viewport width (never upscaling past its pixel width).</summary>
    private void FitImage()
    {
        if (ViewModel.Image is not { } picture) return;
        var scale = XamlRoot?.RasterizationScale ?? 1;
        var available = Math.Max(1, ImageScroller.ActualWidth - 16);
        PathImage.Width = Math.Min(available, picture.Width / scale);
    }

    /// <summary>Refits on resize.</summary>
    /// <param name="sender">Scroller.</param>
    /// <param name="e">Size change.</param>
    private void OnImageScrollerSizeChanged(object sender, SizeChangedEventArgs e) => FitImage();

    /// <summary>Mirrors pinch / Ctrl+wheel zoom into the model.</summary>
    /// <param name="sender">Scroller.</param>
    /// <param name="e">View change.</param>
    private void OnImageViewChanged(object? sender, ScrollViewerViewChangedEventArgs e)
    {
        if (e.IsIntermediate) return;
        applyingZoom = true;
        ViewModel.Zoom = Math.Clamp(ImageScroller.ZoomFactor, SongPathsViewModel.MinZoom, SongPathsViewModel.MaxZoom);
        applyingZoom = false;
    }

    /// <summary>Zoom in one step.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnZoomIn(object sender, RoutedEventArgs e) => ViewModel.ZoomInCommand.Execute(null);

    /// <summary>Zoom out one step.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnZoomOut(object sender, RoutedEventArgs e) => ViewModel.ZoomOutCommand.Execute(null);

    /// <summary>Dismisses the notice (it won't return this app session).</summary>
    /// <param name="sender">OK button.</param>
    /// <param name="e">Unused.</param>
    private void OnWarningClosed(object sender, RoutedEventArgs e) => ViewModel.DismissWarning(false);

    /// <summary>Width below which the chart fills the sheet and the pickers share one bottom row.</summary>
    private const double CompactWidth = 560;

    /// <summary>Switches between the wide selector panel and the compact bottom row.</summary>
    /// <param name="sender">Root grid.</param>
    /// <param name="e">Size change.</param>
    private void OnRootSizeChanged(object sender, SizeChangedEventArgs e)
    {
        var compact = e.NewSize.Width < CompactWidth;
        Selectors.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        CompactSelectors.Visibility = compact ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>Dismisses the warning permanently.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnWarningDismissForever(object sender, RoutedEventArgs e) => ViewModel.DismissWarning(true);

    /// <summary>Builds one activation card's columns in the saved order.</summary>
    /// <param name="sender">Repeater.</param>
    /// <param name="args">Prepared element.</param>
    private void OnActivationPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        if (args.Element is not Border card || sender.ItemsSourceView?.GetAt(args.Index) is not PathActivationRow row) return;
        var heading = (TextBlock)card.FindName("Heading");
        heading.Text = $"Activation {row.Number}";
        AutomationProperties.SetAutomationId(heading, $"fst.paths.activation.{row.Number}");
        var grid = (Grid)card.FindName("Columns");
        grid.Children.Clear();
        grid.ColumnDefinitions.Clear();
        var columns = ViewModel.Columns;
        for (var i = 0; i < columns.Count; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(columns[i] == PathColumnKey.Note ? 1.4 : 1, GridUnitType.Star) });
            var cell = Cell(columns[i], row);
            Grid.SetColumn(cell, i);
            grid.Children.Add(cell);
        }
    }

    /// <summary>One labeled column cell.</summary>
    /// <param name="key">Column.</param>
    /// <param name="row">Activation.</param>
    /// <returns>Cell.</returns>
    private static FrameworkElement Cell(PathColumnKey key, PathActivationRow row)
    {
        var panel = new StackPanel { Spacing = 4 };
        var caption = key == PathColumnKey.Od ? "Overdrive %" : key.Label();
        panel.Children.Add(new TextBlock { Text = caption, Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"], Foreground = (Brush)Application.Current.Resources["FSTSecondaryTextBrush"] });
        switch (key)
        {
            case PathColumnKey.Note:
                var frets = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
                foreach (var (name, color) in Frets)
                {
                    frets.Children.Add(new Border
                    {
                        Width = 18, Height = 18, CornerRadius = new CornerRadius(5), BorderThickness = new Thickness(1),
                        BorderBrush = (Brush)Application.Current.Resources["FSTGlassBorderBrush"],
                        Background = row.HasFret(name) ? new SolidColorBrush(color) : (Brush)Application.Current.Resources["FSTAppBackgroundBrush"],
                    });
                }
                if (row.HasFret("open")) frets.Children.Add(new TextBlock { Text = "Open", FontSize = 11, FontWeight = Microsoft.UI.Text.FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center });
                AutomationProperties.SetName(frets, "Activation frets: " + row.FretsText);
                panel.Children.Add(frets);
                break;
            case PathColumnKey.Beat:
                panel.Children.Add(new TextBlock { Text = row.BeatText });
                break;
            case PathColumnKey.Time:
                panel.Children.Add(new TextBlock { Text = row.TimeText });
                break;
            case PathColumnKey.Od:
                var od = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
                if (row.OdPercent is { } amount)
                {
                    od.Children.Add(new ProgressBar
                    {
                        Value = amount, Maximum = 100, Width = 60, VerticalAlignment = VerticalAlignment.Center,
                        Foreground = (Brush)Application.Current.Resources["FSTGoldBrush"],
                    });
                    AutomationProperties.SetName(od.Children[0], "Overdrive");
                }
                od.Children.Add(new TextBlock { Text = row.OdText });
                panel.Children.Add(od);
                break;
            default:
                panel.Children.Add(new TextBlock { Text = row.ScoreText });
                break;
        }
        return panel;
    }
}
#endregion
