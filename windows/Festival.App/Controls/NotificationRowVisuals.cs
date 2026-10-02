using Festival.Core.Data;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Festival.App.Controls;

#region Notification row visuals
/// <summary>
/// Web <c>NotificationRow</c> pieces that XAML cannot bind directly: the message's bold runs, the instrument grid under
/// the album art and the colour-coded flag pill.
/// </summary>
public static class NotificationRowVisuals
{
    /// <summary>Web <c>SONG_GRID_ICON_SIZE</c>.</summary>
    private const double GridIconSize = 18;

    /// <summary>Web <c>songInstrumentGrid</c> gap.</summary>
    private const double GridGap = 3;

    /// <summary>Message runs for a <see cref="TextBlock"/>; emphasized runs are bold.</summary>
    public static readonly DependencyProperty PartsProperty = DependencyProperty.RegisterAttached(
        "Parts", typeof(object), typeof(NotificationRowVisuals), new PropertyMetadata(null, OnPartsChanged));

    /// <summary>Icon files laid out two per row in a <see cref="Grid"/> (decorative).</summary>
    public static readonly DependencyProperty IconFilesProperty = DependencyProperty.RegisterAttached(
        "IconFiles", typeof(object), typeof(NotificationRowVisuals), new PropertyMetadata(null, OnIconFilesChanged));

    /// <summary>Gets the message runs.</summary>
    /// <param name="element">Text block.</param>
    /// <returns>Runs.</returns>
    public static object? GetParts(DependencyObject element) => element.GetValue(PartsProperty);

    /// <summary>Sets the message runs.</summary>
    /// <param name="element">Text block.</param>
    /// <param name="value">Runs (<see cref="IEnumerable{T}"/> of <see cref="NotificationMessagePart"/>).</param>
    public static void SetParts(DependencyObject element, object? value) => element.SetValue(PartsProperty, value);

    /// <summary>Gets the grid's icon files.</summary>
    /// <param name="element">Grid.</param>
    /// <returns>Files.</returns>
    public static object? GetIconFiles(DependencyObject element) => element.GetValue(IconFilesProperty);

    /// <summary>Sets the grid's icon files.</summary>
    /// <param name="element">Grid.</param>
    /// <param name="value">Files (<see cref="IEnumerable{T}"/> of <see cref="string"/>).</param>
    public static void SetIconFiles(DependencyObject element, object? value) => element.SetValue(IconFilesProperty, value);

    /// <summary>Opaque flag pill brush (web <c>FLAG_COLORS</c>).</summary>
    /// <param name="argb">Colour as <c>0xAARRGGBB</c>.</param>
    /// <returns>Brush.</returns>
    public static Brush FlagBrush(uint argb) =>
        new SolidColorBrush(Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb));

    /// <summary>Rebuilds the text block's inlines; text scaling and the row's Narrator name are unaffected.</summary>
    /// <param name="d">Text block.</param>
    /// <param name="e">Change.</param>
    private static void OnPartsChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not TextBlock block) return;
        block.Inlines.Clear();
        if (e.NewValue is not IEnumerable<NotificationMessagePart> parts) return;
        foreach (var part in parts)
        {
            var run = new Run { Text = part.Text };
            if (part.Emphasis) run.FontWeight = FontWeights.Bold;
            block.Inlines.Add(run);
        }
    }

    /// <summary>Lays the icons out in two 18 epx columns with 3 epx gaps (web <c>songInstrumentGrid</c>).</summary>
    /// <param name="d">Grid.</param>
    /// <param name="e">Change.</param>
    private static void OnIconFilesChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not Grid grid) return;
        grid.Children.Clear();
        grid.RowDefinitions.Clear();
        grid.ColumnDefinitions.Clear();
        AutomationProperties.SetAccessibilityView(grid, AccessibilityView.Raw);
        var files = (e.NewValue as IEnumerable<string>)?.ToList() ?? [];
        if (files.Count == 0) return;
        grid.ColumnSpacing = grid.RowSpacing = GridGap;
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(GridIconSize) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(GridIconSize) });
        for (var i = 0; i < files.Count; i++)
        {
            if (i % 2 == 0) grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(GridIconSize) });
            var icon = new InstrumentIcon { File = files[i], Width = GridIconSize, Height = GridIconSize };
            AutomationProperties.SetAccessibilityView(icon, AccessibilityView.Raw);
            Grid.SetRow(icon, i / 2);
            Grid.SetColumn(icon, i % 2);
            grid.Children.Add(icon);
        }
    }
}
#endregion
