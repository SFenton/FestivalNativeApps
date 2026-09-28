using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Festival.App.Controls;

#region Illustration
/// <summary>
/// Static, decorative slide artwork: a brand gradient card with the slide's Segoe Fluent glyph and, for Item Shop
/// slides, the highlight colour the slide describes. No animation, so an off-screen FlipView page costs nothing.
/// The web's live per-slide demos are not ported yet (see <c>.agents/controls/first-run/windows.md</c>).
/// </summary>
public sealed partial class FirstRunIllustration : UserControl
{
    /// <summary>Slide ID dependency property.</summary>
    public static readonly DependencyProperty SlideIdProperty =
        DependencyProperty.Register(nameof(SlideId), typeof(string), typeof(FirstRunIllustration), new PropertyMetadata(null, (d, _) => ((FirstRunIllustration)d).Render()));

    private readonly FontIcon glyph = new() { FontSize = 56, Foreground = new SolidColorBrush(Colors.White) };
    private readonly Border card = new() { CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(2) };

    /// <summary>Creates the illustration.</summary>
    public FirstRunIllustration()
    {
        card.Child = glyph;
        Content = card;
        AutomationProperties.SetAccessibilityView(this, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
    }

    /// <summary>Slide ID.</summary>
    public string? SlideId
    {
        get => (string?)GetValue(SlideIdProperty);
        set => SetValue(SlideIdProperty, value);
    }

    /// <summary>Applies glyph and colours for the slide.</summary>
    private void Render()
    {
        var id = SlideId ?? "";
        glyph.Glyph = Glyph(id);
        var accent = id.Contains("leaving", StringComparison.Ordinal) ? Color.FromArgb(255, 0xE5, 0x48, 0x4D)
            : id.Contains("new", StringComparison.Ordinal) ? Color.FromArgb(255, 0xF5, 0xB7, 0x31)
            : id.Contains("shop", StringComparison.Ordinal) ? Color.FromArgb(255, 0x2E, 0xCC, 0x71)
            : Color.FromArgb(255, 0x7B, 0x5C, 0xF5);
        card.BorderBrush = new SolidColorBrush(accent);
        card.Background = new LinearGradientBrush
        {
            StartPoint = new Windows.Foundation.Point(0, 0),
            EndPoint = new Windows.Foundation.Point(1, 1),
            GradientStops =
            {
                new GradientStop { Color = Color.FromArgb(255, 0x1B, 0x14, 0x3A), Offset = 0 },
                new GradientStop { Color = Color.FromArgb(255, (byte)(accent.R / 3), (byte)(accent.G / 3), (byte)(accent.B / 3)), Offset = 1 },
            },
        };
    }

    /// <summary>Segoe Fluent Icons glyph for a slide.</summary>
    /// <param name="id">Slide ID.</param>
    /// <returns>Glyph.</returns>
    internal static string Glyph(string id) => id switch
    {
        _ when id.Contains("sort", StringComparison.Ordinal) => "",
        _ when id.Contains("filter", StringComparison.Ordinal) => "",
        _ when id.Contains("navigation", StringComparison.Ordinal) => "",
        _ when id.Contains("shop", StringComparison.Ordinal) || id.Contains("leaving", StringComparison.Ordinal) => "",
        _ when id.Contains("chart", StringComparison.Ordinal) || id.Contains("bar", StringComparison.Ordinal) => "",
        _ when id.Contains("paths", StringComparison.Ordinal) => "",
        _ when id.Contains("rank", StringComparison.Ordinal) || id.StartsWith("leaderboards", StringComparison.Ordinal) || id.Contains("percentile", StringComparison.Ordinal) => "",
        _ when id.StartsWith("rivals", StringComparison.Ordinal) || id.Contains("rivals", StringComparison.Ordinal) => "",
        _ when id.StartsWith("compete", StringComparison.Ordinal) => "",
        _ when id.StartsWith("suggestions", StringComparison.Ordinal) => "",
        _ when id.StartsWith("statistics", StringComparison.Ordinal) => "",
        _ when id.Contains("icons", StringComparison.Ordinal) => "",
        _ when id.Contains("metadata", StringComparison.Ordinal) => "",
        _ when id.StartsWith("playerhistory", StringComparison.Ordinal) || id.Contains("view-all", StringComparison.Ordinal) => "",
        _ => "",
    };
}
#endregion
