using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI.Text;

namespace Festival.App.Controls;

#region Rivals UI helpers
/// <summary>Compiled <c>x:Bind</c> function helpers for Rivals templates (brushes from <c>RivalsResources.xaml</c>).</summary>
public static class RivalsUi
{
    /// <summary>Row accent: green when the player leads overall, red otherwise.</summary>
    /// <param name="winning">Whether the player leads.</param>
    /// <returns>Brush.</returns>
    public static Brush Accent(bool winning) => Brush(winning ? "FSTRivalWinTextBrush" : "FSTRivalLoseTextBrush");

    /// <summary>Text colour for a song outcome.</summary>
    /// <param name="outcome">Outcome.</param>
    /// <returns>Brush.</returns>
    public static Brush OutcomeText(RivalSongOutcome outcome) => Brush(outcome switch
    {
        RivalSongOutcome.Winning => "FSTRivalWinTextBrush",
        RivalSongOutcome.Losing => "FSTRivalLoseTextBrush",
        _ => "FSTRivalTieTextBrush",
    });

    /// <summary>Pill fill for a song outcome.</summary>
    /// <param name="outcome">Outcome.</param>
    /// <returns>Brush.</returns>
    public static Brush OutcomeFill(RivalSongOutcome outcome) => Brush(outcome switch
    {
        RivalSongOutcome.Winning => "FSTRivalWinFillBrush",
        RivalSongOutcome.Losing => "FSTRivalLoseFillBrush",
        _ => "FSTRivalTieFillBrush",
    });

    /// <summary>Heading tint for a category sentiment.</summary>
    /// <param name="sentiment">Sentiment.</param>
    /// <returns>Brush.</returns>
    public static Brush Sentiment(RivalCategorySentiment sentiment) => Brush(sentiment switch
    {
        RivalCategorySentiment.Positive => "FSTRivalWinTextBrush",
        RivalCategorySentiment.Negative => "FSTRivalLoseTextBrush",
        _ => "FSTSectionHeaderBrush",
    });

    /// <summary>Semibold for the leading side, normal otherwise.</summary>
    /// <param name="leading">Whether this side leads.</param>
    /// <returns>Font weight.</returns>
    public static FontWeight Weight(bool leading) => leading ? FontWeights.Bold : FontWeights.Normal;

    /// <summary>Visible when <paramref name="value"/> is <see langword="false"/>.</summary>
    /// <param name="value">Flag.</param>
    /// <returns>Visibility.</returns>
    public static Visibility Not(bool value) => value ? Visibility.Collapsed : Visibility.Visible;

    /// <summary>Resolves a (theme) brush from application resources.</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Brush, or transparent when missing.</returns>
    private static Brush Brush(string key) =>
        Application.Current.Resources.TryGetValue(key, out var value) && value is Brush brush ? brush : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
}
#endregion
