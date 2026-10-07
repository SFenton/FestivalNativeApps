using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region View all card
/// <summary>
/// The frosted "View all" card (pattern <c>surface-materials</c> R7; web <c>PlayerBandsSection</c>
/// <c>BandViewAllCard</c>): a full-width button on the canonical card surface (<c>FSTCardSurfaceBrush</c> and
/// <c>FSTCardStrokeBrush</c>, implicit style in <c>Themes/Styles.xaml</c>), at least 48 epx tall, with the Title Case
/// label and the in-card chevron centred together, 8 epx apart. Not the purple <c>FSTViewAllButtonStyle</c>, which is
/// the approved variant for leaderboard, song, ranking and rivals cards only. Consumers set the UIA name (it starts
/// with the label); the chevron is decorative.
/// </summary>
public sealed partial class ViewAllCard : Button
{
    /// <summary>Visible label, e.g. "View All Bands (18)".</summary>
    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label), typeof(string), typeof(ViewAllCard), new PropertyMetadata("", (d, e) => ((ViewAllCard)d).label.Text = e.NewValue as string ?? ""));

    private readonly TextBlock label = new()
    {
        FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
    };

    /// <summary>Creates the card with the card hover and press fills.</summary>
    public ViewAllCard()
    {
        var resources = Application.Current.Resources;
        Resources["ButtonBackgroundPointerOver"] = resources["FSTCardSurfacePointerOverBrush"];
        Resources["ButtonBackgroundPressed"] = resources["FSTCardSurfacePressedBrush"];
        Resources["ButtonBorderBrushPointerOver"] = resources["FSTCardStrokePointerOverBrush"];
        Resources["ButtonBorderBrushPressed"] = resources["FSTCardStrokeBrush"];
        AutomationProperties.SetAccessibilityView(label, AccessibilityView.Raw);
        var chevron = new FontIcon
        {
            Glyph = "\uE76C", FontSize = 12, VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)resources["FSTSecondaryTextBrush"],
        };
        AutomationProperties.SetAccessibilityView(chevron, AccessibilityView.Raw);
        // A centred grid rather than a horizontal stack, so a long label wraps at large text sizes.
        var row = new Grid
        {
            ColumnSpacing = 8, HorizontalAlignment = HorizontalAlignment.Center,
            ColumnDefinitions = { new ColumnDefinition(), new ColumnDefinition { Width = GridLength.Auto } },
            Children = { label, chevron },
        };
        Grid.SetColumn(chevron, 1);
        Content = row;
    }

    /// <summary>Visible label, e.g. "View All Bands (18)".</summary>
    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }
}
#endregion
