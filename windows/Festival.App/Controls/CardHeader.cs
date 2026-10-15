using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Card header
/// <summary>
/// The header that sits above (outside) a card, as on the web (<c>InstrumentHeader</c> in a card's <c>cardLabel</c>):
/// an optional 36 epx instrument icon, a white title (UIA heading) and an optional subtitle such as
/// "12,345 total entries". Band-size headers (Duos/Trios/Quads) have no icon. A combo board (issue #602) shows its
/// instruments' icons in a row above the title instead (web <c>CompeteScopeHeader</c>). Icons are decorative; the title
/// carries the name. With an icon or icon row, the title sits in a band at least the icon's height, so a combo title and
/// an instrument title share the same band. In a multi-column <see cref="LeaderboardsCardGridLayout"/> row each header is
/// padded above to the row's tallest icon row and below to the row's tallest title-and-subtitle part, so titles and
/// cards start on one line (pattern <c>section-headers</c> R14, issue #657).
/// </summary>
public sealed partial class CardHeader : Grid
{
    /// <summary>Title text.</summary>
    public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(
        nameof(Title), typeof(string), typeof(CardHeader), new PropertyMetadata("", (d, _) => ((CardHeader)d).Update()));

    /// <summary>Subtitle text (empty collapses it).</summary>
    public static readonly DependencyProperty SubtitleProperty = DependencyProperty.Register(
        nameof(Subtitle), typeof(string), typeof(CardHeader), new PropertyMetadata("", (d, _) => ((CardHeader)d).Update()));

    /// <summary>Instrument icon file (empty or null draws no icon).</summary>
    public static readonly DependencyProperty IconFileProperty = DependencyProperty.Register(
        nameof(IconFile), typeof(string), typeof(CardHeader), new PropertyMetadata(null, (d, _) => ((CardHeader)d).Update()));

    /// <summary>A combo's icon files: two or more draw a row of icons above the title in place of <see cref="IconFile"/>.</summary>
    public static readonly DependencyProperty IconFilesProperty = DependencyProperty.Register(
        nameof(IconFiles), typeof(object), typeof(CardHeader), new PropertyMetadata(null, (d, _) => ((CardHeader)d).Update()));

    /// <summary>Automation ID of the title text.</summary>
    public static readonly DependencyProperty TitleAutomationIdProperty = DependencyProperty.Register(
        nameof(TitleAutomationId), typeof(string), typeof(CardHeader), new PropertyMetadata(null, (d, _) => ((CardHeader)d).Update()));

    /// <summary>UIA heading level of the title (default level 2).</summary>
    public static readonly DependencyProperty HeadingLevelProperty = DependencyProperty.Register(
        nameof(HeadingLevel), typeof(AutomationHeadingLevel), typeof(CardHeader),
        new PropertyMetadata(AutomationHeadingLevel.Level2, (d, _) => ((CardHeader)d).Update()));

    private readonly InstrumentIcon icon = new() { Width = 36, Height = 36, VerticalAlignment = VerticalAlignment.Center };
    private readonly InstrumentIconRow iconRow = new() { Margin = new Thickness(0, 0, 0, 4) };
    private readonly MarqueeText title = new();
    private readonly MarqueeText subtitle = new();
    private readonly RowDefinition titleBand = new() { Height = new GridLength(1, GridUnitType.Star) };
    private readonly StackPanel text = new() { VerticalAlignment = VerticalAlignment.Center };

    /// <summary>Creates the header.</summary>
    public CardHeader()
    {
        ColumnSpacing = 12;
        Padding = new Thickness(4, 0, 0, 0);
        ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        RowDefinitions.Add(titleBand);
        AutomationProperties.SetAccessibilityView(icon, AccessibilityView.Raw);
        // Long titles scroll like the web's marquee headers (MarqueeText: only when they overflow and motion is on).
        title.TextStyle = (Style)Application.Current.Resources["FSTCardHeaderTitleStyle"];
        subtitle.TextStyle = (Style)Application.Current.Resources["FSTCardHeaderSubtitleStyle"];
        text.Children.Add(title);
        text.Children.Add(subtitle);
        SetColumnSpan(iconRow, 2);
        SetRow(icon, 1);
        SetRow(text, 1);
        SetColumn(text, 1);
        Children.Add(iconRow);
        Children.Add(icon);
        Children.Add(text);
        Update();
    }

