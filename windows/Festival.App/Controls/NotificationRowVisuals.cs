using Festival.Core.Data;
using Festival.Core.Domain;
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
/// the album art and the colour-coded flag chips (grouped per chart on multi-chart rows).
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

    /// <summary>A row's flag chips for a <see cref="StackPanel"/>: one wrapping line, or one line per chart group.</summary>
    public static readonly DependencyProperty FlagsProperty = DependencyProperty.RegisterAttached(
        "Flags", typeof(object), typeof(NotificationRowVisuals), new PropertyMetadata(null, OnFlagsChanged));

    /// <summary>Web <c>FLAG_GROUP_ICON_SIZE</c>.</summary>
    private const double FlagGroupIconSize = 20;

    /// <summary>Web <c>Gap.xs</c>: between pills, between group lines and after a group's icon.</summary>
    private const double FlagGap = 2;

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

    /// <summary>Gets the row whose flags the panel shows.</summary>
    /// <param name="element">Stack panel.</param>
    /// <returns>Presentation.</returns>
    public static object? GetFlags(DependencyObject element) => element.GetValue(FlagsProperty);

    /// <summary>Sets the row whose flags the panel shows.</summary>
    /// <param name="element">Stack panel.</param>
    /// <param name="value">A <see cref="NotificationPresentation"/>.</param>
    public static void SetFlags(DependencyObject element, object? value) => element.SetValue(FlagsProperty, value);

    /// <summary>
    /// Opaque flag pill brush (web <c>FLAG_COLORS</c>); under a Windows contrast theme the system pill fill
    /// (<c>FSTNeutralPillFillBrush</c>), so the pill's ButtonText label never sits on a brand hue.
    /// </summary>
    /// <param name="argb">Colour as <c>0xAARRGGBB</c>.</param>
    /// <returns>Brush.</returns>
    public static Brush FlagBrush(uint argb) => Services.ContrastTheme.IsOn
        ? Services.ContrastTheme.Brush("FSTNeutralPillFillBrush")
        : new SolidColorBrush(Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb));

    /// <summary>
    /// Rebuilds the text block's inlines; a statement-style message's blank-line clause breaks become line breaks (web
    /// <c>white-space: pre-line</c>). Text scaling and the row's Narrator name are unaffected.
    /// </summary>
    /// <param name="d">Text block.</param>
    /// <param name="e">Change.</param>
    private static void OnPartsChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not TextBlock block) return;
        block.Inlines.Clear();
        if (e.NewValue is not IEnumerable<NotificationMessagePart> parts) return;
        foreach (var part in parts)
        {
            var lines = part.Text.Split('\n');
            for (var i = 0; i < lines.Length; i++)
            {
                if (i > 0) block.Inlines.Add(new LineBreak());
                if (lines[i].Length == 0) continue;
                var run = new Run { Text = lines[i] };
                if (part.Emphasis) run.FontWeight = FontWeights.Bold;
                block.Inlines.Add(run);
            }
        }
    }

    /// <summary>
    /// Builds the flag chips (web <c>NotificationFlags</c>): multi-chart rows get one line per chart, a 20 epx decorative
    /// instrument icon then that chart's wrapping pills; other rows one wrapping line of pills. The pill labels stay text
    /// elements like the message; the row's Narrator name speaks them with their charts.
    /// </summary>
    /// <param name="d">Stack panel.</param>
    /// <param name="e">Change.</param>
    private static void OnFlagsChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not StackPanel panel) return;
        panel.Children.Clear();
        panel.Spacing = FlagGap;
        if (e.NewValue is not NotificationPresentation presentation) return;
        if (presentation.FlagGroups.Count == 0)
        {
            if (presentation.Flags.Count > 0) panel.Children.Add(Pills(presentation.Flags));
            return;
        }
        foreach (var group in presentation.FlagGroups)
        {
            var line = new Grid { ColumnSpacing = FlagGap };
            line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(FlagGroupIconSize) });
            line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var icon = new InstrumentIcon
            {
                File = group.Instrument.IconFile(), Width = FlagGroupIconSize, Height = FlagGroupIconSize, VerticalAlignment = VerticalAlignment.Center,
            };
            AutomationProperties.SetAccessibilityView(icon, AccessibilityView.Raw);
            var pills = Pills(group.Flags);
            pills.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(pills, 1);
            line.Children.Add(icon);
            line.Children.Add(pills);
            panel.Children.Add(line);
        }
    }

    /// <summary>One wrapping line of colour-coded pills (<c>FSTNotificationFlagPillStyle</c>, web <c>FLAG_COLORS</c>).</summary>
    /// <param name="flags">Flags.</param>
    /// <returns>Panel.</returns>
    private static WrapPanel Pills(IEnumerable<NotificationFlagKind> flags)
    {
        var resources = Application.Current.Resources;
        var wrap = new WrapPanel { HorizontalSpacing = FlagGap, VerticalSpacing = FlagGap };
        foreach (var flag in flags)
        {
            var pill = new Border
            {
                Style = (Style)resources["FSTNotificationFlagPillStyle"],
                Background = FlagBrush(flag.Argb()),
                Child = new TextBlock { Text = flag.Label(), Style = (Style)resources["FSTNotificationFlagTextStyle"] },
            };
            wrap.Children.Add(pill);
        }
        return wrap;
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
