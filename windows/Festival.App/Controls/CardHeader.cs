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
/// an instrument title share the same band. In a multi-column <see cref="LeaderboardsCardGridLayout"/> row every header
/// takes the row's tallest height (space above a shorter header's content), so titles and cards start on one line
/// (pattern <c>section-headers</c> R14, issue #657).
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
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
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
    /// The header's own height at its last measure (its content, or <see cref="FrameworkElement.MinHeight"/> when
    /// larger), without the row-alignment space above it.
    /// </summary>
    internal double NaturalHeight { get; private set; }

    /// <summary>
    /// Takes a grid row's header height by adding the shortfall above the content (<see cref="CardRowAlignment"/>);
    /// 0 removes it.
    /// </summary>
    /// <param name="rowHeight">The row's tallest header height, or 0 outside a multi-column row.</param>
    /// <returns><see langword="true"/> when the space changed, so the card must be measured again.</returns>
    internal bool AlignToRow(double rowHeight)
    {
        var top = CardRowAlignment.TopInset(rowHeight, NaturalHeight);
        if (Math.Abs(Padding.Top - top) < 0.5) return false;
        Padding = new Thickness(Padding.Left, top, Padding.Right, Padding.Bottom);
        return true;
    }

    /// <inheritdoc />
    protected override Size MeasureOverride(Size availableSize)
    {
        var size = base.MeasureOverride(availableSize);
        var minimum = double.IsNaN(MinHeight) ? 0 : MinHeight;
        NaturalHeight = Math.Max(size.Height - Padding.Top, minimum);
        // The alignment space sits above the whole natural height, MinHeight included, so the content keeps its usual
        // centring in the band below it.
        return new Size(size.Width, Math.Max(size.Height, Padding.Top + NaturalHeight));
    }
    #endregion
}
#endregion