    /// <summary>Title text.</summary>
    public string Title
    {
        get => (string)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    /// <summary>Subtitle text.</summary>
    public string Subtitle
    {
        get => (string)GetValue(SubtitleProperty);
        set => SetValue(SubtitleProperty, value);
    }

    /// <summary>Instrument icon file, or none.</summary>
    public string? IconFile
    {
        get => (string?)GetValue(IconFileProperty);
        set => SetValue(IconFileProperty, value);
    }

    /// <summary>A combo's icon files (two or more replace the single icon with a row above the title).</summary>
    public object? IconFiles
    {
        get => GetValue(IconFilesProperty);
        set => SetValue(IconFilesProperty, value);
    }

    /// <summary>Automation ID of the title text.</summary>
    public string? TitleAutomationId
    {
        get => (string?)GetValue(TitleAutomationIdProperty);
        set => SetValue(TitleAutomationIdProperty, value);
    }

    /// <summary>UIA heading level of the title.</summary>
    public AutomationHeadingLevel HeadingLevel
    {
        get => (AutomationHeadingLevel)GetValue(HeadingLevelProperty);
        set => SetValue(HeadingLevelProperty, value);
    }

    /// <summary>Applies the current values (runs only when a property changes).</summary>
    private void Update()
    {
        title.Text = Title ?? "";
        AutomationProperties.SetHeadingLevel(title, HeadingLevel);
        if (TitleAutomationId is { Length: > 0 } id) AutomationProperties.SetAutomationId(title, id);
        subtitle.Text = Subtitle ?? "";
        subtitle.Visibility = string.IsNullOrEmpty(Subtitle) ? Visibility.Collapsed : Visibility.Visible;
        var hasRow = IconFiles is IReadOnlyCollection<string> { Count: > 1 };
        iconRow.Files = hasRow ? IconFiles : null;
        var hasIcon = !hasRow && !string.IsNullOrEmpty(IconFile);
        icon.Visibility = hasIcon ? Visibility.Visible : Visibility.Collapsed;
        if (hasIcon)
        {
            icon.File = IconFile;
            icon.Label = Title;
        }
        ColumnSpacing = hasIcon ? 12 : 0;
        titleBand.MinHeight = hasIcon || hasRow ? icon.Height : 0;
    }

    #region Row alignment
    /// <summary>
    /// The header's own size at its last measure, without the row-alignment space: where its title starts (below the
    /// icon row and the band's centring space) and its whole height (its content, or
    /// <see cref="FrameworkElement.MinHeight"/> when larger).
    /// </summary>
    internal CardHeaderSize NaturalSize { get; private set; }

    /// <summary>
    /// Lines the header up with its grid row by adding space above and below its content (<see cref="CardRowAlignment"/>);
    /// zero insets remove it.
    /// </summary>
    /// <param name="insets">The space from <see cref="CardRowAlignment.Insets"/>, or zero outside a multi-column row.</param>
    /// <returns><see langword="true"/> when the space changed, so the card must be measured again.</returns>
    internal bool AlignToRow(CardHeaderInsets insets)
    {
        if (Math.Abs(Padding.Top - insets.Top) < 0.5 && Math.Abs(Padding.Bottom - insets.Bottom) < 0.5) return false;
        Padding = new Thickness(Padding.Left, insets.Top, Padding.Right, insets.Bottom);
        return true;
    }

    /// <inheritdoc />
    protected override Size MeasureOverride(Size availableSize)
    {
        var size = base.MeasureOverride(availableSize);
        var minimum = double.IsNaN(MinHeight) ? 0 : MinHeight;
        var inset = Padding.Top + Padding.Bottom;
        var natural = Math.Max(size.Height - inset, minimum);
        // The title band (Star row) takes the height below the icon row and centres the text in it, so a single-line
        // title under MinHeight starts lower than one with a subtitle.
        var row = iconRow.DesiredSize.Height;
        var band = Math.Max(natural - row, Math.Max(titleBand.MinHeight, text.DesiredSize.Height));
        NaturalSize = new CardHeaderSize(row + Math.Max(0, (band - text.DesiredSize.Height) / 2), natural);
        // The alignment space sits outside the whole natural height, MinHeight included, so the content keeps its usual
        // centring between them.
        return new Size(size.Width, Math.Max(size.Height, inset + natural));
    }
    #endregion
}
#endregion
