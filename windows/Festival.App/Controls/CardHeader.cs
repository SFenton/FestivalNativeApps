using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Card header
/// <summary>
/// The header that sits above (outside) a card, as on the web (<c>InstrumentHeader</c> in a card's <c>cardLabel</c>):
/// an optional 36 epx instrument icon, a white title (UIA heading) and an optional subtitle such as
/// "12,345 total entries". Band-size headers (Duos/Trios/Quads) have no icon. The icon is decorative; the title
/// carries the name.
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

    /// <summary>Automation ID of the title text.</summary>
    public static readonly DependencyProperty TitleAutomationIdProperty = DependencyProperty.Register(
        nameof(TitleAutomationId), typeof(string), typeof(CardHeader), new PropertyMetadata(null, (d, _) => ((CardHeader)d).Update()));

    /// <summary>UIA heading level of the title (default level 2).</summary>
    public static readonly DependencyProperty HeadingLevelProperty = DependencyProperty.Register(
        nameof(HeadingLevel), typeof(AutomationHeadingLevel), typeof(CardHeader),
        new PropertyMetadata(AutomationHeadingLevel.Level2, (d, _) => ((CardHeader)d).Update()));

    private readonly InstrumentIcon icon = new() { Width = 36, Height = 36, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock title = new();
    private readonly TextBlock subtitle = new();

    /// <summary>Creates the header.</summary>
    public CardHeader()
    {
        ColumnSpacing = 12;
        Padding = new Thickness(4, 0, 0, 0);
        ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        AutomationProperties.SetAccessibilityView(icon, AccessibilityView.Raw);
        title.Style = (Style)Application.Current.Resources["FSTCardHeaderTitleStyle"];
        subtitle.Style = (Style)Application.Current.Resources["FSTCardHeaderSubtitleStyle"];
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(title);
        text.Children.Add(subtitle);
        SetColumn(text, 1);
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
        var hasIcon = !string.IsNullOrEmpty(IconFile);
        icon.Visibility = hasIcon ? Visibility.Visible : Visibility.Collapsed;
        if (hasIcon)
        {
            icon.File = IconFile;
            icon.Label = Title;
        }
        ColumnSpacing = hasIcon ? 12 : 0;
    }
}
#endregion
