using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Windows.UI.Text;

namespace Festival.App.Controls;

#region Score badge
/// <summary>
/// x:Bind helpers for a leaderboard row's accuracy badge (web <c>AccuracyDisplay</c>): a full combo is the gold outline
/// badge (2 epx <c>#CFA500</c> stroke, gold bold italic text, skewed −8°, <c>goldOutlineSkew</c>); anything else is a pill
/// tinted red→green by accuracy at 25% opacity (<c>accuracyBgColor</c>). The score comes first; there is no separate FC chip.
/// </summary>
public static class ScoreBadge
{
    private static readonly SolidColorBrush Clear = new(Color.FromArgb(0, 0, 0, 0));

    /// <summary>Badge fill: transparent for FC, else the accuracy tint.</summary>
    /// <param name="fullCombo">Explicit FC.</param>
    /// <param name="expandedAccuracy">Accuracy in ten-thousandths of a percent.</param>
    /// <returns>Brush.</returns>
    public static Brush Fill(bool fullCombo, double expandedAccuracy)
    {
        if (fullCombo) return Clear;
        // Contrast themes: a ButtonFace pill (the accuracy is in the text), never the red→green tint.
        if (Services.ContrastTheme.IsOn) return Services.ContrastTheme.Brush("FSTNeutralPillFillBrush");
        var (r, g, b) = ScoreFormatting.AccuracyTint(expandedAccuracy);
        return new SolidColorBrush(Color.FromArgb(0x40, r, g, b));
    }

    /// <summary>Gold stroke for FC, else none.</summary>
    /// <param name="fullCombo">Explicit FC.</param>
    /// <returns>Brush.</returns>
    public static Brush Stroke(bool fullCombo) =>
        fullCombo ? Services.ContrastTheme.Brush("FSTEmphasisStrokeBrush")
        : Services.ContrastTheme.IsOn ? Services.ContrastTheme.Brush("FSTNeutralPillStrokeBrush") : Clear;

    /// <summary>Gold text for FC, else primary text.</summary>
    /// <param name="fullCombo">Explicit FC.</param>
    /// <returns>Brush.</returns>
    public static Brush Text(bool fullCombo) =>
        Services.ContrastTheme.Brush(fullCombo ? "FSTEmphasisBrush" : Services.ContrastTheme.IsOn ? "FSTNeutralPillTextBrush" : "FSTTextPrimaryBrush");

    /// <summary>Italic for FC.</summary>
    /// <param name="fullCombo">Explicit FC.</param>
    /// <returns>Font style.</returns>
    public static FontStyle Style(bool fullCombo) => fullCombo ? FontStyle.Italic : FontStyle.Normal;

    /// <summary>The web's <c>skewX(-8deg)</c> for FC, else none.</summary>
    /// <param name="fullCombo">Explicit FC.</param>
    /// <returns>Transform or <see langword="null"/>.</returns>
    public static Transform? Skew(bool fullCombo) => fullCombo ? new SkewTransform { AngleX = -8, CenterY = 10 } : null;
}
#endregion
